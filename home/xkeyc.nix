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

  # dsh-nix 的打包对应旧版 harness，这里按 flake 里锁定的新版覆盖：
  # - 版本号、提交号与 pnpm 依赖哈希（实测值）；
  # - 上游已删除 packages/examples/acp-demo，删掉 dsh-nix 为它生成的失效 wrapper；
  # - 修正 nixpkgs 的 node 下启动失败的问题（见 postInstall）。
  programs.dsh.package =
    (pkgs.callPackage "${dshNix}/pkgs/dsh.nix" { src = dshSrc; }).overrideAttrs (old: {
      version = "0.2.1-rc.3";
      # src 已通过 callPackage 换成新版，只是 overrideAttrs 看不到。
      __intentionallyOverridingVersion = true;
      # 构建脚本默认用 `git rev-parse HEAD` 取提交号，沙箱里没有 git 仓库。
      env = (old.env or { }) // { DSH_CLIENT_COMMIT_HASH = inputs.deepseek-harness.rev; };
      pnpmDeps = old.pnpmDeps.overrideAttrs {
        outputHash = "sha256-I9pz1GK1uWwp28RBLfGK4SYqIa9bwf0/hW88kWEuJEQ=";
      };
      # node-addon-require-builtin 靠匹配 node 二进制里的 getter 指令取内部模块，
      # nixpkgs 编译的 node 对不上（Unsupported/no-getter），启动即崩。wrapper 本来就带
      # --expose-internals，这时直接 require，与上游 vendor/loader 的做法一致。
      postInstall = (old.postInstall or "") + ''
        rm "$out/bin/dsh-acp-demo"
        substituteInPlace "$out"/node_modules/.pnpm/node-addon-require-builtin@*/node_modules/node-addon-require-builtin/lib/index.js \
          --replace-fail "return api.requireBuiltin(moduleId);" \
            "return process.execArgv.includes('--expose-internals') ? require(moduleId) : api.requireBuiltin(moduleId);"
      '';
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

  # Baloo 默认只索引 ~，这里再显式排除两块 NTFS 数据盘：大批文件的元数据扫描没必要，
  # 也少一个常驻读写 NTFS 的后台进程。
  home.activation.configureBaloo = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file baloofilerc \
      --group General --key "exclude folders" --type path "/mnt/data/,/mnt/application/"
  '';

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
