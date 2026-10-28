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
  # （44.1 kHz 的音乐就按 44.1 kHz 输出，不重采样）；正在播放时不切换采样率，之后开始的声音会被重采样。
  services.pipewire.extraConfig.pipewire."10-clock-rate"."context.properties" = {
    "default.clock.rate" = 48000;
    "default.clock.allowed-rates" = [ 44100 48000 88200 96000 176400 192000 ];
  };
  # 主板 USB 声卡（MSI PRO X670-P 的 Realtek ALC4080）的光纤输出：alsa-ucm-conf 把它指向 PCM 3，
  # 那是 S/PDIF 端点上供 AC-3/DTS 码流直通使用的 altset（FORMAT_TYPE_III），只支持 16 bit，
  # 用它播放 96 kHz 的普通 PCM 会爆音。同一端点的 PCM 2 才是普通 PCM（16/24 bit），改用它之后就不再爆音（Windows 下没有这个问题）。
  services.pipewire.wireplumber.extraConfig."50-alc4080-spdif"."monitor.alsa.rules" = [
    {
      matches = [ { "node.name" = "alsa_output.usb-Generic_USB_Audio-00.HiFi__SPDIF__sink"; } ];
      actions.update-props."api.alsa.path" = "hw:Audio,2";
    }
  ];

  # PipeWire 通过 RTKit 把音频线程提升到实时优先级；没有 RTKit 时只有普通优先级，系统繁忙时容易断流。
  security.rtkit.enable = true;

  # 显示器的 VRR 用「自动」（在系统设置里改，KDE 自己存在 kwinoutputconfig.json）：只有全屏窗口才开 VRR，
  # 桌面固定刷新率，和 Windows 的做法一样。「始终」在 4090 + 这两块屏上会让 OLED 闪烁，桌面静止或刷新率
  # 大幅跳动时显示器还会轮流黑屏几秒，内核和 KWin 日志里都没有记录。
  # Spectacle 的区域截图是一个全屏窗口，「自动」模式下会让 VRR 打开又关上，每次切换都黑一下；
  # 这里用窗口规则让它不触发 VRR。KWin 会把 kwinrulesrc 里新增的规则组自动加入规则列表，系统设置里也能看到和修改。
  home-manager.sharedModules = [
    ({ lib, ... }: {
      home.activation.spectacleNoVrr = lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatStringsSep "\n" (lib.mapAttrsToList (key: value: ''
          run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kwinrulesrc --group spectacle-no-vrr --key ${key} ${lib.escapeShellArg value}
        '') {
          Description = "Spectacle 不触发 VRR";
          wmclass = "org.kde.spectacle";
          wmclassmatch = "1"; # 完全匹配
          wmclasscomplete = "false";
          adaptivesync = "false";
          adaptivesyncrule = "2"; # 强制
        })
      );
    })
  ];
}
