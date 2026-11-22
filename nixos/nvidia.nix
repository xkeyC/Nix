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
    # 驱动版本取自 nixpkgs PR #583684（production: 595.112.07 -> 620.73.04，2026-11-21 已合并到 master，
    # 还未进 nixos-unstable），先在本地用。
    # nixos-unstable 包含该 PR 后改回 nvidiaPackages.latest（production 与 new_feature 中版本较高的那个）。
    package = (config.boot.kernelPackages.nvidiaPackages.mkDriver {
      version = "620.73.04";
      sha256_64bit = "sha256-tfLi1dqENbMlOTBAFbib9+si/grsjNaQW3puip+bjxs=";
      sha256_aarch64 = "sha256-45QZFS3Hs9hN4tKRrfmripADVpZQqksB7pAEZaS+XkA=";
      openSha256 = "sha256-+GPU2bXC/QWZTt0eH3dTvI0bMAta1GCdU2WFI4E4LWE=";
      settingsSha256 = "sha256-Wrv0F7Eo9X/0Xv5DclI9aIe3FcRtbu9okQJuWBjL8es=";
      persistencedSha256 = "sha256-QOndl1q7veD5aB6AfEe0/K2QHR8+ftLsei/aQrUCN3Q=";
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
