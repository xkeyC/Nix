# Nix 本身：非自由软件许可、国内镜像与 CUDA 二进制缓存。
{ ... }:

{
  nixpkgs.config.allowUnfree = true;
  nix.settings = {
    substituters = [
      "https://mirror.sjtu.edu.cn/nix-channels/store?priority=10"
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store?priority=20"
      "https://mirrors.ustc.edu.cn/nix-channels/store?priority=30"
      "https://cache.nixos-cuda.org?priority=35"
      "https://cache.nixos.org?priority=40"
    ];
    trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };
}
