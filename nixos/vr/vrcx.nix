# VRCX：VRChat 好友/实例管理工具（打包见 packages/vrcx.nix，上游 AppImage）。
{ pkgs, ... }:

{
  environment.systemPackages = [ (pkgs.callPackage ./packages/vrcx.nix { }) ];
}
