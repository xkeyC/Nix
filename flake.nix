{
  description = "xkeyc 的 NixOS 配置（KDE Plasma + Fcitx5/RIME 雾凇拼音 + FlClash + Home Manager）";

  inputs = {
    # 与当前 nixos channel 相同的 nixpkgs 提交
    # （nixos-version = 26.11pre1097682.02c087f3fe67）。
    # 升级 nixpkgs：`nix flake update nixpkgs`，然后 `sudo nixos-rebuild switch`。
    nixpkgs.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";

    linuxqq-wayland-fix = {
      url = "github:SHORiN-KiWATA/linuxqq-wayland-fix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 以下三个原先拷贝在 ./vendor/，现在改为引用同一提交的线上源码（与原来的 vendor 目录逐个文件相同）。
    # 都用 flake = false 按源码目录导入，行为与原来直接 import 相同。
    # 升级：修改 url 里的提交号（或者去掉提交号，再执行 `nix flake update <名字>`）。
    home-manager = {
      url = "github:nix-community/home-manager/c216bf5a1f173b0481bd5c8c489ebe5595ecc68c";
      flake = false;
    };
    # DSH 的 Nix 打包（Home Manager 模块 + profile 构建）。
    dsh-nix = {
      url = "github:Samuka007/dsh-nix/090ed51b27e65af7c0aadf64dcd7b208030aa3a9";
      flake = false;
    };
    # DeepSeek Harness 源码，锁定在发布 tag dsh-v0.2.1-rc.3（比 dsh-nix 自身锁定的新，
    # 版本号与安装步骤的差异在 home/xkeyc.nix 里覆盖）。
    deepseek-harness = {
      url = "github:deepseek-ai/deepseek-harness/1f81c047fc48fa190a683e469daa699857e9afe8";
      flake = false;
    };

    # Chaos HDR 的 fork，打包和 NixOS 模块都在 fork 的 flake 里。
    # 升级：修改 url 里的提交号，再执行 `nix flake update chaos-hdr`。
    chaos-hdr = {
      url = "github:xkeyC/chaos-hdr/ec2803dfed650bc058536564c64a7b31fd31ce61";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 隐私配置（密码哈希、邮箱等），目录本身被 .gitignore 忽略；模板见 private.example/。
    # 用 path: 输入是因为 git flake 看不到被忽略的文件。修改 private/ 后执行：
    #   nix flake update private
    private = {
      url = "path:/home/xkeyc/Nix/private";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, home-manager, private, ... }@inputs:
    {
      nixosConfigurations.xkeyc-nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix
          "${home-manager}/nixos"
          "${private}/default.nix"
        ];
      };
    };
}
