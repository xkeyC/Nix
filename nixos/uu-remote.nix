# UU 远程 Linux 被控端（非官方，uu-remote-linux）：让官方 Mac / Windows / 手机客户端远程控制本机。
#
# 打包、uuremote-native.service（用户级服务，随图形会话启动）和 /dev/uinput 的 uaccess 规则都来自上游自带的
# Nix 打包与 NixOS 模块（flake 输入 uu-remote-linux，packaging/nix/）。这里只叠加：
#   * 两个本地补丁（见下面 package 处的说明）；
#   * 上游包装的 PATH 只有 ffmpeg、wl-clipboard，补上 xrandr、lspci（login 时上报显卡）、fc-match（控制端找字体）；
#   * wrapGApps：登录二维码窗口、隐私屏遮罩用 GTK，Plasma 会话的 XDG_DATA_DIRS 里没有 GSettings schema。
#   * 服务的环境变量和 PATH（pactl、wpctl、kscreen-doctor）。
#   * 开机自启：服务依附 Plasma 图形会话，开机停在登录界面时不会运行。因此自动登录
#     xkeyc，并让 Plasma 一启动就锁屏（kscreenlockerrc LockOnStart）；远程连接后用
#     官方客户端的「自动解锁被控端」（PAM 校验登录密码）进入桌面。
#     自动登录没有输入密码，KDE 钱包（pam_kwallet）不会自动解锁，首次访问时会弹出密码框。
#   * /dev/uinput（uinput.enable）：Wayland 下改用内核级的虚拟键盘鼠标，绕过 portal 授权，也解决键盘布局丢失符号的问题。
#     uaccess 只把权限授予当前在本机前登录的用户。
#
# 首次使用：桌面里运行 `uuremote-server login`，用 UU 远程 App 扫码（服务启动后也会自动弹出登录窗口）。
# 登录信息在 ~/.config/uuremote/config.json。日志：journalctl --user -u uuremote-native -f
# 排查：uuremote-server doctor
{ inputs, lib, pkgs, ... }:

let
  uu-remote-linux = pkgs.uu-remote-linux.overrideAttrs (old: {
    # KDE 的远程控制 portal 不弹出屏幕选择框，多屏时直接把整个工作区拼成一路画面。
    # 补丁新增 UU_PORTAL_MONITOR=<序号>：按显示器分别请求画面流，只采集其中一块（绝对坐标的鼠标事件上游已改为发送到该 portal 流）。
    # 只对真实显示器生效；隐私屏用的虚拟输出（source type 4）仍是单路画面。
    # UU_PORTAL_MONITOR_CMD=<命令>：命令输出 x,y 时选坐标相同的流，失败时才用序号。
    # 控制端找界面字体时上游已要求含「控」字（charset=63a7），但同一个 Noto CJK ttc 里各语言字形并列，
    # 本机会先挑到 KR。补丁在查询前加上 Noto Sans CJK SC。
    patches = (old.patches or [ ]) ++ [
      ./packages/uu-remote-linux-portal-monitor.patch
      ./packages/uu-remote-linux-viewer-cjk-font.patch
    ];
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.wrapGAppsHook3 ];
    dontWrapGApps = true;
    # 上游已把 uuremote-server 本体放在 libexec 并包装好，这里在外面再套一层，/proc/<pid>/exe 不变。
    postFixup = old.postFixup + ''
      for bin in $out/bin/uuremote-server $out/bin/uuremote-viewer; do
        wrapProgram $bin "''${gappsWrapperArgs[@]}" \
          --suffix PATH : ${lib.makeBinPath [ pkgs.xrandr pkgs.pciutils pkgs.fontconfig.bin ]}
      done
    '';
  });

  # 要共享的显示器型号，取自 EDID（strings /sys/class/drm/card*-*/edid）。
  monitorModel = "PG32UCDM3";
  # 输出这个型号当前的逻辑坐标（x,y）：先按 EDID 找接口，再问 KDE 坐标。portal 的流只带坐标，没有型号。
  monitorPosition = pkgs.writeShellApplication {
    name = "uu-portal-monitor-position";
    runtimeInputs = [ pkgs.gnugrep pkgs.jq pkgs.kdePackages.libkscreen ];
    text = ''
      for edid in /sys/class/drm/card*-*/edid; do
        dir=''${edid%/edid}
        [ "$(cat "$dir/status")" = connected ] || continue
        grep -qaF ${pkgs.lib.escapeShellArg monitorModel} "$edid" || continue
        connector=''${dir##*/}
        connector=''${connector#card*-}
        position=$(kscreen-doctor -j | jq -er --arg name "$connector" \
          '.outputs[] | select(.name == $name and .enabled) | "\(.pos.x),\(.pos.y)"')
        echo "$position"
        exit 0
      done
      echo "显示器 ${monitorModel} 未连接" >&2
      exit 1
    '';
  };
in
{
  imports = [ inputs.uu-remote-linux.nixosModules.default ];

  services.uu-remote-linux = {
    enable = true;
    package = uu-remote-linux;
    uinput.enable = true;
  };

  # 单元本身（ExecStart、Restart、partOf/after graphical-session.target）来自上游包，这里的设置成为 drop-in。
  systemd.user.services.uuremote-native = {
    # 用户服务的 PATH 只有 coreutils/systemd 等。pactl/parec：静音、虚拟音频、手柄麦克风；
    # wpctl：静音；kscreen-doctor：KDE 隐私屏（关物理屏、切到虚拟输出）。
    path = [ pkgs.pulseaudio pkgs.wireplumber pkgs.kdePackages.libkscreen ];
    environment = {
      RUST_LOG = "info";
      # 只共享一块显示器（补丁功能，见上面的 package）。序号对应日志里的
      # "Portal monitor stream N: position=… size=…"；删掉这两行恢复上游行为（整个工作区）。
      # 每次连接都按 monitorModel 重新定位，序号只在定位失败时使用（流的顺序随接线变化）。
      UU_PORTAL_MONITOR_CMD = "${monitorPosition}/bin/uu-portal-monitor-position";
      UU_PORTAL_MONITOR = "1";
    };
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "xkeyc";
  };
  # 用激活脚本写入，KDE 设置界面里仍可修改（「锁屏 → 登录后锁定」）。
  home-manager.users.xkeyc = { lib, pkgs, ... }: {
    home.activation.lockScreenOnStart = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kscreenlockerrc \
        --group Daemon --key LockOnStart --type bool true
    '';
  };
}
