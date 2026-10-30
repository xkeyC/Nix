{ config, lib, pkgs, ... }:

let
  # 固定源码及上游固件输入；更换版本时必须重新检查生成器和固件摘要。
  src = pkgs.fetchFromGitHub {
    owner = "JustAResearcher";
    repo = "gpu-unlock-ada";
    rev = "d28c485418c3d9d034cd4bac19200bc33dd3453b";
    hash = "sha256-+asA7z8uR3dwJROyK8xl2Xe2VvWmVv/vZ8nx/SjB4fk=";
  };
  nvidiaSource = pkgs.fetchurl {
    url = "https://download.nvidia.com/XFree86/NVIDIA-kernel-module-source/NVIDIA-kernel-module-source-610.43.03.tar.xz";
    hash = "sha256-fhGJI8eiPtw2EU1jJzpG4+BOmvmGlaQiA+esLf6fwdw=";
  };
  nvidiaUtils = pkgs.fetchurl {
    url = "https://archive.cachyos.org/archive/cachyos-v3/nvidia-utils-610.43.03-1-x86_64_v3.pkg.tar.zst";
    hash = "sha256-4X58ku7/oXiw/h9A6xekcJX4/Dzkp3vxFc9b1aTfhuk=";
  };
  firmware = pkgs.runCommand "gpu-unlock-ada-firmware-610.43.03" {
    nativeBuildInputs = [ pkgs.python3 pkgs.zstd pkgs.gnutar pkgs.xz ];
  } ''
    mkdir source assets
    tar -xf ${nvidiaSource} -C source
    python3 ${src}/firmware/generate_v67.py ${nvidiaUtils} assets
    python3 ${src}/firmware/extract_boot_assets.py source/NVIDIA-kernel-module-source-610.43.03 assets
    python3 ${src}/firmware/extract_boot_assets.py source/NVIDIA-kernel-module-source-610.43.03 assets --chip ad102
    install -Dm644 assets/*.bin -t "$out/lib/firmware/gpu-unlock/610.43.03"
    install -Dm644 assets/NVIDIA-LICENSE "$out/share/licenses/gpu-unlock/NVIDIA-LICENSE"
    install -Dm644 ${src}/firmware/NOTICE.md "$out/share/licenses/gpu-unlock/NOTICE.md"
  '';
in
{
  options.xkeyc.gpuUnlock.enable = lib.mkEnableOption "RTX 4090 Tensor Core unlock" // { default = true; };

  config = lib.mkMerge [
    {
      # systemd-boot 可选此配置，禁用模块、固件和解锁参数。
      specialisation.no-gpu-unlock.configuration = {
        xkeyc.gpuUnlock.enable = lib.mkForce false;
        system.nixos.tags = [ "no-gpu-unlock" ];
      };
    }
    (lib.mkIf config.xkeyc.gpuUnlock.enable {
    system.nixos.tags = [ "gpu-unlock" ];

    boot.extraModulePackages = [
      (config.boot.kernelPackages.callPackage ({ stdenv, kernel, kernelModuleMakeFlags, ... }:
        stdenv.mkDerivation {
          pname = "gpu-unlock-ada";
          version = "1.1.1-d28c485";
          inherit src;
          sourceRoot = "source/kernel/gpu_unlock";
          nativeBuildInputs = kernel.moduleBuildDependencies;
          makeFlags = kernelModuleMakeFlags ++ [
            "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
            "INSTALL_MOD_PATH=${placeholder "out"}"
          ];
          installPhase = ''
            runHook preInstall
            make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M="$PWD" modules_install $makeFlags
            runHook postInstall
          '';
          meta.license = lib.licenses.gpl2Only;
        }) { })
    ];

    hardware.firmware = [ firmware ];
    boot.initrd.extraFirmwarePaths = map (name: "gpu-unlock/610.43.03/${name}") [
      "booter_load_ga102.bin" "gsp_ga10x.bin" "gsp_boot_ga102.bin"
      "gsp_boot_desc_ga102.bin" "v67-ga102-610.43.03.bin"
      "booter_load_ad102.bin" "gsp_boot_ad102.bin" "gsp_boot_desc_ad102.bin"
      "v67-ad102-610.43.03-four-plm.bin"
    ];
    boot.initrd.availableKernelModules = [ "gpu_unlock" ];
    boot.kernelParams = [ "gpu_unlock.targets=0000:01:00.0" ];

    # 在设备枚举和 modules-load 之前同步完成解锁，再让 NVIDIA 驱动接管。
    boot.initrd.systemd.services.gpu-unlock = {
      description = "Unlock RTX 4090 before NVIDIA driver initialization";
      wantedBy = [ "initrd.target" ];
      before = [ "systemd-udevd.service" "systemd-udev-trigger.service" "systemd-modules-load.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/bin/modprobe gpu_unlock";
      };
    };
    })
  ];
}
