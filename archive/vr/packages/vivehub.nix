# VIVE Hub for Linux（Beta）：VIVE Ultimate Tracker 的配对、建图和姿态 SDK。
#
# 上游 https://github.com/ViveRoboticsSoftware/vivehub-linux 只发布预编译包（闭源，VIVE EULA）。
#   * vivehub（ImGui/GLFW 界面）和 tracker_server（dongle 守护进程，由界面拉起）按
#     /proc/self/exe 的目录找同级文件，资源按当前目录找，所以必须 cd 进安装目录再启动；
#     随包的 libglfw / libhidapi-hidraw 通过 LD_LIBRARY_PATH 加载（同上游 run-vivehub.sh）。
#   * “Start setup”打开的建图向导是 Unity 播放器，运行时会 dlopen 一大串 X11/Wayland/
#     GL/Vulkan/音频库。逐个 patchelf 容易漏，这里把原样文件放进 store，用 FHS 环境运行。
#   * 界面的 imgui.ini 写在安装目录（只读），窗口布局不会保存，不影响功能。
#   * 日志、trackers.json 在 ~/.local/share/HTC/VIVEUltimateTracker/。
{ lib
, stdenvNoCC
, fetchurl
, buildFHSEnv
, makeDesktopItem
, writeShellScript
}:

let
  version = "1.0.3";

  unwrapped = stdenvNoCC.mkDerivation {
    pname = "vivehub-unwrapped";
    inherit version;

    src = fetchurl {
      url = "https://github.com/ViveRoboticsSoftware/vivehub-linux/releases/download/v${version}/VIVEHub-Linux-v${version}-x86_64.tar.gz";
      sha256 = "4bd87a7d7cb7d580a8dce0a5b2b5d4c32c1bd44822fec4a7bbf5971da277bc07";
    };

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/vivehub $out/lib/udev/rules.d
      cp -r . $out/share/vivehub/
      install -m644 udev/70-vive-tracker.rules $out/lib/udev/rules.d/
      runHook postInstall
    '';

    # 闭源二进制原样保留（Unity 播放器对改动 ELF 很敏感）。
    dontFixup = true;
  };

  desktopItem = makeDesktopItem {
    name = "vivehub";
    desktopName = "VIVE Hub";
    comment = "Pair and set up VIVE Ultimate Trackers";
    exec = "vivehub";
    icon = "${unwrapped}/share/vivehub/Assets/Icon_Main_OET_Connect.png";
    categories = [ "Utility" ];
  };
in
buildFHSEnv {
  pname = "vivehub";
  inherit version;

  targetPkgs = pkgs: with pkgs; [
    stdenv.cc.cc.lib
    zlib
    udev
    dbus
    libGL
    vulkan-loader
    # X11（GLFW 与 Unity）
    libx11
    libxext
    libxcursor
    libxinerama
    libxi
    libxrandr
    libxrender
    libxscrnsaver
    libxxf86vm
    libxkbcommon
    # Wayland 与随包 libdecor-cairo
    wayland
    cairo
    pango
    glib
    # Unity 音频、字体
    alsa-lib
    libpulseaudio
    fontconfig
    freetype
    dejavu_fonts
    xdg-utils
  ];

  runScript = writeShellScript "vivehub-launch" ''
    cd ${unwrapped}/share/vivehub || exit 1
    export LD_LIBRARY_PATH="${unwrapped}/share/vivehub/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    exec ./vivehub "$@"
  '';

  extraInstallCommands = ''
    install -Dm644 ${desktopItem}/share/applications/vivehub.desktop \
      $out/share/applications/vivehub.desktop
  '';

  passthru = { inherit unwrapped; };

  meta = {
    description = "VIVE Hub for Linux (Beta) - setup and monitoring for VIVE Ultimate Tracker";
    homepage = "https://github.com/ViveRoboticsSoftware/vivehub-linux";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "vivehub";
  };
}
