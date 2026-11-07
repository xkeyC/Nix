# CapturePlay：采集卡（AVerMedia Live Gamer Ultra 2.1）低延迟播放器，Vulkan + Wayland HDR。
# 打包和模块都在 xkeyC/CapturePlay 的 flake 里，这里只负责启用。
#   * nvidiaVfx：NVIDIA Video Effects 运行库（补帧 VFG、超分 VSR），和 chaos-hdr 共用同一个 wheel 下载；
#   * dlssNr：DLSS NR 的 Proton helper（captureplay-nr-host.exe）。模型 nvngx_dlssnr.dll 不在包里，
#     程序会用 dlss5vklayer 导入的那份（~/.local/share/dlssnr/binaries）；Proton 用 Steam 里的，经 steam-run 启动。
# 数据：~/.config/CapturePlay（settings.toml、capture-play.log），~/.local/share/CapturePlay/nr-prefix（NR 的 Wine 前缀和 helper 日志）。
# VRR：窗口类别 capture-play 已加进 desktop.nix 的 VRR 白名单，全屏时开 VRR。
{ inputs, ... }:

{
  imports = [ inputs.capture-play.nixosModules.default ];

  programs.capture-play = {
    enable = true;
    nvidiaVfx = true;
    dlssNr = true;
  };
}
