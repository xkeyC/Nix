# 中文输入法：Fcitx5 + RIME（雾凇拼音），面向 KDE Plasma 6 Wayland。
#
#   * 由 KWin 通过 kwinrc 的 [Wayland] InputMethod 启动 Fcitx5 的 Wayland
#     前端（等价于 “系统设置 -> 键盘 -> 虚拟键盘” 中选择
#     “Fcitx 5 Wayland Launcher (Experimental)”）。
#   * 不设置 GTK_IM_MODULE / QT_IM_MODULE，原生应用使用 text-input-v3 协议；
#     XWayland 应用通过 XMODIFIERS 使用 Fcitx5 的 XIM。
#   * 词库使用雾凇拼音 (rime-ice)，默认输出简体，并带 emoji。
{ config, lib, pkgs, ... }:

let
  # 用雾凇拼音的数据替换 fcitx5-rime 自带的 rime-data。
  # 该包会把上游 default.yaml 安装为 rime_ice_suggestion.yaml，
  # 需要用户侧 default.custom.yaml 用 __include 引入（见下）。
  fcitx5-rime-rime-ice = pkgs.fcitx5-rime.override {
    rimeDataPkgs = [ pkgs.rime-ice ];
  };

  # 启用雾凇拼音的上游默认配置（方案列表、快捷键、菜单、emoji 等）。
  rimeDefaultSchema = pkgs.writeText "fcitx5-rime-default.custom.yaml" ''
    patch:
      __include: rime_ice_suggestion:/
  '';
in
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      addons = [ fcitx5-rime-rime-ice ];
      waylandFrontend = true;

      # Fcitx5 默认把左 Shift 设成“临时切换到第一个输入法（keyboard-us）”，按键传不到 RIME，
      # 而且切换出去时 fcitx5-rime 会把高亮的候选词上屏。这里清空这个设置，把左 Shift 交给雾凇拼音自己处理：
      # ascii_composer 里 Shift_L 是 commit_code，已敲的字母直接作为英文上屏并切到英文。
      settings.globalOptions."Hotkey/AltTriggerKeys" = { };

      # 默认输入法设为 RIME；同时保留 keyboard-us 便于 Ctrl+Space 切换英文。
      settings.inputMethod = {
        "GroupOrder"."0" = "Default";
        "Groups/0" = {
          "Name" = "Default";
          "Default Layout" = "us";
          "DefaultIM" = "rime";
        };
        "Groups/0/Items/0" = {
          "Name" = "keyboard-us";
          "Layout" = "";
        };
        "Groups/0/Items/1" = {
          "Name" = "rime";
          "Layout" = "";
        };
      };
    };
  };

  # 让 KWin 在登录时自动启动 Fcitx5 的 Wayland 前端。
  # 与 KCM 写入 ~/.config/kwinrc 的内容相同，这里放进系统级 kwinrc，
  # 使第一次登录就能生效（KConfig 会把 /etc/xdg 配置作为默认层读取）。
  environment.etc."xdg/kwinrc".text = ''
    [Wayland]
    InputMethod[$e]=${config.i18n.inputMethod.package}/share/applications/fcitx5-wayland-launcher.desktop
  '';

  # RIME 用户配置：用 __include 启用雾凇拼音。
  # 通过 home-manager 写入 ~/.local/share/fcitx5/rime/default.custom.yaml。
  home-manager.sharedModules = [
    {
      home.file.".local/share/fcitx5/rime/default.custom.yaml".source = rimeDefaultSchema;
    }
  ];
}
