{
  description = "xkeyc 的 NixOS 配置（KDE Plasma + Fcitx5/RIME 雾凇拼音 + FlClash + Home Manager）";

  inputs = {
    # 与当前 nixos-unstable channel 相同的 nixpkgs 提交
    # （nixos-version = 26.11.20261107.f4a03c0）。
    # 升级 nixpkgs：`nix flake update nixpkgs`，然后 `sudo nixos-rebuild switch`。
    nixpkgs.url = "github:NixOS/nixpkgs/f4a03c008967841f2a0b3cb7c436fc6fc31671f6";

    # 只用来取比 nixos-unstable 新的个别包：configuration.nix 读这里的 kernels-org.json，同一分支上比 nixos-unstable 新就用它的
    # 版本号和 hash（内核本来就因 ntfs 补丁在本地编译，channel 落后时不用干等）；home-manager.nix 的 codex 同理。
    # 其余包仍来自上面的 nixpkgs，有 cache。
    # 升级：把提交号换成 master 最新提交（git ls-remote https://github.com/NixOS/nixpkgs refs/heads/master），
    # 再执行 `nix flake update nixpkgs-master`。
    nixpkgs-master = {
      url = "github:NixOS/nixpkgs/4563b5d1c75e16d35f8beec24404078c28a518ea";
      flake = false;
    };

    # Star Citizen 的 Wine 环境和 RSI Launcher。
    nix-citizen.url = "github:LovingMelody/nix-citizen";

    linuxqq-wayland-fix = {
      url = "github:SHORiN-KiWATA/linuxqq-wayland-fix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 以下三个原先拷贝在 ./vendor/，现在改为引用同一提交的线上源码（与原来的 vendor 目录逐个文件相同）。
    # 都用 flake = false 按源码目录导入，行为与原来直接 import 相同。
    # 升级：修改 url 里的提交号（或者去掉提交号，再执行 `nix flake update <名字>`）。
    home-manager = {
      url = "github:nix-community/home-manager/095fef2f265c3c0da4fe315efba8f8a04495ab34";
      flake = false;
    };
    # DSH 的 Nix 打包（Home Manager 模块 + profile 构建）。
    dsh-nix = {
      url = "github:Samuka007/dsh-nix/090ed51b27e65af7c0aadf64dcd7b208030aa3a9";
      flake = false;
    };
    # DeepSeek Harness 源码，锁定在发布 tag dsh-v0.2.1-rc.5（比 dsh-nix 自身锁定的新，
    # 版本号与安装步骤的差异在 home/xkeyc.nix 里覆盖）。
    deepseek-harness = {
      url = "github:deepseek-ai/deepseek-harness/b830ec950faba0a46dda564be3e2d854afed94f1";
      flake = false;
    };

    # Chaos HDR 的 fork，打包和 NixOS 模块都在 fork 的 flake 里。
    # 升级：修改 url 里的提交号，再执行 `nix flake update chaos-hdr`。
    chaos-hdr = {
      url = "github:xkeyC/chaos-hdr/ec2803dfed650bc058536564c64a7b31fd31ce61";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # FlydigiLinux：飞智手柄力回馈扳机（官方 mod）与 DS 模式，打包和 NixOS 模块在它自己的 flake 里。
    # 升级：修改 url 里的提交号，再执行 `nix flake update flydigi-linux`。
    flydigi-linux = {
      url = "github:xkeyC/FlydigiLinux/4b11ab344007b14da04ce60c05afb08868dbad02";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # CapturePlay：采集卡低延迟播放器（补帧、超分、HDR、DLSS NR），打包和 NixOS 模块在它自己的 flake 里。
    # 升级：修改 url 里的提交号，再执行 `nix flake update capture-play`。
    capture-play = {
      url = "github:xkeyC/CapturePlay/24fd15689c620fa7dbeee93cb6e3ff56b320e079";
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
