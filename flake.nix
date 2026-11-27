{
  description = "ai-max-395：Ryzen AI MAX+ 395 无头服务器的 NixOS 配置";

  inputs = {
    # 与 main 分支（xkeyc-nixos）同一个 nixos-unstable 提交，便于共用本地 store 与镜像缓存。
    # 升级：修改提交号，再执行 `nix flake update nixpkgs`。
    nixpkgs.url = "github:NixOS/nixpkgs/2786a2a72088ecf32aea5b3ec52099e6a7cff78f";

    # Gufo：Strix Halo 推理引擎，release v0.37.0 的提交。不 follow 本仓库的 nixpkgs：
    # 它自带 ROCm 10.1 的 nixpkgs，预编译包只对它自己的 lock 有效（gufo.cachix.org）。
    # 升级：修改提交号，再执行 `nix flake update gufo`。
    gufo.url = "github:gufo-org/gufo/684b716a567aee9e016cbe1e4fec22ae9344a7e8";
  };

  outputs = { nixpkgs, ... }@inputs: {
    nixosConfigurations.ai-max-395 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./hardware-configuration.nix
        ./configuration.nix
        ./llm.nix
        ./halogen.nix
        ./xprobe.nix
      ];
    };
  };
}
