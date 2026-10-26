# FlClash 二进制打包（Linux amd64，来自 GitHub Release 的 .deb）
{ lib
, stdenv
, fetchurl
, dpkg
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
  version = "0.9.2";

  src = fetchurl {
    url = "https://github.com/chen08209/FlClash/releases/download/v${version}/FlClash-${version}-linux-amd64.deb";
    sha256 = "sha256-xso3RG25K1cwnRxwn7piCfLGebbTPPx0j3O46xpZpug=";
  };

  nativeBuildInputs = [
    dpkg
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

  unpackCmd = "dpkg-deb -x $curSrc source";
  sourceRoot = "source";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt
    cp -r opt/FlClash $out/opt/FlClash

    # 只有 Android 会用到；Linux 版不加载，且依赖 libjvm.so
    rm -f $out/opt/FlClash/lib/libdartjni.so

    install -d $out/share/applications $out/share/icons
    cp -r usr/share/applications/. $out/share/applications/
    cp -r usr/share/icons/. $out/share/icons/

    substituteInPlace $out/share/applications/FlClash.desktop \
      --replace-fail "Exec=FlClash" "Exec=$out/bin/flclash"

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
