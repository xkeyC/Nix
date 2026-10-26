# SteamVR（通过 Steam 安装，本身无需 NixOS 配置）的配套设置。
#
# 已知限制：SteamVR 首次启动会试图用 pkexec 给 vrcompositor-launcher 加 cap_sys_nice，
# 然后弹“SteamVR setup is incomplete, some features might be missing”。nixpkgs 的 Steam
# 跑在 bubblewrap 用户命名空间里，setuid/文件 capability 都不生效，所以这一步在 NixOS 上
# 必然失败，缺的只是 SteamVR 自己合成器的异步重投影（高优先级 GPU 队列）；点确定继续即可。
# 绕过需要打补丁的 bwrap 或内核，有安全代价，见 https://wiki.nixos.org/wiki/VR#SteamVR 。
{
  # vrserver / vrcompositor / ALVR 驱动通过 RealtimeKit 提升线程优先级；没有它日志里全是
  # “org.freedesktop.RealtimeKit1 ... not activatable”。PipeWire 也会用到。
  security.rtkit.enable = true;
}
