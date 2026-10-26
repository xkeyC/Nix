# WiVRn：把 OpenXR 画面串流到一体机（头显里装 WiVRn 客户端，同一局域网自动发现）。
# 桌面上开 WiVRn 面板（wivrn-dashboard）启动服务器，或 `systemctl --user start wivrn`。
# Steam 游戏的启动项还要加
#   PRESSURE_VESSEL_FILESYSTEMS_RW=$XDG_RUNTIME_DIR/wivrn/comp_ipc %command%
# 让容器里的游戏能连上 WiVRn 的 socket。
{
  services.wivrn = {
    enable = true;
    # TCP/UDP 9757，头显连接用；局域网发现走 Avahi（模块自动启用）。
    openFirewall = true;
    # 异步重投影需要 cap_sys_nice。
    highPriority = true;
    # 让 Steam（pressure-vessel 容器）里的游戏能找到 WiVRn 的 OpenXR 运行时。
    # 改的是会话环境变量，switch 后要注销重新登录。
    steam.importOXRRuntimes = true;
  };
}
