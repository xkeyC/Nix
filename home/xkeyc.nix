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
    # 命令行网易云音乐，启动命令 musicfox。取播放链接原本走网页端接口（weapi），
    # 那里请求 jymaster 最多只给 96k 的 Hi-Res；改走客户端接口（eapi），SVIP 才能拿到
    # 192k 的超清母带。补丁打在 vendor 的 netease-music 库上，vendor 在 configure 时才复制进来。
    (go-musicfox.overrideAttrs (old: {
      postConfigure = (old.postConfigure or "") + ''
        chmod -R u+w vendor/github.com/go-musicfox/netease-music
        patch -p1 -d vendor/github.com/go-musicfox/netease-music < ${./packages/go-musicfox-eapi-song-url.patch}
      '';
    }))
    mpv # go-musicfox 的播放引擎
  ];

  # go-musicfox：用 mpv 播放（Linux 默认是程序自带的 beep 引擎），音质选超清母带 jymaster
  # （需要 SVIP，拿不到时服务器会降级）。没写的项用程序内置默认值。
  # 界面里换主题时 musicfox 会回写这个文件，所以只在文件不存在时写一份，之后可以自由编辑。
  home.activation.configureMusicfox = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    musicfoxConfig="''${XDG_CONFIG_HOME:-$HOME/.config}/go-musicfox/config.toml"
    if [ ! -e "$musicfoxConfig" ]; then
      run mkdir -p "$(dirname "$musicfoxConfig")"
      run install -m 644 ${pkgs.writeText "musicfox-config.toml" ''
        [player]
        engine = "mpv"
        songLevel = "jymaster"
      ''} "$musicfoxConfig"
    fi
  '';

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

  # 窗口回到上次所在的显示器。主显示器走 HDMI 2.1，开机时比右边的竖屏（DP）晚几秒接上，
  # 登录时恢复/自启的窗口会全开在竖屏上。KWin QML 脚本：
  #   - 记录：两块屏都在线时，窗口换到哪块屏就记下“程序 → 显示器”（~/.local/state/kwin-window-screens.ini）
  #   - 还原：只在登录后 2 分钟内，把新开的窗口送回它上次的显示器；目标屏还没接上就等它出现
  # 2 分钟后不再干预，KWin 照常摆放。
  xdg.dataFile."kwin/scripts/window-screen-memory/metadata.json".text = builtins.toJSON {
    KPlugin = {
      Id = "window-screen-memory";
      Name = "窗口回到上次的显示器";
      Description = "登录后把窗口送回上次所在的显示器";
      Version = "1.0";
      License = "MIT";
      EnabledByDefault = true;
    };
    X-Plasma-API = "declarativescript";
    X-Plasma-MainScript = "ui/main.qml";
    KPackageStructure = "KWin/Script";
  };
  xdg.dataFile."kwin/scripts/window-screen-memory/contents/ui/main.qml".text = ''
    import QtQuick
    import QtCore
    import org.kde.kwin

    Item {
        id: root
        readonly property int restoreWindowMs: 2 * 60 * 1000
        readonly property double started: Date.now()
        property var pending: []

        Settings {
            id: store
            location: StandardPaths.writableLocation(StandardPaths.GenericStateLocation) + "/kwin-window-screens.ini"
            property string screens: "{}" // JSON：resourceClass → 显示器名
        }

        function load() {
            try { return JSON.parse(store.screens); } catch (e) { return {}; }
        }
        function relevant(w) {
            return w.normalWindow && w.moveableAcrossScreens && w.resourceClass;
        }
        // 两块屏都在线才记录：登录时只有竖屏的那几秒，窗口在哪都不算数
        function allScreensUp() {
            return Workspace.screens.length >= 2;
        }
        function remember(w) {
            if (!relevant(w) || !w.output || !allScreensUp()) return;
            const map = load();
            if (map[w.resourceClass] === w.output.name) return;
            map[w.resourceClass] = w.output.name;
            store.screens = JSON.stringify(map);
            store.sync();
        }
        // 送回上次的显示器；目标屏还没接上返回 false
        function restore(w) {
            const target = load()[w.resourceClass];
            if (!target) { remember(w); return true; } // 没记录过：记下现在的位置
            const out = Workspace.screens.find(o => o.name === target);
            if (!out) return false;
            if (w.output !== out) Workspace.sendClientToScreen(w, out);
            return true;
        }
        function track(w) {
            if (!relevant(w)) return;
            w.outputChanged.connect(() => remember(w));
            if (Date.now() - started < restoreWindowMs) {
                if (!restore(w)) pending.push(w);
            } else {
                remember(w);
            }
        }

        Connections {
            target: Workspace
            function onWindowAdded(w) { root.track(w); }
            function onWindowRemoved(w) { root.pending = root.pending.filter(x => x !== w); }
            function onScreensChanged() { root.pending = root.pending.filter(w => !root.restore(w)); }
        }
        Component.onCompleted: Workspace.stackingOrder.forEach(track)
    }
  '';
  home.activation.enableWindowScreenMemory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kwinrc \
      --group Plugins --key window-screen-memoryEnabled --type bool true
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
