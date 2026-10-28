# 系统基础：引导、主机名、网络、时区与语言、固件。
{ ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 4;

  networking.hostName = "xkeyc-nixos";
  networking.networkmanager.enable = true;

  # 板载 2.5G 网口（r8169）开 magic packet 唤醒。生成的是 udev 的 .link 文件，不依赖 networkd；
  # NM 连接的 wake-on-lan 保持 default，不会覆盖。BIOS 里也要关 ErP、开 PCIe 唤醒。
  networking.interfaces.enp6s0.wakeOnLan.enable = true;

  time.timeZone = "Asia/Singapore";
  i18n.defaultLocale = "zh_CN.UTF-8";

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = true;
}
