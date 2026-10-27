# SteamVR（通过 Steam 安装，本身无需 NixOS 配置）的配套设置。
#
# 已知限制：SteamVR 首次启动会试图用 pkexec 给 vrcompositor-launcher 加 cap_sys_nice，
# 然后弹出“SteamVR setup is incomplete, some features might be missing”。nixpkgs 的 Steam
# 运行在 bubblewrap 用户命名空间里，setuid/文件 capability 都不生效，所以这一步在 NixOS 上
# 必然失败，缺少的只是 SteamVR 自己合成器的异步重投影（高优先级 GPU 队列）；点确定继续即可。
# 要绕过这个限制，需要给 bwrap 或内核打补丁，有安全风险，见 https://wiki.nixos.org/wiki/VR#SteamVR 。
{ pkgs, ... }:

{
  # vrserver / vrcompositor / ALVR 驱动通过 RealtimeKit 提升线程优先级；没有它日志里全是
  # “org.freedesktop.RealtimeKit1 ... not activatable”。PipeWire 也会用到。
  security.rtkit.enable = true;

  # SteamVR 仪表盘（手柄菜单键呼出）由 vrwebhelper（CEF）渲染。Steam 的 FHS 环境里没有
  # libatk-bridge-2.0 / libatk-1.0 / libatspi，vrwebhelper 一启动就报
  # “error while loading shared libraries: libatk-bridge-2.0.so.0”退出，菜单永远加载不出来。
  # 补上这些库之后，下一个缺少的是 NSS：Steam Runtime（scout）自带的 libnss3 太旧，libcef 要 NSS_3.30+，
  # 宿主里有更新的 nss/nspr 时 Steam Runtime 会优先用宿主的。
  programs.steam.extraPackages = with pkgs; [
    at-spi2-core
    nss
    nspr
  ];
}
