# halogen-flash-server：开机自启的默认推理服务（OpenAI / Anthropic 兼容 API，:8731）。
#
# halogen 是闭源二进制，按不完全可信处理：
#   * 出站：容器在专用桥接网络 halogen0 上，mangle PREROUTING 丢弃从 halogen0 进来的所有新建连接
#     （conntrack NEW），容器只能回复别人发起的连接，主动连公网、局域网代理、宿主机都不行（v4 / v6）。
#     本来 HALOGEN_DOWNLOAD 不设它就不联网，这一层是不靠它自觉的保证。
#   * 入站：只有局域网（192.168.0.0/16）和 tailnet（100.64.0.0/10）能访问 8731。
#     rootful podman 的端口走 DNAT → FORWARD，不经过 nixos-fw 的 INPUT 规则，所以在 mangle 里单独限制。
#   * 容器去掉所有 capabilities，no-new-privileges；--ipc=host 是 GPU 运行时硬性要求（官方 compose：
#     去掉它启动即崩，shm_size 替代不了），只能保留。
#   * 镜像不联网拉取（pull = never），启动前核对镜像 ID，防止被替换。
# 为什么不用 rootless：rootless 的网络走 pasta，容器流量在宿主机上就是普通进程的流量，没法按网卡拦。
{ lib, pkgs, ... }:

let
  image = "ghcr.io/peonist-ai/halogen-flash-server:0.21.0";
  # 升级镜像：在别处 pull 新版本后 `podman save | sudo podman load` 导入 root 的存储，再改这两行。
  imageId = "d01627c8411dfc93e757901763c7e40ab7c6ab9706cb15f6ad3138a857773aef";

  # Quat3rnion 的 v2-abliterated（bf16-to-hgn 原生 v2），配官方 n-gram 表（5cc17cea），同目录按标准名放。
  # 实测：verify PASS、4.16 bpw、PPL 3.988（unsloth UD-IQ4_XS 3.855）、niah 24/27（GGUF 23/27）。
  checkpoint = "/srv/models/halogen-abliterated/qwen38-flash-next-v2-abliterated.hgn";

  net = { name = "halogen"; iface = "halogen0"; subnet = "10.89.100.0/24"; };
  port = 8731;
  allowedSources = { v4 = [ "192.168.0.0/16" "100.64.0.0/10" ]; v6 = [ "fd7a:115c:a1e0::/48" ]; };

  podman = "${pkgs.podman}/bin/podman";
in
{
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.halogen = {
    inherit image;
    pull = "never";
    autoStart = true;
    networks = [ net.name ];
    ports = [ "0.0.0.0:${toString port}:${toString port}" ];
    devices = [ "/dev/kfd" "/dev/dri" ];
    volumes = [
      "/srv/models:/srv/models:ro"
      "/srv/cache/halogen:/cache" # SSD 级 prompt 缓存
    ];
    environment = {
      HALOGEN_CHECKPOINT = checkpoint;
      HALOGEN_TOKENIZER = "/srv/models/halogen/tokenizer";
      # 动态上下文：单个请求最多原生 262k；786,432 个位置的共享 KV 池 = 3 个完整 262k（见 llm.nix 的说明）。
      HALOGEN_CTX = "262144";
      HALOGEN_KV_POOL_POSITIONS = "786432";
      HALOGEN_CACHE_DIR = "/cache";
      HALOGEN_CACHE_DISK_GIB = "128";
      # 请求没指定时的思考档位。模板默认 xhigh（想得很久）；medium 实测 99k 首个答案只比关思考晚约 3 s。
      HALOGEN_REASONING_EFFORT = "medium";
    };
    extraOptions = [
      "--ipc=host"
      "--ulimit=memlock=-1:-1"
      "--cap-drop=all"
      "--security-opt=no-new-privileges"
      "--stop-timeout=60" # 停止时把最后一轮的 SSD 缓存刷完
    ];
  };

  systemd.services.podman-halogen = {
    requires = [ "podman-network-halogen.service" ];
    after = [ "podman-network-halogen.service" ];
    preStart = ''
      id=$(${podman} image inspect --format '{{.Id}}' ${image})
      if [ "$id" != "${imageId}" ]; then
        echo "halogen 镜像 ID 不符：$id（期望 ${imageId}）" >&2
        exit 1
      fi
    '';
    # halogen 文档：进程异常退出后驱动可能扣着 GTT 不放，之后每次启动都会卡住，restart=always 会变成死循环。
    serviceConfig = {
      Restart = lib.mkForce "on-failure";
      RestartSec = "30s";
      TimeoutStopSec = lib.mkForce "90s";
    };
    startLimitBurst = 3;
    startLimitIntervalSec = 900;
  };

  systemd.services.podman-network-halogen = {
    description = "Podman network for halogen (egress blocked by firewall)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      ${podman} network exists ${net.name} || \
        ${podman} network create --interface-name ${net.iface} --subnet ${net.subnet} --disable-dns ${net.name}
    '';
  };

  # 出站封锁 + 入站来源限制。mangle 表不归 nixos-fw 管，所以用自己的链，每次先清空再填，避免重复。
  networking.firewall.extraCommands = ''
    for ipt in iptables ip6tables; do
      # 出站：halogen0 上只放行已建立连接的回包，新建连接一律丢弃。
      $ipt -t mangle -N halogen-egress 2>/dev/null || true
      $ipt -t mangle -F halogen-egress
      $ipt -t mangle -A halogen-egress -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
      $ipt -t mangle -A halogen-egress -j DROP
      $ipt -t mangle -C PREROUTING -i ${net.iface} -j halogen-egress 2>/dev/null || \
        $ipt -t mangle -I PREROUTING -i ${net.iface} -j halogen-egress
      # 入站：发往本机 ${toString port} 端口的只放行局域网和 tailnet。
      $ipt -t mangle -N halogen-ingress 2>/dev/null || true
      $ipt -t mangle -F halogen-ingress
    done
    ${lib.concatMapStrings (s: "iptables -t mangle -A halogen-ingress -s ${s} -j RETURN\n") allowedSources.v4}
    ${lib.concatMapStrings (s: "ip6tables -t mangle -A halogen-ingress -s ${s} -j RETURN\n") allowedSources.v6}
    for ipt in iptables ip6tables; do
      $ipt -t mangle -A halogen-ingress -j DROP
      $ipt -t mangle -C PREROUTING -p tcp --dport ${toString port} -m addrtype --dst-type LOCAL -j halogen-ingress 2>/dev/null || \
        $ipt -t mangle -I PREROUTING -p tcp --dport ${toString port} -m addrtype --dst-type LOCAL -j halogen-ingress
    done
  '';
  networking.firewall.extraStopCommands = ''
    for ipt in iptables ip6tables; do
      $ipt -t mangle -D PREROUTING -i ${net.iface} -j halogen-egress 2>/dev/null || true
      $ipt -t mangle -D PREROUTING -p tcp --dport ${toString port} -m addrtype --dst-type LOCAL -j halogen-ingress 2>/dev/null || true
    done
  '';
}
