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
  # 「自动」下 VRR 打开没问题，关闭时两块屏都会黑一下（退出全屏、全屏时去操作另一块屏），是 NVIDIA 驱动的问题。
  # 所以只给游戏开 VRR（白名单），减少开关次数；网页全屏、mpv、Spectacle 的区域截图都不再触发。
  #
  # 用 KWin 窗口规则实现：同一个窗口匹配多条规则时，按 Order 的顺序第一条设置了「自适应同步」的规则生效。
  #   * vrr-allow-games：Steam 里的游戏（Proton 把窗口类别设成 steam_app_<ID>，非 Steam 游戏加进 Steam 也一样）
  #     和不经过 Steam 运行的 Wine / Proton 程序（窗口类别是 exe 文件名）；「不影响」= 保持默认，全屏时才开 VRR。
  #   * vrr-deny-others：匹配其余所有窗口，强制不开 VRR，排在最后。
  # 其他游戏的窗口类别可在「系统设置 → 窗口规则 → 检测窗口属性」里查看，加到 wmclass 的正则里。
  # 每次激活都会重排 Order：白名单在最前、兜底规则在最后，自己在系统设置里加的规则保持原有顺序排在中间。
  home-manager.sharedModules = [
    ({ lib, ... }: {
      home.activation.vrrWhitelist = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        kwrite=${pkgs.kdePackages.kconfig}/bin/kwriteconfig6
        kread=${pkgs.kdePackages.kconfig}/bin/kreadconfig6
        setRule() {
          local group=$1
          shift
          while [ $# -gt 0 ]; do
            run $kwrite --file kwinrulesrc --group "$group" --key "$1" "$2"
            shift 2
          done
        }
        # wmclassmatch：0 不重要 / 3 正则；adaptivesyncrule：1 不影响 / 2 强制
        setRule vrr-allow-games Description "游戏：全屏时开 VRR" wmclass '^steam_app_|\.exe$' \
          wmclassmatch 3 wmclasscomplete false adaptivesyncrule 1
        setRule vrr-deny-others Description "其他窗口：不开 VRR" wmclassmatch 0 adaptivesync false adaptivesyncrule 2
        # 旧版只给 Spectacle 关 VRR 的规则（黑名单）
        for key in Description wmclass wmclassmatch wmclasscomplete adaptivesync adaptivesyncrule; do
          run $kwrite --file kwinrulesrc --group spectacle-no-vrr --key $key --delete
        done
        order=$($kread --file kwinrulesrc --group General --key Order)
        rest=$(printf '%s' "$order" | ${pkgs.coreutils}/bin/tr ',' '\n' \
          | ${pkgs.gnugrep}/bin/grep -vxE 'vrr-allow-games|vrr-deny-others|spectacle-no-vrr' \
          | ${pkgs.coreutils}/bin/paste -sd, - || true)
        run $kwrite --file kwinrulesrc --group General --key Order "vrr-allow-games''${rest:+,$rest},vrr-deny-others"
      '';
    })
  ];
}
