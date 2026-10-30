# Chaos HDR：给选中的 SDR 窗口（例如用 DW-Proton 运行的游戏）做 NVIDIA TrueHDR + 锐化。
# RTX HDR 启动或运行失败时自动换用着色器引擎（Alt+Z 面板里的 Engine 可以手动选择）。
# 打包和服务定义都在 fork 的 flake 里（xkeyC/chaos-hdr 的 nix/），这里只负责启用。
# 数据目录：~/.local/share/chaos-hdr（画面配置、已授权窗口、状态文件）。
#
# 游戏方面的注意事项（DW-Proton）：
#   * 保持默认的 X11/XWayland；PROTON_ENABLE_WAYLAND=1 会让 Wine 把画面放进
#     子 surface，特效会跳过该窗口。
#   * 不要同时开启 PROTON_ENABLE_HDR / DXVK_HDR，游戏已经输出 HDR 时特效直接跳过。
#   * 不要在 gamescope 里运行。
{ inputs, ... }:

{
  imports = [ inputs.chaos-hdr.nixosModules.default ];

  programs.chaos-hdr.enable = true;

  # KWin 用核显渲染时（desktop-gpu.nix）不加载。
  systemd.user.services.chaos-hdr-effect.unitConfig.ConditionPathExists = "!%h/.config/kwin-render-igpu";
}
