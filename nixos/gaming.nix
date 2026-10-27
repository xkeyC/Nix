{ pkgs, ... }:

{
  # Steam 模块同时启用 32 位图形库，供 Steam 和 Windows 游戏使用。
  programs.steam = {
    enable = true;
    extraCompatPackages = [ pkgs.dwproton-bin ];
  };

  # ntsync 是内核里的 NT 同步原语驱动，行为比 fsync 更接近 Windows。内核把它编译成了模块，但默认
  # 不加载；加载后会出现 /dev/ntsync（权限由内核设为 0666），DW-Proton 的 wineserver 检测到后会自动使用
  # （日志里会出现 “ntsync: up and running.”，设置 PROTON_NO_NTSYNC=1 可以关闭）。
  boot.kernelModules = [ "ntsync" ];
}
