{ pkgs, lib, inputs, ... }:
let
  dshNix = inputs.dsh-nix;
  # 沿用原 vendor 目录名：store 路径只取决于内容和名字，名字不变则已构建的 dsh
  # 可以直接复用（换成输入默认的 "source" 名会触发重建并重新下载全部 npm 依赖）。
  dshSrc = builtins.path { path = inputs.deepseek-harness; name = "deepseek-harness"; };
  pluginsLib = import (dshNix + "/lib/plugins.nix") { inherit lib; };
  profilesLib = import (dshNix + "/lib/profiles.nix") { inherit lib; };
in
{
  imports = [
    (import (dshNix + "/modules/home-manager/dsh.nix") {
      inherit pluginsLib profilesLib;
      inBoxNames = [
        "@deepseek-ai/dsh-base"
        "@deepseek-ai/dsh-web-app"
        "@deepseek-ai/dsh-headless"
      ];
      inherit dshSrc;
    })
  ];

  # dsh-nix 里 pnpm 依赖的哈希与当前 nixpkgs 的 fetchPnpmDeps 不符，这里改成实测值
  # （原先直接改在 vendor/dsh-nix/pkgs/dsh.nix 里）。
  programs.dsh.package =
    (pkgs.callPackage "${dshNix}/pkgs/dsh.nix" { src = dshSrc; }).overrideAttrs (old: {
      pnpmDeps = old.pnpmDeps.overrideAttrs {
        outputHash = "sha256-jfwS/aAMqNNS4MY/+OX0DhqnHzuYLDF/qd6E+vq1P4c=";
      };
    });

  home.username = "xkeyc";
  home.homeDirectory = "/home/xkeyc";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    brave
  ];

  programs.kitty.enable = true;

  # Plasma 6：所有电源模式均不自动睡眠，空闲 10 分钟关闭显示器。
  # 用激活脚本写入，使 powerdevilrc 仍可由 KDE 设置界面正常编辑。
  home.activation.configurePowerdevil = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    lib.concatMapStringsSep "\n" (profile: ''
      run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file powerdevilrc \
        --group ${profile} --group SuspendAndShutdown --key AutoSuspendAction 0
      run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file powerdevilrc \
        --group ${profile} --group Display --key TurnOffDisplayWhenIdle --type bool true
      run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file powerdevilrc \
        --group ${profile} --group Display --key TurnOffDisplayIdleTimeoutSec 600
    '') [ "AC" "Battery" "LowBattery" ]
  );

  # DeepSeek Harness web desktop shell; launch with: dsh --profile web
  programs.dsh = {
    enable = true;
    profiles.web.plugins = [
      "@deepseek-ai/dsh-base"
      "@deepseek-ai/dsh-web-app"
    ];
  };

  # User-level npm/pnpm registry; this does not alter Nix build sandboxes.
  home.file.".npmrc".text = ''
    registry=https://registry.npmmirror.com/
  '';
}
