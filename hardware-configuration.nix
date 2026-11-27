# 硬件与磁盘。磁盘按卷标挂载（NIXBOOT / nixos），配置里不写 UUID。
# 分区：nvme0n1p1 1G EFI（NIXBOOT），nvme0n1p2 其余全部 btrfs（nixos），五个子卷。
{ config, lib, modulesPath, ... }:

let
  root = "/dev/disk/by-label/nixos";
  btrfsOpts = [ "compress=zstd:1" "noatime" ];
  subvol = name: {
    device = root;
    fsType = "btrfs";
    options = [ "subvol=${name}" ] ++ btrfsOpts;
  };
in
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "thunderbolt" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" ];

  fileSystems = {
    "/" = subvol "@";
    "/home" = subvol "@home";
    "/nix" = subvol "@nix";
    "/var/log" = subvol "@log" // { neededForBoot = true; };
    "/.snapshots" = subvol "@snapshots";
    "/boot" = {
      device = "/dev/disk/by-label/NIXBOOT";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = true;
}
