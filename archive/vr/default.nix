# 【已存档，不参与构建】正在用的 VR 配置在 nixos/vr（SteamVR + Steam Link、WayVR、PaperTracker、VIVE Hub）。
# 恢复某个工具：把它的 .nix（和 packages/ 下的打包）`git mv` 到 nixos/vr，再加进 nixos/vr/default.nix 的 imports。
# ALVR 依赖 nixos/vr/steamvr.nix 里的 SteamVR 设置，恢复时不用再带 steamvr.nix。
#
# 存档的工具：
#   * ALVR：SteamVR 驱动，从 ALVR Dashboard 启动 SteamVR 串流到一体机。
#   * Monado + WiVRn：WiVRn 内置 Monado，头显连上时把自己写进
#     ~/.config/openxr/1/active_runtime.json 和 ~/.config/openvr/openvrpaths.vrpath
#     （OpenVR 游戏通过 xrizer 运行），原文件备份成 *.wivrn-backup，断开/退出时还原。
#   * 独立的 Monado 服务给有线头显用，socket 激活，平时不运行。
{
  imports = [
    ./monado.nix
    ./wivrn.nix
    ./alvr.nix
  ];
}
