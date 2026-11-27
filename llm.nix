# 本机专门跑 LLM（halogen-flash-server / Gufo），按两者作者公开的 Strix Halo 主机配置调优。
#   halogen: https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/troubleshooting.md#the-host-settings-these-numbers-were-measured-on
#   Gufo:    https://github.com/gufo-org/toolboxes/blob/main/docs/host-configuration.md
#
# 前提：BIOS 里把 GPU 专用显存（UMA frame buffer）设成最小 512 MiB。GPU 通过 GTT 使用系统内存，
# 不再从 BIOS 预留（之前是 96 GiB VRAM，系统只剩 30 GiB）。
{ inputs, pkgs, ... }:

let
  gufo = inputs.gufo.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  boot.kernelParams = [
    # 128 GiB 内存：GTT 上限 124 GiB（RAM − 4 GiB），两个值是同一个大小的不同单位。
    "amdgpu.gttsize=126976"
    "ttm.pages_limit=32505856"
    # 关掉 IOMMU DMA 翻译：halogen 唯一实测过的项，prefill +13~16%。
    # 代价：整机没有 DMA 隔离，XDNA NPU 也不可用（本机只用 GPU）。
    "amd_iommu=off"
  ];
  # halogen 文档：amdgpu.vm_update_mode / noretry / sg_display 没测过收益，且 noretry=0 会把
  # 缺页错误变成无声挂起，建议不加；vm.compaction_proactiveness 保持默认。

  # 权重和 GPU 可见的主机缓冲区要 mlock；默认 8 MiB 时 GPU 会因内存整理卡顿数秒。
  systemd.settings.Manager.DefaultLimitMEMLOCK = "infinity";
  security.pam.loginLimits = [
    { domain = "*"; type = "soft"; item = "memlock"; value = "unlimited"; }
    { domain = "*"; type = "hard"; item = "memlock"; value = "unlimited"; }
  ];

  # amd-pstate active 模式下 performance governor 会把 EPP 也设为 performance。
  # 本机没有 ACPI platform_profile，功耗墙（TDP）只能在 BIOS 里调。
  powerManagement.cpuFreqGovernor = "performance";

  # ryzen_smu：让 ryzenadj 读（必要时改）SMU 的功耗墙。内核 STRICT_DEVMEM 挡住了 /dev/mem 回退路径。
  # 只装模块不会改任何设置；实测四种负载都卡在 120 W 持续 / ~140 W 短时。
  # GPU DPM 强制 high 实测无收益（prefill +0.2%，decode 不变，空闲 +6 W），保持 auto。
  # 功耗墙提到 140 W（BIOS 把 STAPM 封顶在 132 W，实际持续约 134 W）实测：30k prefill
  # 1,891 → 1,910 tok/s（+1%），decode 不变，温度 +3~4 °C。不值得，保持 BIOS 的 120 W，不持久化 ryzenadj 设置。
  hardware.cpu.amd.ryzen-smu.enable = true;

  # halogen 只发布容器镜像；Gufo 也可以用容器，这里用 Nix 包。
  virtualisation.podman.enable = true;

  # Gufo（v0.37.0 tag 的提交）。用 default 而不是 release：gufo.cachix.org 只缓存了 default
  # （release 多带官方 extension 和版本号，要本地编译 ROCm 相关部分）。
  nix.settings = {
    extra-substituters = [ "https://gufo.cachix.org" ];
    extra-trusted-public-keys = [ "gufo.cachix.org-1:rfZe3n4lHINgyoACKzs5EthIZmBNvEyCCtufUpth0PE=" ];
  };

  # 分级 prompt 缓存：内存一级 + SSD 二级（两个引擎各自的实现）。
  #   halogen：内存级就是 KV 池（HALOGEN_KV_POOL_POSITIONS，默认 2×CTX），SSD 级 HALOGEN_CACHE_DIR，
  #            每轮只写新增的注意力行，约 27 KiB/token，按 LRU 淘汰。
  #   Gufo：   内存级 --cache-ram-bytes（0 = 自动：可用内存一半、最多 32 GiB），SSD 级 --cache-disk，
  #            内存放不下的检查点降级到盘上，约 28 KB/token。
  # 缓存目录设 +C（btrfs nodatacow）：缓存文件反复覆盖写，COW 会产生碎片；halogen 还要求 direct I/O。
  # 缓存可丢，所以不要校验和也没关系。+C 只对新建的空目录/文件生效，由 tmpfiles 在创建时设置。
  systemd.tmpfiles.rules = [
    "d /srv/cache 0755 xkeyc users -"
    "h /srv/cache - - - - +C"
    # halogen 现在是 rootful 服务且 cap-drop all（容器里的 root 没有 DAC_OVERRIDE），目录必须归 root，
    # 否则 SSD 缓存层 Permission denied 直接关闭。
    "d /srv/cache/halogen 0700 root root -"
    "d /srv/cache/gufo 0755 xkeyc users -"
    # tmpfiles 先建目录再设属性，子目录不会从父目录继承，所以逐个设置。
    "h /srv/cache/halogen - - - - +C"
    "h /srv/cache/gufo - - - - +C"
    "d /srv/cache/halogen-work 0755 xkeyc users -"
  ];

  # halogen 常驻服务见 halogen.nix（podman-halogen.service，开机自启）。gufo-serve 手动起：
  #   systemctl stop podman-halogen; systemd-run --user --unit=gufo gufo-serve   （两者内存装不下同时跑）
  #
  # 动态上下文：上下文设成原生 262,144，它只是「单个请求的上限」，内存按实际用量占：
  #   halogen：KV 池 786,432 个位置（约 28 KiB/个，3 个完整 262k）由所有请求共享，每个请求按
  #            提示+max_tokens 借用。这是甜点值：v2 检查点（62 GiB）在默认 20 GiB 预留下正好装得下（GGUF 用 524,288），
  #            不挤占 n-gram 表的页缓存；再大就得压 HALOGEN_HOST_RESERVE_GIB（长提示会读盘变慢）或开 KV8。
  #   Gufo：   每个 session 按完整上下文预留（约 27.5 KiB/token），2 个 session 约 13.7 GiB；
  #            Flash-Next 上超出的 session 共享内存，放得下才开跑。
  environment.systemPackages = [
    gufo
    pkgs.ryzenadj
    (pkgs.writeShellScriptBin "halogen-tool" ''
      # 用法：halogen-tool 检查点 模式 [参数…]   跑 halogen 镜像自带的检查工具（rootless，不起服务）
      #   halogen-tool X.hgn verify X.hgn / inspect X.hgn / ppl X.hgn --corpus … / niah X.hgn …
      #   检查点：/srv/models 下 GGUF 的任一分片，或 .hgn（n-gram 表按标准名放在它旁边）
      # 常驻服务是 podman-halogen.service（halogen.nix），两者别同时跑：内存装不下。
      # --network=none：闭源二进制，工具模式完全不需要网络。
      # /srv/models 按原路径只读挂入；/work 可写（参考 dump 等）。别挂到容器的 /halogen：那是镜像自己的程序目录。
      # 宿主机上设置的任何 HALOGEN_* 都按值传进容器（如 HALOGEN_KV_POOL_POSITIONS、HALOGEN_KV8）。
      set -eu
      [ $# -ge 2 ] || { echo "用法：halogen-tool 检查点 模式 [参数…]" >&2; exit 2; }
      ckpt=$1; shift
      extra=()
      # GGUF 不带 halogen 能跑的草稿头，用官方的；.hgn 自带。
      case "$ckpt" in *.gguf) extra+=(-e HALOGEN_MTP_HEAD=/srv/models/halogen/qwen38-flash-next-mtp.hgn) ;; esac
      for v in $(compgen -e | grep '^HALOGEN_' || true); do extra+=(-e "$v=''${!v}"); done
      exec ${pkgs.podman}/bin/podman run --rm --replace --name halogen-tool --network=none "''${extra[@]}" \
        --device /dev/kfd --device /dev/dri --group-add keep-groups \
        --ipc=host --ulimit memlock=-1:-1 --cap-drop=all --security-opt=no-new-privileges \
        -e HALOGEN_CHECKPOINT="$ckpt" \
        -e HALOGEN_TOKENIZER=/srv/models/halogen/tokenizer \
        -v /srv/models:/srv/models:ro \
        -v /srv/cache/halogen-work:/work \
        ghcr.io/peonist-ai/halogen-flash-server:0.21.0 "$@"
    '')
    (pkgs.writeShellScriptBin "gufo-serve" ''
      # 用法：gufo-serve [GGUF 首个分片] [MTP 头]
      set -eu
      model=''${1:-/srv/models/unsloth-UD-Q4_K_XL/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf}
      mtp=''${2:-/srv/models/unsloth-UD-Q4_K_XL/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf}
      exec ${gufo}/bin/gufo serve llm --host 0.0.0.0 --port 8080 \
        --served-model-name flash-next \
        --model "$model" --speculative mtp --mtp-model "$mtp" \
        --context "''${GUFO_CONTEXT:-262144}" --sessions "''${GUFO_SESSIONS:-2}" \
        --cache-ram-bytes "''${GUFO_CACHE_RAM_BYTES:-0}" \
        --cache-disk /srv/cache/gufo \
        --cache-disk-bytes "''${GUFO_CACHE_DISK_BYTES:-137438953472}" \
        --reasoning-effort "''${GUFO_REASONING_EFFORT:-medium}"
    '')
  ];

  # 局域网 / tailnet 访问 Gufo 的 API（8080）。halogen 的 8731 在 halogen.nix 里限制。
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p tcp --dport 8080 -s 192.168.0.0/16 -j nixos-fw-accept
    iptables -A nixos-fw -p tcp --dport 8080 -s 100.64.0.0/10 -j nixos-fw-accept
  '';
}
