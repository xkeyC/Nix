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
  # 主板 USB 声卡（MSI PRO X670-P 的 Realtek ALC4080）的光纤输出：alsa-ucm-conf 把它指到 PCM 3，
  # 那是 S/PDIF 端点上给 AC-3/DTS 码流直通用的 altset（FORMAT_TYPE_III），只有 16 bit，
  # 放普通 PCM 到 96 kHz 就爆音。同一端点的 PCM 2 才是普通 PCM（16/24 bit），改走它就不爆了（Windows 下本来就不爆）。
  services.pipewire.wireplumber.extraConfig."50-alc4080-spdif"."monitor.alsa.rules" = [
    {
      matches = [ { "node.name" = "alsa_output.usb-Generic_USB_Audio-00.HiFi__SPDIF__sink"; } ];
      actions.update-props."api.alsa.path" = "hw:Audio,2";
    }
  ];

  # PipeWire 靠 RTKit 把音频线程提到实时优先级；没有它就是普通线程，系统忙时容易断流。
  security.rtkit.enable = true;
}
