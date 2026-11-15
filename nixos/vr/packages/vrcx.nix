# VRCX：VRChat 好友/实例管理工具。
#
# nixpkgs 的 vrcx 从源码构建，版本落后于上游 release。这里直接用上游发布的 x64 AppImage。
# AppImage 里带了 Electron 和 .NET 10 运行时（resources/dotnet-runtime，启动时自动设置 DOTNET_ROOT），
# 用 appimageTools.wrapType2 放进 FHS 环境运行即可，不需要另装 dotnet。
#   * --no-install：不把 AppImage 改名搬到 ~/Applications（store 路径只读）。
#   * --no-desktop：不往 ~/.local/share/applications 写 VRCX.desktop，桌面文件由本包提供。
#   * --no-updater：关掉自更新，升级改这里的 version/hash。
#   * --ozone-platform-hint=auto：Wayland 会话下走原生 Wayland。
# 数据在 ~/.config/VRCX/ 和 ~/.cache/VRCX/。
{ lib
, appimageTools
, fetchurl
, icu
, openssl
, runtimeShell
}:

let
  pname = "vrcx";
  version = "2026.11.14";

  src = fetchurl {
    url = "https://github.com/vrcx-team/VRCX/releases/download/v${version}/VRCX_${version}_x64.AppImage";
    hash = "sha256-nNtVLj9D46xOy96gUeCHO5OXoP6O6o6DkqqeMIYs6gg=";
  };

  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  # .NET 运行时 dlopen libicu 和 libssl。
  extraPkgs = _: [ icu openssl ];

  extraInstallCommands = ''
    mv $out/bin/${pname} $out/bin/.${pname}-wrapped
    cat > $out/bin/${pname} <<EOF
    #!${runtimeShell}
    exec $out/bin/.${pname}-wrapped --no-install --no-desktop --no-updater --ozone-platform-hint=auto "\$@"
    EOF
    chmod +x $out/bin/${pname}

    install -Dm644 ${contents}/VRCX.desktop $out/share/applications/vrcx.desktop
    substituteInPlace $out/share/applications/vrcx.desktop \
      --replace-fail 'Exec=AppRun %U' 'Exec=${pname} %U' \
      --replace-fail 'Icon=VRCX' 'Icon=vrcx'
    install -Dm644 ${contents}/VRCX.png $out/share/icons/hicolor/512x512/apps/vrcx.png
  '';

  meta = {
    description = "Friendship management tool for VRChat";
    homepage = "https://github.com/vrcx-team/VRCX";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
