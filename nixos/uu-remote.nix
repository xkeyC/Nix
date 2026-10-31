# UU 远程 Linux 被控端（非官方，uu-remote-linux）：让官方 Mac / Windows / 手机客户端远程控制本机。
#
# 打包见 packages/uu-remote-linux.nix。这里替代了上游 install.sh / deb 包所做的安装工作：
#   * uuremote-native.service：用户级服务，随 Plasma 图形会话启动。单元名不能改，
#     程序里的 `show`、托盘「退出」等会直接 `systemctl --user start/stop uuremote-native.service`。
#   * 开机自启：服务依附 Plasma 图形会话，开机停在登录界面时不会运行。因此自动登录
#     xkeyc，并让 Plasma 一启动就锁屏（kscreenlockerrc LockOnStart）；远程连接后用
#     官方客户端的「自动解锁被控端」（PAM 校验登录密码）进入桌面。
#     自动登录没有输入密码，KDE 钱包（pam_kwallet）不会自动解锁，首次访问时会弹出密码框。
#   * /dev/uinput 的 uaccess 规则：Wayland 下改用内核级的虚拟键盘鼠标，绕过 portal 授权，也解决键盘布局丢失符号的问题。
#     uaccess 只把权限授予当前在本机前登录的用户。
#
# 首次使用：桌面里运行 `uuremote-server login`，用 UU 远程 App 扫码（服务启动后也会自动弹出登录窗口）。
# 登录信息在 ~/.config/uuremote/config.json。日志：journalctl --user -u uuremote-native -f
# 排查：uuremote-server doctor
{ pkgs, ... }:

let
  uu-remote-linux = pkgs.callPackage ./packages/uu-remote-linux.nix { };

  # 要共享的显示器型号，取自 EDID（strings /sys/class/drm/card*-*/edid）。
  monitorModel = "PG32UCDM3";
  # 输出这个型号当前的逻辑坐标（x,y）：先按 EDID 找接口，再问 KDE 坐标。portal 的流只带坐标，没有型号。
  monitorPosition = pkgs.writeShellApplication {
    name = "uu-portal-monitor-position";
    runtimeInputs = [ pkgs.gnugrep pkgs.jq pkgs.kdePackages.libkscreen ];
    text = ''
      for edid in /sys/class/drm/card*-*/edid; do
        dir=''${edid%/edid}
        [ "$(cat "$dir/status")" = connected ] || continue
        grep -qaF ${pkgs.lib.escapeShellArg monitorModel} "$edid" || continue
        connector=''${dir##*/}
        connector=''${connector#card*-}
        position=$(kscreen-doctor -j | jq -er --arg name "$connector" \
          '.outputs[] | select(.name == $name and .enabled) | "\(.pos.x),\(.pos.y)"')
        echo "$position"
        exit 0
      done
      echo "显示器 ${monitorModel} 未连接" >&2
      exit 1
    '';
  };
in
{
  environment.systemPackages = [ uu-remote-linux ];

  systemd.user.services.uuremote-native = {
    description = "UU Remote Linux host (unofficial)";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    environment = {
      RUST_LOG = "info";
      # 只共享一块显示器（补丁功能，见 packages/uu-remote-linux.nix）。序号对应日志里的
      # "Portal monitor stream N: position=… size=…"；删掉这两行恢复上游行为（整个工作区）。
      # 每次连接都按 monitorModel 重新定位，序号只在定位失败时使用（流的顺序随接线变化）。
      UU_PORTAL_MONITOR_CMD = "${monitorPosition}/bin/uu-portal-monitor-position";
      UU_PORTAL_MONITOR = "1";
    };
    serviceConfig = {
      ExecStart = "${uu-remote-linux}/bin/uuremote-server";
      Restart = "always";
      RestartSec = 5;
    };
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "xkeyc";
  };
  # 用激活脚本写入，KDE 设置界面里仍可修改（「锁屏 → 登录后锁定」）。
  home-manager.users.xkeyc = { lib, pkgs, ... }: {
    home.activation.lockScreenOnStart = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kscreenlockerrc \
        --group Daemon --key LockOnStart --type bool true
    '';
  };

  boot.kernelModules = [ "uinput" ];
  services.udev.extraRules = ''
    KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess"
  '';
}
