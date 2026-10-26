# VIVE Hub：VIVE Ultimate Tracker 配对、建图（打包见 packages/vivehub.nix）。
# 规则给当前登录用户 dongle（0bb4:0350）和追踪器（0bb4:06a3）的 hidraw/usb 访问权限；
# switch 后拔插一次 dongle 生效。
{ pkgs, ... }:

let
  vivehub = pkgs.callPackage ./packages/vivehub.nix { };
in
{
  environment.systemPackages = [ vivehub ];
  services.udev.packages = [ vivehub.unwrapped ];
}
