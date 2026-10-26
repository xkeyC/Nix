# FlClash TUN 模式需要的特权 Helper。
#
# 官方 .deb 里的版本会在应用内用 pkexec/sudo 把 FlClashHelperService
# 安装成 systemd 服务（写到 /etc，属于命令式安装）。这里改用 NixOS
# 声明式服务提供同一个东西：开机以 root 运行，监听
# /run/flclash/helper.sock，由它拉起带 root euid 的 Core（TUN 需要）。
# 应用会先 ping 这个 socket，ready 后就不会再弹授权窗口。
{ config, lib, pkgs, ... }:

let
  flclash = pkgs.callPackage ./packages/flclash.nix { };
in
{
  systemd.services.flclash-helper = {
    description = "FlClash Helper (privileged core launcher for TUN mode)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "nftables.service" "iptables.service" ];
    unitConfig = {
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
    };
    serviceConfig = {
      Type = "simple";
      # Helper 要求 FLCLASH_HELPER_OWNER_UID/GID 指向调用者（非 root）；
      # 这里用 id 取 xkeyc 的运行时 UID/GID（NixOS 的 uid 在评估期是 null）。
      ExecStart = pkgs.writeShellScript "flclash-helper-start" ''
        export FLCLASH_HELPER_OWNER_UID="$(${pkgs.coreutils}/bin/id -u xkeyc)"
        export FLCLASH_HELPER_OWNER_GID="$(${pkgs.coreutils}/bin/id -g xkeyc)"
        exec ${flclash}/opt/FlClash/FlClashHelperService
      '';
      Group = config.users.users.xkeyc.group;
      RuntimeDirectory = "flclash";
      RuntimeDirectoryMode = "0755";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # TUN 需要内核 tun 模块（/dev/net/tun 一般已有，显式加载更稳）。
  boot.kernelModules = [ "tun" ];
}
