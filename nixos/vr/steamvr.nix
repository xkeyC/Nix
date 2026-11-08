# SteamVR（在 Steam 里安装）+ Steam Link VR（一体机装 Steam Link，串流走 SteamVR 自带的 vrlink 驱动）。
#
# cap_sys_nice 弹窗（“SteamVR setup is incomplete”）在这里修不了，也不用修：
#   * nixpkgs 的 Steam 跑在 bubblewrap 里，bwrap 一定会设 NO_NEW_PRIVS，而且 vrcompositor 在
#     非初始用户命名空间里。文件 capability 和 setuid 都不会生效，就算生效，子命名空间里的
#     CAP_SYS_NICE 也过不了 GPU 驱动的 capable() 检查。除非给 bwrap 打补丁不设 NO_NEW_PRIVS，
#     或者改内核/驱动，去掉高优先级 GPU 队列的权限检查。
#   * 这个能力只用于 SteamVR 合成器的异步重投影。NVIDIA 上 SteamVR 默认就关了异步（vrcompositor.txt：
#     “Async: Automatically disabled as default based on the detected Vulkan environment”），
#     串流头显又是在头显端自己做重投影。所以这里少掉的东西基本没用上，弹窗点确定即可。
#   * 想去掉弹窗：在宿主上执行
#       sudo setcap cap_sys_nice+ep ~/.local/share/Steam/steamapps/common/SteamVR/bin/linux64/vrcompositor-launcher
#     vrsetup.sh 读回 capability 后就不再提示（启动器在 bwrap 里照样拿不到这个能力，无副作用）。
#     SteamVR 更新替换文件后要重新执行。
{ pkgs, ... }:

let
  # vrmonitor:// 处理程序。SteamVR 的网页界面（识别手柄、打开设置页、配对向导等）用 xdg-open 打开
  # vrmonitor://… 链接，按设计由新启动的 vrmonitor.sh 转发给正在运行的 vrmonitor。在 NixOS 上
  # xdg-open 经 KDE 在 Steam 的 FHS 沙箱外启动处理程序：那里没有 Steam Runtime，也看不到沙箱私有
  # /tmp 里 vrmonitor 的本地 socket。这里先进入正在运行的 Steam 的用户和挂载命名空间（用户命名空间
  # 归我们所有，不需要 root），再带上 Steam 进程的环境变量运行 vrmonitor.sh。Steam 用「Steam（UU 加速）」
  # 启动时网络命名空间进不去，但路径 socket 不受影响。
  vrmonitorUrlHandler = pkgs.writeShellApplication {
    name = "vrmonitor-url-handler";
    runtimeInputs = with pkgs; [ coreutils jq libnotify procps util-linux ];
    text = ''
      fail() {
        echo "vrmonitor-url-handler: $1" >&2
        notify-send -a SteamVR -i steamvr "SteamVR" "$1" || true
        exit 1
      }

      pid=""
      self_userns=$(readlink /proc/self/ns/user)
      for p in $(pgrep -x -u "$(id -u)" steam || true); do
        if [ "$(readlink "/proc/$p/ns/user")" != "$self_userns" ]; then
          pid=$p
          break
        fi
      done
      [ -n "$pid" ] || fail "Steam 没在运行，无法打开 ''${1:-vrmonitor://}"

      runtime=$(jq -r '.runtime[0]' "$HOME/.config/openvr/openvrpaths.vrpath" 2>/dev/null || true)
      [ -x "$runtime/bin/vrmonitor.sh" ] || fail "找不到 SteamVR（$runtime/bin/vrmonitor.sh）"

      mapfile -d "" envs < "/proc/$pid/environ"
      exec nsenter -t "$pid" -U -m --preserve-credentials -- \
        ${pkgs.coreutils}/bin/env -i "''${envs[@]}" "$runtime/bin/vrmonitor.sh" "$@"
    '';
  };

  # SteamVR 的进程间通信用抽象 socket，按网络命名空间隔离。Steam 用「Steam（UU 加速）」启动时，
  # vrserver 在网络命名空间 uu 里，宿主上启动的 OpenVR 程序（WayVR、PaperTracker 等）连不上，
  # 报 VRInitError_Init_NoServerForBackgroundApp（挂载命名空间无关，实测只进网络命名空间就够）。
  # 用法：steamvr-netns 程序 [参数...]。SteamVR（没开时看 Steam）在 uu 里就经 uu-netns 进去，否则直接运行。
  # 要在 Steam 之后启动，否则留在宿主网络里。uu-netns 带 capability，经过它会被 glibc 清掉 LD_* 等环境变量，
  # 需要的话在它之后再设置。
  steamvrNetns = pkgs.writeShellApplication {
    name = "steamvr-netns";
    runtimeInputs = with pkgs; [ coreutils procps ];
    text = ''
      target=""
      for name in vrserver steam; do
        for p in $(pgrep -x -u "$(id -u)" "$name" || true); do
          target=$(readlink "/proc/$p/ns/net") && break 2
        done
      done
      uu=/run/netns/uu
      if [ -n "$target" ] && [ -e "$uu" ] && [ -x /run/wrappers/bin/uu-netns ] \
        && [ "$target" = "net:[$(stat -L -c %i "$uu")]" ] \
        && [ "$target" != "$(readlink /proc/self/ns/net)" ]; then
        exec /run/wrappers/bin/uu-netns "$@"
      fi
      exec "$@"
    '';
  };

  wayvr = pkgs.symlinkJoin {
    name = "wayvr-${pkgs.wayvr.version}";
    paths = [ pkgs.wayvr ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm $out/bin/wayvr
      # SteamVR 的 vrclient.so 依赖 libGL / libEGL / libuuid，宿主上找不到时 OpenVR 初始化直接失败
      # （WayVR 用 Vulkan，自己不会加载这几个库）。LD_LIBRARY_PATH 要在进入网络命名空间之后再设：
      # uu-netns 带 capability，执行它时 glibc 进入安全模式，会清掉 LD_LIBRARY_PATH。
      # nixpkgs 只给 uidev 补了 dlopen 的库，wayvr 主程序的 RUNPATH 里没有 vulkan-loader，启动 OpenVR
      # 后端时报 "libvulkan.so.1: cannot open shared object file"。
      makeWrapper ${pkgs.wayvr}/bin/wayvr $out/libexec/wayvr \
        --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath (with pkgs; [
          libglvnd util-linux.lib vulkan-loader wayland libxcursor libxi ])}
      makeWrapper ${steamvrNetns}/bin/steamvr-netns $out/bin/wayvr --add-flags $out/libexec/wayvr
    '';
  };
in
{
  _module.args.steamvrNetns = steamvrNetns;

  environment.systemPackages = [
    steamvrNetns
    # WayVR：VR 里的桌面叠加层（屏幕、键盘、手腕面板），支持 OpenVR（SteamVR）和 OpenXR。
    # 上游因为 SteamVR 的 bug 不再注册自动启动，要在 SteamVR 起来后手动运行 wayvr。
    # 首次启动 KDE 会弹出屏幕共享框，按通知里提示的顺序选择屏幕。经 steamvr-netns 启动。
    wayvr
    vrmonitorUrlHandler
    (pkgs.makeDesktopItem {
      name = "vrmonitor-url-handler";
      desktopName = "SteamVR 链接处理";
      comment = "在 Steam 的沙箱里打开 vrmonitor:// 链接";
      exec = "vrmonitor-url-handler %u";
      icon = "steamvr";
      noDisplay = true;
      mimeTypes = [ "x-scheme-handler/vrmonitor" ];
    })
  ];
  # 用户目录里 SteamVR 自己生成的 valve-vrmonitor.desktop 也声明了这个协议，但它在沙箱外直接运行
  # vrmonitor.sh，这里指定默认程序覆盖它。
  xdg.mime.defaultApplications."x-scheme-handler/vrmonitor" = "vrmonitor-url-handler.desktop";

  programs.steam = {
    # Steam Link 通过 Steam 远程同乐的局域网发现找到电脑：UDP 27031-27036、TCP 27036-27037。
    remotePlay.openFirewall = true;

    # SteamVR 仪表盘（手柄菜单键呼出）由 vrwebhelper（CEF）渲染。Steam 的 FHS 环境里没有
    # libatk-bridge-2.0 / libatk-1.0 / libatspi，vrwebhelper 一启动就报
    # “error while loading shared libraries: libatk-bridge-2.0.so.0”退出。补上之后还缺 NSS：
    # Steam Runtime（scout）自带的 libnss3 太旧（libcef 要 NSS_3.30+），宿主有更新的会优先用宿主的。
    #
    # pactl：Steam 开始串流时用它设置音频，FHS 环境里没有，日志里刷满“pactl: 未找到命令”。
    extraPackages = with pkgs; [
      at-spi2-core
      nss
      nspr
      pulseaudio
    ];

    # Wayland 下 Steam 要加 -pipewire 才能捕获桌面（否则日志是“Desktop capture unavailable, try
    # running Steam with -pipewire”），经 xdg-desktop-portal 的屏幕录制。
    #
    # 已知崩溃（与 -pipewire 无关）：在 SteamVR 菜单里点「桌面」时 Steam 开始桌面串流，按 X 根窗口
    # 大小（两块 4K 屏、XWayland 缩放 2 时是 6000x3840，2304 万像素）准备 NV12 帧，约 3460 万字节，
    # 超出它约 32 MiB 的缓冲区，steamui.so 的串流线程在 memset 里越界段错误，Steam 和 SteamVR 一起退出。
    # 在 VR 里看桌面用 WayVR。
    package = pkgs.steam.override { extraArgs = "-pipewire"; };
  };

  # vrlink 的串流端口（vrlink 日志 driver_vrlink.txt 里是 “Socket bound to port 10400”）。
  networking.firewall.allowedUDPPortRanges = [ { from = 10400; to = 10401; } ];

  # vrlink 用 dlopen("libcrypto.so") 加载 OpenSSL 做串流加密。vrserver 跑在 Steam Linux Runtime
  # sniper 容器里，容器只有 libcrypto.so.1.1、没有不带版本号的 libcrypto.so，于是退回到纯软件 AES
  # （日志 “Soft AES PERF: ~20 MByte/s”、“OpenSSL EVP (New) AES PERF: 0”），高码率时可能成为瓶颈。
  # dlopen 会搜索调用者的 RUNPATH（$ORIGIN/../../../../bin/linux64，即 SteamVR/bin/linux64），
  # 所以在那里放一个指向容器内 libcrypto.so.1.1 的链接。目标路径只在 sniper 容器里存在，宿主上看是断链。
  # 若 SteamVR 换成 Steam Linux Runtime 4（libcrypto.so.3），这里要跟着改。
  systemd.user.tmpfiles.rules = [
    "L+ %h/.local/share/Steam/steamapps/common/SteamVR/bin/linux64/libcrypto.so - - - - /usr/lib/x86_64-linux-gnu/libcrypto.so.1.1"
  ];
}
