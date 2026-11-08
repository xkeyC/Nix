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

{
  programs.steam = {
    # Steam Link 通过 Steam 远程同乐的局域网发现找到电脑：UDP 27031-27036、TCP 27036-27037。
    remotePlay.openFirewall = true;

    # SteamVR 仪表盘（手柄菜单键呼出）由 vrwebhelper（CEF）渲染。Steam 的 FHS 环境里没有
    # libatk-bridge-2.0 / libatk-1.0 / libatspi，vrwebhelper 一启动就报
    # “error while loading shared libraries: libatk-bridge-2.0.so.0”退出。补上之后还缺 NSS：
    # Steam Runtime（scout）自带的 libnss3 太旧（libcef 要 NSS_3.30+），宿主有更新的会优先用宿主的。
    extraPackages = with pkgs; [
      at-spi2-core
      nss
      nspr
    ];
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
