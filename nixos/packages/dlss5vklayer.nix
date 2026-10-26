# DLSS5VKLayer：把游戏呈现的帧交给 Wine/Proton 里运行的 Windows NGX helper，
# 用 DLSS 5 Neural Rendering（Feature 18）处理后再送回去。
#
# 上游 https://github.com/bmitch87/DLSS5VKLayer 。直接用 release 预编译包：
#   * Vulkan 层（64/32 位）只依赖 libc/libm，C++ 运行时静态链接，适合被 Steam 容器
#     里的游戏加载；Windows 端 dlssnr_helper.exe 和 DXVK 的 vulkan-1.dll 是 PE 文件。
#     这些放进单独的 runtime derivation，不做任何 fixup（不改 RUNPATH、不 strip）。
#   * 源码构建要 clang + MinGW 交叉编译 + i686 工具链，收益不大，这里不做。
#   * 只有 Qt GUI 需要 patchelf；dlssnr-helper 是 bash 脚本，用 DLSSNR_INSTALL_DIR
#     指向 runtime，并补齐它调用的命令。
#   * 共享内存：上游默认放 /tmp/dlssnr-$UID，但 nixpkgs 的 Steam（以及 steam-run）是
#     privateTmp，游戏、helper 各自看到不同的 /tmp。这里改成 DLSSNR_SHM 优先、默认
#     /dev/shm/dlssnr-<用户名>/shm.bin（/dev/shm 在宿主、steam-run、Steam 容器之间共享）。
#     层读取同一个 DLSSNR_SHM，由 NixOS 模块设成会话环境变量。helper.pid 也放在同一目录，
#     GUI 按 dirname(shm)/helper.pid 判断 helper 是否在运行（决定 Stop 按钮能不能点）。
# NVIDIA 的 nvngx_dlssnr.dll 不在包里，需要用户自己用 GUI / import-binaries 导入。
{ lib
, stdenv
, stdenvNoCC
, fetchurl
, makeWrapper
, kdePackages
, bash
, coreutils
, util-linux
, gnugrep
, gnused
, gawk
, gnutar
, gzip
, curl
, pciutils
, findutils
, procps
}:

let
  version = "0.3.1-2";

  src = fetchurl {
    url = "https://github.com/bmitch87/DLSS5VKLayer/releases/download/${version}/dlssnr-${version}-linux-x86_64.tar.gz";
    sha256 = "43fd001720a3e15704c1bb8ea03c768b406e058c8eb2859ab0ebc8b3cd48f955";
  };

  # 层、helper.exe、vulkan-1.dll、静态 CLI 工具和层清单；原样保留。
  runtime = stdenvNoCC.mkDerivation {
    pname = "dlss5vklayer-runtime";
    inherit version src;
    sourceRoot = "dlssnr-${version}-linux-x86_64/root/usr";
    installPhase = ''
      mkdir -p $out/lib/dlssnr $out/share/vulkan/implicit_layer.d
      cp -r lib64/dlssnr/. $out/lib/dlssnr/
      for m in share/vulkan/implicit_layer.d/VK_LAYER_NV_dlssnr.*.json; do
        sed -e "s#/usr/lib64/dlssnr/#$out/lib/dlssnr/#" "$m" \
          > $out/share/vulkan/implicit_layer.d/$(basename "$m")
      done
      install -Dm644 share/doc/dlssnr/dxvk-license.txt $out/share/doc/dlssnr/dxvk-license.txt
    '';
    dontFixup = true;
  };
in
stdenv.mkDerivation {
  pname = "dlss5vklayer";
  inherit version src;
  sourceRoot = "dlssnr-${version}-linux-x86_64/root/usr";

  nativeBuildInputs = [ makeWrapper kdePackages.wrapQtAppsHook ];
  buildInputs = [ kdePackages.qtbase ];

  installPhase = ''
    runHook preInstall

    shmDefault='export DLSSNR_SHM="''${DLSSNR_SHM:-/dev/shm/dlssnr-$(${coreutils}/bin/id -un)/shm.bin}"'

    install -Dm755 bin/dlssnr-gui $out/libexec/dlssnr/dlssnr-gui
    patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
      --set-rpath ${lib.makeLibraryPath [ kdePackages.qtbase ]} $out/libexec/dlssnr/dlssnr-gui
    # Qt 的二进制包装器不支持 --run，这里用 shell 包装器带上 Qt 插件路径。
    makeShellWrapper $out/libexec/dlssnr/dlssnr-gui $out/bin/dlssnr-gui \
      "''${qtWrapperArgs[@]}" --run "$shmDefault"

    install -Dm755 bin/dlssnr-helper $out/libexec/dlssnr/dlssnr-helper
    substituteInPlace $out/libexec/dlssnr/dlssnr-helper \
      --replace-fail 'RUNTIME_DIR="/tmp/dlssnr-''${DLSSNR_UID:-$UID}"' \
                     'RUNTIME_DIR="$(dirname "''${DLSSNR_SHM:-/dev/shm/dlssnr-''${DLSSNR_UID:-$UID}/shm.bin}")"' \
      --replace-fail 'SHM_FILE="$RUNTIME_DIR/shm.bin"' 'SHM_FILE="''${DLSSNR_SHM:-$RUNTIME_DIR/shm.bin}"' \
      --replace-fail 'mkdir -p "$(dirname "$log")" "$(dirname "$shm")"' \
                     'mkdir -p "$(dirname "$log")" "$(dirname "$shm")"; chmod 700 "$(dirname "$shm")"'
    makeShellWrapper $out/libexec/dlssnr/dlssnr-helper $out/bin/dlssnr-helper \
      --run "$shmDefault" \
      --set-default DLSSNR_INSTALL_DIR ${runtime}/lib/dlssnr \
      --set-default DLSSNR_HELPER_EXE ${runtime}/lib/dlssnr/helper/dlssnr_helper.exe \
      --prefix PATH : ${lib.makeBinPath [ bash coreutils util-linux gnugrep gnused gawk gnutar gzip curl pciutils findutils procps ]}

    ln -s ${runtime}/lib/dlssnr/bin/dlssnr-shmctl $out/bin/dlssnr-shmctl
    ln -s ${runtime}/lib/dlssnr/bin/runner_probe $out/bin/dlssnr-runner-probe

    install -Dm644 share/applications/dlssnr.desktop $out/share/applications/dlssnr.desktop

    runHook postInstall
  '';

  dontWrapQtApps = true;

  passthru = { inherit runtime; };

  meta = {
    description = "Vulkan layer forwarding game frames to a Wine-hosted DLSS 5 Neural Rendering helper";
    homepage = "https://github.com/bmitch87/DLSS5VKLayer";
    license = lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
