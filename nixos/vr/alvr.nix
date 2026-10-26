# ALVR：通过 SteamVR 把画面串流到一体机（头显里装 ALVR 客户端）。
# 先在 Steam 里安装 SteamVR，再打开 ALVR Dashboard，由它启动 SteamVR。
#
# 用的是 master 版（packages/alvr），20.14.1 与 SteamVR 2.16+ 不兼容，原因见打包说明。
# 头显客户端要装同版本的 nightly APK。
#
# SteamVR 启动选项设成
#   ~/.local/share/Steam/steamapps/common/SteamVR/bin/vrmonitor.sh %command%
# 否则 vrserver 跑在 pressure-vessel 容器里，私有的 $XDG_RUNTIME_DIR 与容器外的
# vrcompositor 不通（20.14.1 时实测；master 改用 direct mode 后待验证是否仍需要）。
{ pkgs, ... }:

{
  programs.alvr = {
    enable = true;
    package = pkgs.callPackage ./packages/alvr/package.nix { };
    # TCP/UDP 9943、9944。
    openFirewall = true;
  };
}
