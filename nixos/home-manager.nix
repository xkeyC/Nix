# Home Manager 相关：用户级软件包与激活行为。
#
#   * Linux QQ（NT 版，Electron；非自由软件，allowUnfree 已在
#     nix-settings.nix 开启）；/mnt/data 没挂载时不启动
#   * FlClash（ClashMeta 代理客户端，打包见 packages/flclash.nix）
#   * Claude Code CLI（命令 claude；官方二进制打包）
#   * Codex CLI（命令 codex；Rust 实现）
#
# 都放在用户 profile 里（~/.nix-profile/bin），不进系统包集合。
{ config, lib, pkgs, inputs, ... }:

let
  flclash = pkgs.callPackage ./packages/flclash.nix { };

  # QQ 的聊天记录在 /mnt/data 上（~/.config/QQ 里的 nt_qq_*、global 是指过去的符号链接）。
  # 盘没挂上时启动，QQ 会把目录建在根分区的空挂载点里，挂上后被盖住、记录“丢失”。
  # 所以命令和菜单项都换成先检查挂载的包装：登录时会话恢复拉起 QQ 可能比挂载早，先等 10 秒。
  qq = pkgs.symlinkJoin {
    name = "qq-${pkgs.qq.version}";
    paths = [ pkgs.qq ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm $out/bin/qq $out/share/applications/qq.desktop
      makeWrapper ${pkgs.qq}/bin/qq $out/bin/qq --run '
        for _ in $(seq 20); do ${pkgs.util-linux}/bin/mountpoint -q /mnt/data && break; sleep 0.5; done
        if ! ${pkgs.util-linux}/bin/mountpoint -q /mnt/data; then
          ${pkgs.libnotify}/bin/notify-send -a QQ -i dialog-warning "QQ 没有启动" "/mnt/data 没有挂载，聊天记录在那块盘上" || true
          exit 1
        fi'
      sed "s|${pkgs.qq}/bin/qq|$out/bin/qq|" ${pkgs.qq}/share/applications/qq.desktop > $out/share/applications/qq.desktop
    '';
  };
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
        qq
        flclash
        pkgs.claude-code
        pkgs.codex
      ];
    }
  ];
}
