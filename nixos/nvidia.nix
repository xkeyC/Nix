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
    # 带有重叠的 LOAD 段：后映射的只读段盖住了 .dynamic 所在页，ld.so 启动时写 DT_DEBUG
    # 直接段错误（ksystemstats 的 GPU 监控会不停触发 coredump）。这里在 fixup 之后补正段权限。
    package = config.boot.kernelPackages.nvidiaPackages.new_feature.overrideAttrs (old: {
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
