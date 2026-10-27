# KDE Plasma 6：Wayland 优先，保留 XWayland 兼容；以及字体、音频采样率。
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

  # 音频：PipeWire 由 Plasma 默认启用，默认把所有声音重采样到 48 kHz。
  # 放开主板 USB 声卡支持的全部采样率：声卡空闲时按第一个开始播放的音源切换
  # （44.1 kHz 的音乐就按 44.1 kHz 输出，不重采样）；正在播放时不换档，后来的声音会被重采样。
  services.pipewire.extraConfig.pipewire."10-clock-rate"."context.properties" = {
    "default.clock.rate" = 48000;
    "default.clock.allowed-rates" = [ 44100 48000 88200 96000 176400 192000 ];
  };
}
