# uu-remote-linux：非官方网易 UU 远程 Linux 被控端（uuremote-server）+ 实验性控制端（uuremote-viewer）。
#
# 上游 https://github.com/VallierDev/uu-remote-linux 只提供 deb / tarball / 源码编译（用 apt 安装依赖）。
# 这里改成纯 Nix 构建：
#   * 特性 wayland,portal：本机是 KDE Plasma Wayland，使用 xdg-desktop-portal（PipeWire + libei）。
#     不开 engine-plugins，Wayland/Portal 引擎直接静态链接进主程序，不再需要按 /usr/lib 路径查找 libuu-*.so。
#   * native-viewer,viewer-sdl：同时编译出控制端（视频用外部 ffmpeg 进程解码）。
#   * 运行时 dlopen 的裸 soname（libpam、libgbm、托盘用的 ayatana-appindicator）在 NixOS 上找不到，
#     补充到可执行文件的 RUNPATH；不使用 LD_LIBRARY_PATH，以免泄漏给远程终端里启动的 shell。
#   * ffmpeg（编码，需 libx264 / h264_nvenc）、wl-clipboard 等外部命令追加到 PATH 末尾。
{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, wayland-scanner
, wrapGAppsHook3
, libX11
, libXext
, libXtst
, libXfixes
, gtk3
, glib
, pipewire
, libei
, wayland
, libxkbcommon
, SDL2
, linux-pam
, libgbm
, libayatana-appindicator
, ffmpeg
, wl-clipboard
, xrandr
, pciutils
}:

rustPlatform.buildRustPackage {
  pname = "uu-remote-linux";
  version = "0.2.41-unstable-2026-10-30";

  src = fetchFromGitHub {
    owner = "VallierDev";
    repo = "uu-remote-linux";
    rev = "6bf05a6361e58dbeec5846f044d234bed04fcf02";
    hash = "sha256-PR1ZyVJJmuRtjBPbraWq88+K4F2ixH1ak4Fb5+NFDwk=";
  };

  # KDE 的远程控制 portal 不弹出屏幕选择框，多屏时直接把整个工作区拼成一路画面。
  # 补丁新增 UU_PORTAL_MONITOR=<序号>：按显示器分别请求画面流，只采集其中一块（绝对坐标的鼠标事件上游已改为发送到该 portal 流）。
  # UU_PORTAL_MONITOR_CMD=<命令>：命令输出 x,y 时选坐标相同的流，失败时才用序号。
  patches = [ ./uu-remote-linux-portal-monitor.patch ];

  # 上游 Cargo.lock 的副本（与 rev 一致；升级 rev 时一并替换）。
  cargoLock.lockFile = ./uu-remote-linux.Cargo.lock;

  buildFeatures = [ "wayland" "portal" "native-viewer" "viewer-sdl" ];

  nativeBuildInputs = [ pkg-config wayland-scanner wrapGAppsHook3 ];
  buildInputs = [
    libX11 libXext libXtst libXfixes
    gtk3 glib
    pipewire libei
    wayland libxkbcommon
    SDL2
  ];

  # 测试需要真实的 X11 / Wayland 会话。
  doCheck = false;

  postInstall = ''
    install -Dm644 contrib/desktop/uu-remote-linux.svg $out/share/icons/hicolor/scalable/apps/uu-remote-linux.svg
    install -Dm644 -t $out/share/applications contrib/desktop/uu-remote-linux.desktop contrib/desktop/uu-remote-linux-viewer.desktop
  '';

  dontWrapGApps = true;
  postFixup = ''
    for bin in $out/bin/uuremote-server $out/bin/uuremote-viewer; do
      patchelf --add-rpath ${lib.makeLibraryPath [ linux-pam libgbm libayatana-appindicator ]} $bin
      wrapProgram $bin "''${gappsWrapperArgs[@]}" \
        --suffix PATH : ${lib.makeBinPath [ ffmpeg wl-clipboard xrandr pciutils ]}
    done
  '';

  meta = {
    description = "Unofficial Linux host for NetEase UU Remote";
    homepage = "https://github.com/VallierDev/uu-remote-linux";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "uuremote-server";
  };
}
