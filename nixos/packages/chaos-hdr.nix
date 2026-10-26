# Chaos HDR：NVIDIA TrueHDR（SDR→HDR）+ 锐化的 KWin 原生特效。
#
# 上游 https://github.com/chaosfox26/chaos-hdr 只提供 CachyOS/Arch 的安装脚本
# （pacman 装依赖、uv 拉 Python 包、写死 /usr/include/kwin，项目目录兼作数据目录）。
# 这里改成纯 Nix 构建：
#   * 针对系统同一个 kdePackages.kwin 编译，插件放进 lib/qt-6/plugins/kwin/effects/plugins，
#     KWin 通过 /run/current-system/sw 直接找到，不再需要上游的 QML 加载器、
#     版本校验和 Python 更新器；KWin 升级时 Nix 会自动重编。
#   * NGX 头文件与静态加载器来自 NVIDIA/DLSS 固定提交（哈希取自上游 sdk.py）。
#   * TrueHDR 运行时只取 nvidia-vfx wheel 里的 libnvidia-ngx-truehdr.so（仅依赖 glibc，
#     NGX 通过上游编进特效里的 <site>/nvvfx/libs 路径加载它；原样保留、不做 patchelf）。
#   * 可写数据（profile.json、窗口授权、状态文件）从项目目录改到
#     $XDG_DATA_HOME/chaos-hdr（默认 ~/.local/share/chaos-hdr）。
{ lib
, stdenv
, fetchFromGitHub
, fetchurl
, unzip
, cmake
, pkg-config
, glslang
, addDriverRunpath
, kdePackages
, vulkan-headers
, vulkan-loader
, libepoxy
, libdrm
, wayland
, fontconfig
, libxkbcommon
}:

let
  version = "0.4.3";

  # 与上游 sdk.py 中的 REVISION / FILES 保持一致。
  dlssRev = "374959484e79a640feaba44c93ac8cfb0a03f5b5";
  dlssFile = path: sha256: fetchurl {
    url = "https://raw.githubusercontent.com/NVIDIA/DLSS/${dlssRev}/${path}";
    inherit sha256;
  };
  ngxFiles = {
    "LICENSE.txt" = dlssFile "LICENSE.txt" "d4216e39ebef5f9b50a6712ebb37beeb5379862a67733a9999c651f21592aaf0";
    "nvsdk_ngx_vk.h" = dlssFile "include/nvsdk_ngx_vk.h" "2d364ce7132881eb669e9498fd570d74cba563b1fbebc82c235f8e1ad2dd8b6d";
    "nvsdk_ngx_defs.h" = dlssFile "include/nvsdk_ngx_defs.h" "ea23f33497cd274860d1c25a97644fce807dcb0037c594547203343103fad03e";
    "nvsdk_ngx_params.h" = dlssFile "include/nvsdk_ngx_params.h" "943bc8cc5cdae03b6303016fbad3183636f2335ae27a2d18776798c3b4efabbc";
    "nvsdk_ngx_defs_vk.h" = dlssFile "include/nvsdk_ngx_defs_vk.h" "0a24d0861ace7d6b9362a67b7f08bea1b33ea123c5ce730b19133de8a891d031";
    "nvsdk_ngx_helpers_vk.h" = dlssFile "include/nvsdk_ngx_helpers_vk.h" "c192bff72138f12f770db48e12c1d8f712dfc81ea0e8e055ebb27d8dd1b31623";
    "libnvsdk_ngx.a" = dlssFile "lib/Linux_x86_64/libnvsdk_ngx.a" "3321c4ca9adf71f345550d10bf2148ed38003151b03ec5f81c99d00949ab8202";
  };

  # 上游 bootstrap.sh 固定的 nvidia-vfx==0.2.0.0（pypi.nvidia.com）。
  # 单独一个不做 fixup 的 derivation：NGX 会校验特性库签名，文件必须保持原样。
  truehdrRuntime = stdenv.mkDerivation {
    pname = "nvidia-ngx-truehdr";
    version = "1.2.3";
    src = fetchurl {
      url = "https://pypi.nvidia.com/nvidia-vfx/nvidia_vfx-0.2.0.0-cp312-abi3-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl";
      sha256 = "0252866a7b798a6f92c8543443d88f716e8c5bbc6a7ddd77a2754728dada9fa8";
    };
    nativeBuildInputs = [ unzip ];
    unpackPhase = "unzip -q $src 'nvvfx/libs/libnvidia-ngx-truehdr.so.1.2.3' 'nvidia_vfx-0.2.0.0.dist-info/*'";
    installPhase = ''
      install -Dm644 nvvfx/libs/libnvidia-ngx-truehdr.so.1.2.3 $out/nvvfx/libs/libnvidia-ngx-truehdr.so.1.2.3
      cp -r nvidia_vfx-0.2.0.0.dist-info $out/
    '';
    dontFixup = true;
    meta.license = lib.licenses.unfree;
  };
in
stdenv.mkDerivation {
  pname = "chaos-hdr";
  inherit version;

  src = fetchFromGitHub {
    owner = "chaosfox26";
    repo = "chaos-hdr";
    rev = "v${version}";
    hash = "sha256-PMaC31MmnpKaE+P/uKCQXJDesUgs6Mv7bO0BYuEQo1A=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    glslang
    addDriverRunpath
    kdePackages.wrapQtAppsHook
  ];

  buildInputs = [
    kdePackages.qtbase
    kdePackages.qtdeclarative
    kdePackages.kwin
    kdePackages.kcoreaddons
    kdePackages.kconfig
    kdePackages.kwindowsystem
    kdePackages.kglobalaccel
    kdePackages.kguiaddons
    vulkan-headers
    vulkan-loader
    libepoxy
    libdrm
    wayland
    fontconfig
    libxkbcommon
  ];

  # 两个独立的 CMake 工程（KWin 特效 + Alt+Z 快捷键/面板），自己驱动。
  dontUseCmakeConfigure = true;

  postPatch = ''
    # --- 构建定义：去掉 .venv / 项目目录假设，改用 Nix 提供的路径 ---
    substituteInPlace native/desktop/CMakeLists.txt \
      --replace-fail 'file(GLOB sites "''${TRUEHDR_ROOT}/.venv/lib/python*/site-packages")' "" \
      --replace-fail 'list(GET sites 0 TRUEHDR_RUNTIME_SITE)' "" \
      --replace-fail '"''${TRUEHDR_ROOT}/output/compositor/reference/ngx"' "\"$NIX_BUILD_TOP/ngx\"" \
      --replace-fail '/usr/include/kwin' '${kdePackages.kwin.dev}/include/kwin' \
      --replace-fail 'TRUEHDR_DESKTOP_SHADER="''${CMAKE_CURRENT_BINARY_DIR}/desktop_input.spv"' \
                     "TRUEHDR_DESKTOP_SHADER=\"$out/share/chaos-hdr/desktop_input.spv\""

    # --- 运行时数据目录：$XDG_DATA_HOME/chaos-hdr ---
    substituteInPlace native/desktop/effect.cpp \
      --replace-fail 'root=QString::fromUtf8(TRUEHDR_ROOT),profile;' \
                     'root=QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)+"/chaos-hdr",profile;' \
      --replace-fail 'QFile targets(root+"/window-targets.json");' \
                     'QDir().mkpath(root);QFile targets(root+"/window-targets.json");' \
      --replace-fail '#include <QDir>' $'#include <QDir>\n#include <QStandardPaths>' \
      --replace-fail 'QString::fromUtf8(TRUEHDR_ROOT)+"/build/truehdr-panel"' \
                     "QStringLiteral(\"$out/bin/truehdr-panel\")"
    substituteInPlace native/vulkan_hdr.cpp \
      --replace-fail 'QString::fromUtf8(TRUEHDR_DEFAULT_PROFILE)' \
                     'QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)+"/chaos-hdr/profile.json"' \
      --replace-fail '#include <QDir>' $'#include <QDir>\n#include <QStandardPaths>'

    # --- 面板：从菜单启动时不再调用 Python 的 desktop.py，直接触发叠加层 ---
    substituteInPlace native/panel.cpp \
      --replace-fail 'return QProcess::startDetached(root+"/.venv/bin/python",{root+"/desktop.py","--controls"})?0:1;
#else' \
                     'QSaveFile toggleFile(root+"/overlay.toggle");if(!toggleFile.open(QIODevice::WriteOnly))return 1;toggleFile.write(QByteArray::number(QDateTime::currentMSecsSinceEpoch()));return toggleFile.commit()?0:1;
#else'
  '';

  configurePhase = ''
    runHook preConfigure

    mkdir -p $NIX_BUILD_TOP/ngx
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: file: "cp ${file} $NIX_BUILD_TOP/ngx/${name}") ngxFiles)}

    cmake -S native/desktop -B build-desktop -DCMAKE_BUILD_TYPE=Release \
      -DTRUEHDR_ROOT=$out/share/chaos-hdr \
      -DTRUEHDR_ASSET_ROOT=$out/share/chaos-hdr \
      -DTRUEHDR_RUNTIME_SITE=${truehdrRuntime} \
      -DTRUEHDR_EFFECT_ID=truehdr_desktop
    cmake -S . -B build-controls -DCMAKE_BUILD_TYPE=Release

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cmake --build build-desktop --target truehdr_desktop truehdr-desktop-gpu-test --parallel $NIX_BUILD_CORES
    cmake --build build-controls --target truehdr-panel --parallel $NIX_BUILD_CORES
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 build-desktop/kwin/effects/plugins/truehdr_desktop.so \
      $out/lib/qt-6/plugins/kwin/effects/plugins/truehdr_desktop.so
    install -Dm644 build-desktop/desktop_input.spv $out/share/chaos-hdr/desktop_input.spv
    install -Dm755 build-controls/truehdr-panel $out/bin/truehdr-panel
    # 上游的独立自检：在单独进程里跑一遍 OpenGL→Vulkan→TrueHDR，不碰 KWin。
    install -Dm755 build-desktop/truehdr-desktop-gpu-test $out/libexec/chaos-hdr/truehdr-desktop-gpu-test

    mkdir -p $out/share/chaos-hdr/vendor
    cp -r assets $out/share/chaos-hdr/assets
    cp -r vendor/fonts $out/share/chaos-hdr/vendor/fonts
    cp release.json profile.example.json $out/share/chaos-hdr/

    install -Dm644 LICENSE $out/share/licenses/chaos-hdr/LICENSE
    install -Dm644 $NIX_BUILD_TOP/ngx/LICENSE.txt $out/share/licenses/chaos-hdr/NVIDIA-DLSS-LICENSE.txt
    install -Dm644 THIRD_PARTY_NOTICES.rst $out/share/licenses/chaos-hdr/THIRD_PARTY_NOTICES.rst

    runHook postInstall
  '';

  # 静态 NGX 加载器在运行时 dlopen 驱动里的 libnvidia-ngx.so（走本库的 RUNPATH）。
  # TrueHDR 特性库则自己 dlopen("libnvidia-ml.so.1")，而它是从 memfd 加载、没有 RUNPATH，
  # 在 NixOS 上找不到驱动目录；失败后 NVIDIA 代码会解引用空列表，直接让 KWin 段错误。
  # 预先把 NVML 作为依赖加载进进程，之后按 soname 的 dlopen 会直接命中它。
  postFixup = ''
    for f in $out/lib/qt-6/plugins/kwin/effects/plugins/truehdr_desktop.so \
             $out/libexec/chaos-hdr/.truehdr-desktop-gpu-test-wrapped; do
      patchelf --add-needed libnvidia-ml.so.1 "$f"
      addDriverRunpath "$f"
    done
  '';

  passthru = { inherit truehdrRuntime; };

  meta = {
    description = "Experimental NVIDIA TrueHDR and sharpening KWin effect for SDR windows";
    homepage = "https://github.com/chaosfox26/chaos-hdr";
    # 原创代码 GPL-2.0-only；NGX SDK 与 TrueHDR 运行时为 NVIDIA 专有许可。
    license = with lib.licenses; [ gpl2Only unfree ];
    platforms = [ "x86_64-linux" ];
  };
}
