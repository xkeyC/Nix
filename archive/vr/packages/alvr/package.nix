# ALVR master（21.0.0-dev）。基于 nixpkgs pkgs/by-name/al/alvr/package.nix（20.14.1）改写。
#
# 为什么不用 20.14.1：它在 SteamVR 2.16+ 上有一串问题（合成器进程名 vrcompositor.re 导致 303、
# Vulkan 层没实现 vkWaitForPresentKHR 导致一帧画面都不输出 → 黑屏），修复都只在 master。
# master 的变化：
#   * Linux 改用 SteamVR direct-mode 驱动接口（#3398），不再有 vulkan_layer / vrcompositor 包装器 /
#     drm-lease shim。新 Dashboard 启动时会还原旧版留下的 vrcompositor 符号链接。
#   * FFmpeg 升级到 8.1、单独需要 Vulkan 头文件，见 ffmpeg.nix 和 fix-finding-libs.patch。
#   * 头显客户端必须安装同版本的 nightly APK（v21.0.0-dev），20.14.1 客户端连不上。
# 升级：改 rev/hash，cargoHash 置空后构建一次获取新值，对照 alvr/xtask/patches 更新 ffmpeg.nix。
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  fetchurl,
  replaceVars,
  callPackage,
  pkg-config,
  autoAddDriverRunpath,
  alsa-lib,
  android-tools,
  brotli,
  bzip2,
  celt,
  gmp,
  jack2,
  lame,
  libx11,
  libxi,
  libxrandr,
  libxcursor,
  libdrm,
  libglvnd,
  libogg,
  libpng,
  libtheora,
  libunwind,
  libva,
  libvdpau,
  libxkbcommon,
  openapv,
  openssl,
  openvr,
  pipewire,
  rust-cbindgen,
  soxr,
  vulkan-headers,
  vulkan-loader,
  wayland,
  x264,
  xvidcore,
}:

let
  rev = "adaa16bab3ef1a0c7aba4bebb5504c499c5a4425";

  src = fetchFromGitHub {
    owner = "alvr-org";
    repo = "ALVR";
    inherit rev;
    fetchSubmodules = true; # openvr
    hash = "sha256-lvjIQWxgfLSDAVAIftdiy4WpjhLxH5ktbkLP341Xsrg=";
  };

  ffmpeg-alvr = callPackage ./ffmpeg.nix { alvrSrc = src; };

  # PR #3425 新增的已编译着色器（源码 layer.comp 在补丁里），取自 PR head 提交。
  layerShaderSpv = fetchurl {
    url = "https://raw.githubusercontent.com/alvr-org/ALVR/66b773c85441e3a020b3aa6e6de363a5c84e1dd5/alvr/server_openvr/cpp/platform/linux/shader/layer.comp.spv";
    hash = "sha256-5gtGx7aToTu6ohcQIKHRfjBqRMvQlwaWX0EQG0nFh3s=";
  };
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "alvr";
  version = "21.0.0-dev14-unstable-2026-10-21";

  inherit src;

  cargoHash = "sha256-Wj8FVh8X7biYf/Fnjz/9t7jRfG85j9W21Pae5RnXZVA=";

  patches = [
    (replaceVars ./fix-finding-libs.patch {
      ffmpeg = lib.getDev ffmpeg-alvr;
      x264 = lib.getDev x264;
      vulkanHeaders = vulkan-headers;
    })
    # 上游未合并的 PR #3425（NVIDIA + Quest 上测试）：direct mode 按 SteamVR 的 per-texture
    # timeline semaphore 获取帧、合成所有图层、只在必要时阻塞 PostPresent。没有它时 vrcompositor
    # 每帧都 “WaitForAcquire timed out”，画面抖动、延迟高。合并到 rev 无冲突；
    # 二进制的 layer.comp.spv 不在补丁里，见 postPatch。合入上游后删掉。
    ./pr3425-linux-direct-frame-sync.patch
    # 头显在 SteamVR 激活 HMD 期间就已连接时，direct mode 组件尚未创建，编码器一直空闲 → 黑屏，
    # 只有重连才出画面。组件创建时再请求一次编码器重建。
    ./fix-first-connection-encoder.patch
  ];

  postPatch = ''
    cp ${layerShaderSpv} alvr/server_openvr/cpp/platform/linux/shader/layer.comp.spv
  '';

  env = {
    NIX_CFLAGS_COMPILE = toString [
      "-lbrotlicommon"
      "-lbrotlidec"
      "-lcrypto"
      "-lpng"
      "-lssl"
    ];
    RUSTFLAGS = toString (
      map (a: "-C link-arg=${a}") [
        "-Wl,--push-state,--no-as-needed"
        "-lEGL"
        "-lwayland-client"
        "-lxkbcommon"
        # master 的 Dashboard 用 wgpu，按裸库名 dlopen libvulkan.so.1；不链接进来就只剩 GL 后端，
        # 而 GL 后端在 Wayland 上不可用，Dashboard 启动即退出。
        "-lvulkan"
        "-Wl,--pop-state"
      ]
    );
  };

  cargoBuildFlags = [
    "--exclude=alvr_xtask"
    "--workspace"
  ];

  nativeBuildInputs = [
    rust-cbindgen
    pkg-config
    rustPlatform.bindgenHook
    autoAddDriverRunpath
  ];

  buildInputs = [
    alsa-lib
    android-tools
    brotli
    bzip2
    celt
    ffmpeg-alvr
    gmp
    jack2
    lame
    libx11
    libxcursor
    libxi
    libxrandr
    libdrm
    libglvnd
    libogg
    libpng
    libtheora
    libunwind
    libva
    libvdpau
    libxkbcommon
    openapv
    openssl
    openvr
    pipewire
    soxr
    vulkan-headers
    vulkan-loader
    wayland
    x264
    xvidcore
  ];

  postBuild = ''
    # Build SteamVR driver ("streamer")
    cargo xtask build-streamer --release
  '';

  postInstall = ''
    install -Dm755 ${finalAttrs.src}/alvr/xtask/resources/alvr.desktop $out/share/applications/alvr.desktop
    install -Dm644 ${finalAttrs.src}/resources/ALVR-Icon.svg $out/share/icons/hicolor/scalable/apps/alvr.svg

    # Install SteamVR driver（master 没有 Vulkan 层了，构建目录里不再有 share/）
    mkdir -p $out/{libexec,lib/alvr}
    cp -r ./build/alvr_streamer_linux/lib64/. $out/lib
    cp -r ./build/alvr_streamer_linux/libexec/. $out/libexec
    ln -s $out/lib $out/lib64
  '';

  passthru = { inherit ffmpeg-alvr; };

  meta = {
    description = "Stream VR games from your PC to your headset via Wi-Fi";
    homepage = "https://github.com/alvr-org/ALVR/";
    license = lib.licenses.mit;
    mainProgram = "alvr_dashboard";
    platforms = lib.platforms.linux;
  };
})
