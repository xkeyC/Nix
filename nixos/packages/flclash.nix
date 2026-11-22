# FlClash 二进制打包（Linux amd64，来自 archlinuxcn 的构建）
{ lib
, stdenv
, fetchurl
, zstd
, autoPatchelfHook
, makeWrapper
, wrapGAppsHook3
, gtk3
, glib
, pango
, cairo
, gdk-pixbuf
, atk
, harfbuzz
, libepoxy
, fontconfig
, libX11
, libayatana-appindicator
, libayatana-indicator
, libdbusmenu
, ayatana-ido
, libsecret
, keybinder3
}:

stdenv.mkDerivation rec {
  pname = "flclash";
  # 0.9.4 的 Flutter Wayland 渲染可能只显示左下角，暂时锁定旧版：
  # https://github.com/flutter/flutter/issues/196476
  version = "0.9.3-2";

  src = fetchurl {
    url = "https://archlinux.ccns.ncku.edu.tw/archlinuxcn/x86_64/flclash-${version}-x86_64.pkg.tar.zst";
    sha256 = "sha256-r3kEL7/EcbcOnDVjBPGKNKK5mtaZDYrpjYE7pJ45Nl0=";
  };

  nativeBuildInputs = [
    zstd
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    gtk3
    glib
    pango
    cairo
    gdk-pixbuf
    atk
    harfbuzz
    libepoxy
    fontconfig
    libX11
    libayatana-appindicator
    libayatana-indicator
    libdbusmenu
    ayatana-ido
    libsecret
    keybinder3
    stdenv.cc.cc.lib
  ];

  unpackPhase = ''
    runHook preUnpack
    tar --zstd -xf "$src"
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt
    cp -r usr/lib/flclash $out/opt/FlClash

    # 只有 Android 会用到；Linux 版不加载，且依赖 libjvm.so
    rm -f $out/opt/FlClash/lib/libdartjni.so

    install -d $out/share/applications $out/share/pixmaps
    cp -r usr/share/applications/. $out/share/applications/
    cp -r usr/share/pixmaps/. $out/share/pixmaps/

    substituteInPlace $out/share/applications/com.follow.clash.desktop \
      --replace-fail "Exec=flclash" "Exec=$out/bin/flclash"

    runHook postInstall
  '';

  postFixup = ''
    makeWrapper $out/opt/FlClash/FlClash $out/bin/flclash \
      --prefix LD_LIBRARY_PATH : "$out/opt/FlClash/lib" \
      "''${gappsWrapperArgs[@]}"
  '';

  meta = with lib; {
    description = "Multi-platform proxy client based on ClashMeta, simple and easy to use, open-source and ad-free";
    homepage = "https://github.com/chen08209/FlClash";
    license = licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ sourceTypes.binaryNativeCode ];
  };
}
