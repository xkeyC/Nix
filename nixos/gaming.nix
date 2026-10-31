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
  # 固定 DWProton 11.0-16，避免随 nixpkgs 更新而自动升级。
  nixpkgs.overlays = [
    (final: prev:
      let
        version = "dwproton-11.0-16";
        source = final.fetchzip {
          url = "https://dawn.wine/dawn-winery/dwproton/releases/download/${version}/${version}-x86_64.tar.xz";
          hash = "sha256-fNAT/PRoWE5WcjGmoZYjPXx+wF0rlKuUXWQk0+P7s7U=";
        };
      in {
        dwproton-bin = prev.dwproton-bin.overrideAttrs (old: {
          inherit version;
          src = source;
          toolName = "${version}-x86_64";
          # Nix store 里文件的 mtime 都相同，wineboot 不会在前缀升级时重跑 wine.inf，
          # 旧前缀因此缺少 SamSs 服务和 lsass.exe，ACE 无法加载驱动。
          # 这里在前缀版本变化时删除 .update-timestamp。下面 Python 的缩进已算上 Nix 字符串去掉的 12 格。
          # 等 https://github.com/NixOS/nixpkgs/pull/581490 合并并更新 nixpkgs 后删除这两项。
          postInstall = (old.postInstall or "") + ''
            rm $steamcompattool/proton
            cp $src/proton $steamcompattool
          '';
          preFixup = old.preFixup + ''
            substituteInPlace "$steamcompattool/proton" \
              --replace-fail "            self.upgrade_pfx(old_ver)" \
                             "            self.upgrade_pfx(old_ver)
                        if old_ver != CURRENT_PREFIX_VERSION and file_exists(self.prefix_dir + '.update-timestamp', follow_symlinks=False):
                            os.remove(self.prefix_dir + '.update-timestamp')"
          '';
        });
      })
  ];

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
