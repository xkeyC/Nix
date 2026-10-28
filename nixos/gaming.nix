{ config, pkgs, ... }:

let
  dwproton = pkgs.writeShellScriptBin "dwproton" ''
    if [ "$#" -eq 0 ] || [ "$1" = "--help" ]; then
      echo '用法: dwproton [run|runinprefix|waitforexitandrun] <程序.exe> [参数...]'
      echo '      dwproton <程序.exe> [参数...]'
      echo '默认兼容目录: ~/.local/share/dwproton/default；可通过 STEAM_COMPAT_DATA_PATH 覆盖。'
      exit 0
    fi

    export STEAM_COMPAT_CLIENT_INSTALL_PATH="''${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$HOME/.local/share/Steam}"
    export STEAM_COMPAT_DATA_PATH="''${STEAM_COMPAT_DATA_PATH:-''${XDG_DATA_HOME:-$HOME/.local/share}/dwproton/default}"
    mkdir -p "$STEAM_COMPAT_DATA_PATH"

    case "$1" in
      run|runinprefix|waitforexitandrun|getcompatpath|getnativepath|destroyprefix) ;;
      *) set -- run "$@" ;;
    esac
    exec ${config.programs.steam.package.run}/bin/steam-run \
      ${pkgs.dwproton-bin.steamcompattool}/proton "$@"
  '';
  dwprotonExplorer = pkgs.runCommand "dwproton-explorer" { } ''
    mkdir -p "$out/bin"
    ln -s ${pkgs.dwproton-bin.steamcompattool}/files/lib/wine/x86_64-windows/explorer.exe "$out/bin/dwproton-explorer.exe"
  '';
in
{
  environment.systemPackages = [ dwproton dwprotonExplorer ];
  # Steam 模块同时启用 32 位图形库，供 Steam 和 Windows 游戏使用。
  programs.steam = {
    enable = true;
    extraCompatPackages = [ pkgs.dwproton-bin ];
  };

  # ntsync 是内核里的 NT 同步原语驱动，行为比 fsync 更接近 Windows。内核把它编译成了模块，但默认
  # 不加载；加载后会出现 /dev/ntsync（权限由内核设为 0666），DW-Proton 的 wineserver 检测到后会自动使用
  # （日志里会出现 “ntsync: up and running.”，设置 PROTON_NO_NTSYNC=1 可以关闭）。
  boot.kernelModules = [ "ntsync" ];
}
