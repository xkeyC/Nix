# KDE Plasma 6：Wayland 优先，保留 XWayland 兼容；以及字体。
{ pkgs, ... }:

{
  services.displayManager.plasma-login-manager.enable = true;
  services.desktopManager.plasma6 = {
    enable = true;
    enableQt5Integration = true;
  };
  programs.xwayland.enable = true;
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
  ];
}
