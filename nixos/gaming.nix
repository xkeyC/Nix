{ pkgs, ... }:

{
  # Steam 模块同时启用 32 位图形库，供 Steam 和 Windows 游戏使用。
  programs.steam = {
    enable = true;
    extraCompatPackages = [ pkgs.dwproton-bin ];
  };

  # ntsync：内核里的 NT 同步原语驱动，比 fsync 更贴近 Windows 的行为。内核编成了模块但默认
  # 不加载；加载后出现 /dev/ntsync（内核自己设成 0666），DW-Proton 的 wineserver 检测到就用
  # （日志里 “ntsync: up and running.”，PROTON_NO_NTSYNC=1 可以关掉）。
  boot.kernelModules = [ "ntsync" ];
}
