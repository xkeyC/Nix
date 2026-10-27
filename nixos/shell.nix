# 交互式 shell：登录 shell 换成 zsh + oh-my-zsh；Claude Code 执行命令仍然用 bash。
#
# Claude Code 默认按 $SHELL 选择执行命令的 shell，CLAUDE_CODE_SHELL 可以覆盖（路径里要含 bash 或 zsh）。
# 这里设成 bash：它按 ~/.bashrc 获取环境快照，命令也按 bash 语法执行，换登录 shell 后行为不变。
# ~/.bashrc / ~/.profile 仍由 Home Manager 生成（dev-toolchains.nix 的 programs.bash），两边的 PATH 等会话变量一致。
# 改登录 shell 后要注销重新登录，已经打开的终端不受影响。
{ pkgs, ... }:

{
  # 系统级：把 zsh 加进 /etc/shells，提供系统补全文件。compinit 交给 Home Manager 的 .zshrc，不重复执行。
  programs.zsh = {
    enable = true;
    enableGlobalCompInit = false;
  };
  users.users.xkeyc.shell = pkgs.zsh;

  home-manager.sharedModules = [
    {
      programs.zsh = {
        enable = true;
        autosuggestion.enable = true; # 按历史显示灰色提示，→ 键接受
        syntaxHighlighting.enable = true;
        history = {
          size = 100000;
          save = 100000;
          ignoreDups = true;
          share = true;
        };
        oh-my-zsh = {
          enable = true;
          theme = "robbyrussell";
          # sudo：连按两次 Esc 给当前命令加 sudo；extract：用 x <压缩包> 解压各种格式。
          plugins = [ "git" "sudo" "extract" "colored-man-pages" ];
        };
      };

      home.sessionVariables.CLAUDE_CODE_SHELL = "/run/current-system/sw/bin/bash";
    }
  ];
}
