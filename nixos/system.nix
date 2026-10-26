# 系统基础：引导、主机名、网络、时区与语言、固件。
{ ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 4;

  networking.hostName = "xkeyc-nixos";
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Singapore";
  i18n.defaultLocale = "zh_CN.UTF-8";

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = true;
}
