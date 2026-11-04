# FlydigiLinux：Linux 版飞智空间站，驱动 APEX 5 的力回馈扳机。
# 打包和模块都在 xkeyC/FlydigiLinux 的 flake 里，这里只负责启用。模块会：
#   * 加 udev 规则（飞智 vendor hidraw、/dev/uhid 给登录用户），加载 uhid；
#   * 用 security.wrappers 给 flydigid 加 CAP_SYS_PTRACE（XGameMonitor 读游戏内存，ptrace_scope=1 时需要）；
#   * 注册用户服务 flydigid（systemctl --user status flydigid），界面是 flydigi-gui。
# 数据：~/.local/share/flydigi-linux（游戏列表、官方 mod），~/.config/flydigi-linux（启用状态、GUI 语言）。
{ inputs, pkgs, ... }:

{
  imports = [ inputs.flydigi-linux.nixosModules.default ];

  programs.flydigi-linux = {
    enable = true;
    # F1 系列等原生 Windows 官方 mod 用 wine 运行（独立前缀，只走 UDP）
    wine = pkgs.wineWow64Packages.stable;
  };
}
