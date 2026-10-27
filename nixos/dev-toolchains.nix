# 开发工具链：给 /mnt/application/Projects 下从 Windows 迁移来的项目使用。
#
#   * Rust：rustup（按各仓库 rust-toolchain.toml 自动安装对应版本，
#     如 Astrbot/codex 固定 1.95.0）
#   * Python：python3 + uv（AstrBot 等项目用 uv 按 .python-version 下载 Python 3.12）
#   * Node：nodejs + pnpm + yarn（dashboard / NapCatQQ / wrangler 等）
#   * Flutter / Dart（SCToolBox、FlClash 等）、Go（Clash.Meta、codex2api）
#   * C/C++：gcc / cmake / ninja / make / pkg-config / protobuf
#   * .NET SDK（StarCitizen/_analysis 下的 ilspycmd 工具）
#
# rustup / uv / pnpm 会下载通用 Linux 预编译二进制，NixOS 上需要 nix-ld
# 提供 /lib64/ld-linux-x86-64.so.2 才能直接运行。
{ config, lib, pkgs, ... }:

{
  programs.nix-ld = {
    enable = true;
    # 在默认库集合之外，补充常见预编译工具链和 wheel 依赖的库。
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      zstd
      openssl
      curl
      libxml2
      glib
      libGL
      libx11
      libxext
      libxrender
      libxi
      libxcursor
      libxrandr
      fontconfig
      freetype
      gtk3
      icu
    ];
  };

  home-manager.sharedModules = [
    {
      home.packages = with pkgs; [
        # Rust（rustup 自带 cargo / rustc，按需安装 toolchain）
        rustup

        # Python
        python3
        uv

        # Node
        nodejs
        pnpm
        yarn

        # Flutter / Dart、Go
        # flutter 的输出根目录带 .gitattributes，与 dsh 冲突；降低 flutter 的优先级，让 buildEnv 使用 dsh 的文件。
        (lib.lowPrio flutter)
        go

        # C/C++ 构建
        gcc
        gnumake
        cmake
        ninja
        pkg-config
        protobuf

        # .NET
        dotnet-sdk

        # 常用命令行工具
        just
        jq
        fd
        ripgrep
        _7zz
        unzip
        zip
        wget
        rsync
        file
        tree
      ];

      programs.git = {
        enable = true;
        lfs.enable = true;
        settings = {
          # 与 Windows 上的全局身份一致；各仓库自身未配置 user。邮箱在 private/default.nix。
          user.name = "xkeyC";
          init.defaultBranch = "main";
          # 项目在 NTFS 分区上，权限位不可靠。
          core.fileMode = false;
          # 仓库从 Windows 迁移而来：提交时把 CRLF 转回 LF，检出保持 LF。
          core.autocrlf = "input";
        };
      };

      # GitHub CLI。git 配置由 Home Manager 生成（只读），`gh auth setup-git` 写不进去，
      # 所以在这里声明：github.com 的 HTTPS 凭据交给 `gh auth git-credential`。
      # 登录（令牌存在 ~/.config/gh/hosts.yml，不归 Nix 管）：gh auth login -h github.com -p https -w
      programs.gh = {
        enable = true;
        gitCredentialHelper.enable = true;
        settings.git_protocol = "https";
      };

      # Rust 构建缓存与 rustup/cargo 数据放在默认 ~/.cargo、~/.rustup；
      # ~/.local/bin 存放 `uv tool install` 安装的命令。
      home.sessionPath = [ "$HOME/.cargo/bin" "$HOME/.local/bin" ];

      # 需要由 Home Manager 生成 ~/.profile / ~/.bashrc，它们才会加载 hm-session-vars.sh
      # （上面的 sessionPath 以及其他 home.sessionVariables 依赖它）。
      programs.bash.enable = true;
    }
  ];
}
