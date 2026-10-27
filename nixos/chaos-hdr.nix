# Chaos HDR：给选中的 SDR 窗口（例如用 DW-Proton 运行的游戏）做 NVIDIA TrueHDR + 锐化。
#
# 打包见 packages/chaos-hdr.nix。替代上游安装脚本里的 install.py / desktop.py：
#   * chaos-hdr-effect：登录后通过 D-Bus 让 KWin 加载 truehdr_desktop 特效。
#     故意不写进 kwinrc 的 [Plugins]：加载只在本次会话生效，万一特效让 KWin
#     崩溃重启，它不会被自动再次加载，桌面不会卡在崩溃循环里。
#   * chaos-hdr-controls：注册 Alt+Z 全局快捷键，按下后通知特效打开侧栏。
# 数据目录：~/.local/share/chaos-hdr（画面配置、已授权窗口、状态文件）。
#
# 游戏方面的注意事项（DW-Proton）：
#   * 保持默认的 X11/XWayland；PROTON_ENABLE_WAYLAND=1 会让 Wine 把画面放进
#     子 surface，特效会跳过该窗口。
#   * 不要同时开启 PROTON_ENABLE_HDR / DXVK_HDR，游戏已经输出 HDR 时特效直接跳过。
#   * 不要在 gamescope 里运行。
{ pkgs, ... }:

let
  chaos-hdr = pkgs.callPackage ./packages/chaos-hdr.nix { };
  dataDir = "%h/.local/share/chaos-hdr";
in
{
  environment.systemPackages = [ chaos-hdr ];

  systemd.user.services.chaos-hdr-effect = {
    description = "Load the Chaos HDR KWin effect";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" "plasma-kwin_wayland.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.systemd}/bin/busctl --user call org.kde.KWin /Effects org.kde.kwin.Effects loadEffect s truehdr_desktop";
      ExecStop = "${pkgs.systemd}/bin/busctl --user call org.kde.KWin /Effects org.kde.kwin.Effects unloadEffect s truehdr_desktop";
    };
  };

  systemd.user.services.chaos-hdr-controls = {
    description = "Chaos HDR Alt+Z controls";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    environment.QT_QPA_PLATFORM = "wayland";
    serviceConfig = {
      Type = "simple";
      # 首次运行时用上游的默认画面配置；release.json 只用于界面里显示版本号。
      ExecStartPre = pkgs.writeShellScript "chaos-hdr-prepare" ''
        dir="''${XDG_DATA_HOME:-$HOME/.local/share}/chaos-hdr"
        ${pkgs.coreutils}/bin/mkdir -p -m 700 "$dir"
        [ -e "$dir/profile.json" ] || ${pkgs.coreutils}/bin/install -m 600 ${chaos-hdr}/share/chaos-hdr/profile.example.json "$dir/profile.json"
        ${pkgs.coreutils}/bin/install -m 644 ${chaos-hdr}/share/chaos-hdr/release.json "$dir/release.json"
      '';
      ExecStart = "${chaos-hdr}/bin/truehdr-panel ${dataDir}/profile.json --overlay-service";
      Restart = "on-failure";
      RestartSec = 2;
      TimeoutStopSec = 5;
    };
  };
}
