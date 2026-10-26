# VR 相关配置。各工具一个文件，自己打包的放 ./packages。
#
# 两套运行时，按需启动，都不设成系统默认：
#   * SteamVR + ALVR：ALVR 是 SteamVR 驱动，从 ALVR Dashboard 启动 SteamVR 串流到一体机。
#   * Monado + WiVRn：WiVRn 内置 Monado，头显连上时把自己写进
#     ~/.config/openxr/1/active_runtime.json 和 ~/.config/openvr/openvrpaths.vrpath
#     （OpenVR 游戏走 xrizer），原文件备份成 *.wivrn-backup，断开/退出时还原。
#   * 独立的 Monado 服务给有线头显用，socket 激活，平时不运行。
#   * VIVE Hub：VIVE Ultimate Tracker 的配对/建图工具，不是运行时（不支持头显）。
{
  imports = [
    ./steamvr.nix
    ./monado.nix
    ./wivrn.nix
    ./alvr.nix
    ./vivehub.nix
  ];
}
