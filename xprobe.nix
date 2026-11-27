# xprobe agent：给 xkeyc-linux-server 上的 xprobe hub（home.xkeyc.com）提供本机指标和推理服务负载。
# 项目：/mnt/application/Projects/xprobe（暂未发布；hub 部署见其 deploy/linux-server/）。
#
# 部署外的两样（不进 git）：
#   1. 二进制：主力机上构建后 scp 到 /srv/xprobe/xprobe（静态链接，root:root 0755）。
#      以后项目发布到 GitHub 再改成 flake 输入，去掉这个手工步骤。
#   2. token：与 hub 上 /etc/xprobe/395.token 相同的值，放在 /var/lib/xprobe/token（root:root 0600），
#      经 LoadCredential 交给服务。
{ ... }:

let
  port = 39100;
in
{
  systemd.services.xprobe-agent = {
    description = "xprobe agent (host metrics + halogen load for the xprobe hub)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "podman-halogen.service" ];
    serviceConfig = {
      # 推理服务：halogen 的 /metrics、/health、/cache（经 podman 发布的 8731，本机访问不受入站限制）。
      ExecStart = "/srv/xprobe/xprobe agent -listen :${toString port} -token-file %d/token -halogen http://127.0.0.1:8731";
      LoadCredential = "token:/var/lib/xprobe/token";
      DynamicUser = true;
      Restart = "always";
      RestartSec = 5;
      # 只读 /proc、/sys（amdgpu、hwmon）和 statfs，不需要写任何东西。
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    };
  };

  # agent 的 API 带 token，端口仍只对局域网和 tailnet 开放（hub 在 192.168.6.201 / 100.64.0.2）。
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p tcp --dport ${toString port} -s 192.168.0.0/16 -j nixos-fw-accept
    iptables -A nixos-fw -p tcp --dport ${toString port} -s 100.64.0.0/10 -j nixos-fw-accept
  '';
}
