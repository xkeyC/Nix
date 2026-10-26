{ pkgs, ... }:

{
  # Steam 模块同时启用 32 位图形库，供 Steam 和 Windows 游戏使用。
  programs.steam = {
    enable = true;
    extraCompatPackages = [ pkgs.dwproton-bin ];
  };
}
