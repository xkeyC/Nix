# NVIDIA 驱动（open 内核模块）、Docker + NVIDIA 容器工具链、CUDA。
{ config, pkgs, ... }:

{
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    open = true;
    modesetting.enable = true;
    nvidiaSettings = true;
    # nixpkgs 用 patchelf 处理后的 nvidia-smi / nvidia-cuda-mps-control / nvidia-powerd
    # 带有重叠的 LOAD 段：后映射的只读段覆盖了 .dynamic 所在的页，ld.so 启动时写入 DT_DEBUG
    # 就会段错误（ksystemstats 的 GPU 监控会不停触发 coredump）。这里在 fixup 之后修正段权限。
    #
    # 驱动版本取自 nixpkgs PR #583684（production: 595.112.07 -> 620.70.06），合并前先在本地用。
    # PR 合并、nixpkgs 升级后改回 nvidiaPackages.latest（production 与 new_feature 中版本较高的那个）。
    package = (config.boot.kernelPackages.nvidiaPackages.mkDriver {
      version = "620.70.06";
      sha256_64bit = "sha256-KRGOOr0IwHVZvMo9nHYjjQOUkK8DYqLlvPy+cgSv1LE=";
      sha256_aarch64 = "sha256-P6ZaknHg3eKk5YxJZcOIhaAqOkKszcsm/IF0EGB/PgM=";
      openSha256 = "sha256-dV8vzniUl3UJoG2Q3KdoUJigLRuQeTniUfB670gb1Mw=";
      settingsSha256 = "sha256-CFBRmXFJ9eAf5BRlHMBolahz1Pshr9giI7zcZC29oZ8=";
      persistencedSha256 = "sha256-FpGzhArrvR1nEt8lKDzNEnbvHvGP36gL1dINvpDAkpA=";
    }).overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
      postFixup = (old.postFixup or "") + ''
        python3 -I ${./packages/fix-overlapping-load-segments.py} $bin/bin/*
      '';
    });
  };

  virtualisation.docker.enable = true;
  hardware.nvidia-container-toolkit.enable = true;
  virtualisation.docker.daemon.settings.features.cdi = true;

  environment.systemPackages = with pkgs; [
    cudaPackages_13.cudatoolkit
  ];
}
