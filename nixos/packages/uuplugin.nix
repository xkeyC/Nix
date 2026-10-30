# uuplugin：网易 UU 主机加速的 Steam Deck 插件（闭源，静态链接，不需要 patchelf）。
#
# 对应 AUR 的 uuplugin-bin，直接用官方压缩包；uudeck 则是运行时用 curl -k 下载最新版，不可复现。
# 升级：查询最新版本和 MD5，修改下面的 version 和 hash。
#   curl -H 'Accept:text/plain' 'https://router.uu.163.com/api/plugin?type=steam-deck-plugin-x86_64'
{ lib, stdenvNoCC, fetchurl }:

stdenvNoCC.mkDerivation rec {
  pname = "uuplugin";
  version = "14.11.2";

  src = fetchurl {
    url = "https://uurouter.gdl.netease.com/uuplugin/steam-deck-plugin-x86_64/v${version}/uu.tar.gz";
    hash = "sha256-oZE8mmveqVrIbvVz+ztESm1AoRS/0wnuRYdnUIs/p2I=";
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  # uuplugin 按 /proc/self/exe 找同目录的 xuplugin-guardian，两个文件必须放在一起。
  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin uuplugin xuplugin-guardian
    install -Dm644 uu.conf $out/share/uuplugin/uu.conf
    runHook postInstall
  '';

  meta = {
    description = "NetEase UU accelerator plugin for Steam Deck";
    homepage = "https://uu.163.com/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "uuplugin";
  };
}
