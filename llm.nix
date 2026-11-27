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

  # halogen 只发布容器镜像；Gufo 也可以用容器，这里用 Nix 包。
  virtualisation.podman.enable = true;

  # Gufo（v0.37.0 tag 的提交）。用 default 而不是 release：gufo.cachix.org 只缓存了 default
  # （release 多带官方 extension 和版本号，要本地编译 ROCm 相关部分）。
  environment.systemPackages = [ gufo ];
  nix.settings = {
    extra-substituters = [ "https://gufo.cachix.org" ];
    extra-trusted-public-keys = [ "gufo.cachix.org-1:rfZe3n4lHINgyoACKzs5EthIZmBNvEyCCtufUpth0PE=" ];
  };

  # 局域网访问推理 API：halogen 8731，Gufo 8080。
  networking.firewall.extraCommands = ''
    for port in 8731 8080; do
      iptables -A nixos-fw -p tcp --dport $port -s 192.168.0.0/16 -j nixos-fw-accept
      iptables -A nixos-fw -p tcp --dport $port -s 100.64.0.0/10 -j nixos-fw-accept
    done
  '';
}
