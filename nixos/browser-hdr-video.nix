# 浏览器（Brave）里的 HDR 视频：YouTube 高光不被截掉，B 站能选 HDR。
#
# KWin 补丁（packages/kwin-pq-max-cll.patch）：
#   Chromium 在 HDR 显示器上把整个窗口声明为 PQ（参考白 = 显示器的 SDR 白，这里约 194 nits），
#   但 max_cll / max_fall 也填成参考白，播放 HDR 视频时也不更新。KWin 照这个值做色调映射，
#   视频里超过参考白的高光全被压掉，看起来就是「HDR 没点亮、亮部没细节」。
#   补丁让 KWin 忽略「PQ 内容最亮不超过参考白」这种描述，改用 mastering 亮度或 set_luminances 的上限
#   （Chromium 给 1000 nits）。真正的 HDR 内容（游戏、mpv）声明的 max_cll 远高于参考白，不受影响。
#   只替换合成器本身：kwin_wayland_wrapper 按 PATH 启动 /run/wrappers/bin/kwin_wayland，
#   这里把这个 cap_sys_nice 包装的来源换成补丁版，Plasma 的其他组件仍用原版 kwin，不必重新编译。
#   升级 nixpkgs 后补丁打不上时，按新版 src/wayland/colormanagement_v1.cpp 重新制作。
#
# Brave 硬件解码：Chromium 默认不在 NVIDIA 上用 VA-API，视频全靠 CPU 软解，而且完全不支持 HEVC，
#   B 站的 HDR 流是 HEVC，于是不提供 HDR 选项。打开 VaapiOnNvidiaGPUs 等开关后，经 nvidia-vaapi-driver
#   用 NVDEC 解码（HEVC Main10、VP9 Profile 2、AV1 都可以），libva 按显卡自动选驱动，不用设环境变量。
#   检查：brave://media-internals 里 kVideoDecoderName 应为 VaapiVideoDecoder。
#   B 站的 HDR 画质需要大会员。
{ lib, pkgs, ... }:

let
  kwin = pkgs.kdePackages.kwin.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./packages/kwin-pq-max-cll.patch ];
  });

  # make-brave.nix 自己也加了一个 --enable-features，Chromium 只认最后一个，所以要带上它原有的几项。
  brave = pkgs.brave.override {
    commandLineArgs = "--enable-features=" + lib.concatStringsSep "," [
      "AcceleratedVideoDecodeLinuxGL"
      "AcceleratedVideoEncoder"
      "WaylandWindowDecorations"
      "VaapiVideoDecoder"
      "VaapiOnNvidiaGPUs"
      "VaapiIgnoreDriverChecks"
      "PlatformHEVCDecoderSupport"
    ] + " --ignore-gpu-blocklist";
  };
in
{
  security.wrappers.kwin_wayland.source = lib.mkForce "${kwin}/bin/kwin_wayland";

  home-manager.sharedModules = [
    { home.packages = [ brave ]; }
  ];
}
