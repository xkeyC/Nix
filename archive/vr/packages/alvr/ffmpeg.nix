# ALVR master 用的 FFmpeg：上游 xtask 下载 n8.1 并打上 alvr/xtask/patches 里的补丁
# （VAAPI 码率/全局头、NVENC 对 RGB 输入的色彩范围等）。这里用 nixpkgs 的 8.1.x headless
# 变体（默认带 NVENC、VAAPI、Vulkan、libdrm），只追加这些补丁。
{ ffmpeg_8-headless, alvrSrc }:

ffmpeg_8-headless.overrideAttrs (old: {
  pname = "ffmpeg-alvr";
  # 与上游 alvr/xtask/patches 保持一致，升级 ALVR 时对照目录内容更新。
  patches = (old.patches or [ ]) ++ map (p: "${alvrSrc}/alvr/xtask/patches/${p}") [
    "0001-lavu-hwcontext_vulkan-Fix-importing-RGBx-frames-to-C.patch"
    "0002-vaapi_encode-Force-enable-global-header.patch"
    "0003-vaapi_encode_h265-Set-vui_parameters_present_flag.patch"
    "0004-vaapi_encode-Allow-to-dynamically-change-bitrate-and.patch"
    "0005-vaapi_encode-Add-filler_data-option.patch"
    "0006-Add-AV_VAAPI_DRIVER_QUIRK_HEVC_ENCODER_ALIGN_64_16-f.patch"
    "0007-nvenc-honour-colorspace-and-range-for-RGB-input.patch"
    "0008-nvenc-honour-colorspace-and-range-for-RGB-input-AV1-UNTESTED.patch"
  ];
  doCheck = false;
})
