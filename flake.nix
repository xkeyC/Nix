{
  description = "ai-max-395：Ryzen AI MAX+ 395 无头服务器的 NixOS 配置";

  inputs = {
    # 与 main 分支（xkeyc-nixos）同一个 nixos-unstable 提交，便于共用本地 store 与镜像缓存。
    # 升级：修改提交号，再执行 `nix flake update nixpkgs`。
    nixpkgs.url = "github:NixOS/nixpkgs/2786a2a72088ecf32aea5b3ec52099e6a7cff78f";
  };

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.ai-max-395 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        ./configuration.nix
      ];
    };
  };
}
