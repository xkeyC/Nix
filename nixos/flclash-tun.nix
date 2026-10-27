# FlClash TUN 模式需要的特权 Helper。
#
# 官方 .deb 里的版本会在应用内用 pkexec/sudo 把 FlClashHelperService
# 安装成 systemd 服务（写到 /etc，属于命令式安装）。这里改用 NixOS
# 声明式服务提供同样的功能：开机以 root 运行，监听
# /run/flclash/helper.sock，由它启动 euid 为 root 的 Core（TUN 模式需要）。
# 应用会先 ping 这个 socket，确认就绪后不会再弹出授权窗口。
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
      # 这里用 id 获取 xkeyc 的运行时 UID/GID（NixOS 的 uid 在评估期是 null）。
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

  # TUN 模式需要内核的 tun 模块（/dev/net/tun 一般已经存在，显式加载更可靠）。
  boot.kernelModules = [ "tun" ];
}
