# Home Manager 相关：用户级软件包与激活行为。
#
#   * Linux QQ（NT 版，Electron；非自由软件，allowUnfree 已在
#     nix-settings.nix 开启）
#   * FlClash（ClashMeta 代理客户端，打包见 packages/flclash.nix）
#   * Claude Code CLI（命令 claude；官方二进制打包）
#   * Codex CLI（命令 codex；Rust 实现）
#
# 都放在用户 profile 里（~/.nix-profile/bin），不进系统包集合。
{ config, lib, pkgs, inputs, ... }:

let
  flclash = pkgs.callPackage ./packages/flclash.nix { };
in
{
  # 用户环境声明在 home/xkeyc.nix。
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    users.xkeyc = import ../home/xkeyc.nix;
  };

  # 遇到已有的非符号链接文件（例如残留的 10-hm-fonts.conf）时，
  # 自动改名为 *.hm-backup 而不是让整个 Home Manager 激活失败。
  home-manager.backupFileExtension = "hm-backup";

  home-manager.sharedModules = [
    {
      home.packages = [
        pkgs.qq
        flclash
        pkgs.claude-code
        pkgs.codex
      ];
    }
  ];
}
