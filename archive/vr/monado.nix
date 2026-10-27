# Monado：OpenXR 运行时（nixpkgs 模块），给有线头显用。以用户服务 + socket 激活运行，
# OpenXR 程序连接 $XDG_RUNTIME_DIR/monado_comp_ipc 时才启动 monado-service。
# 不设为默认运行时：默认运行时由正在用的那一套（SteamVR 或 WiVRn）在用户目录里管理。
# 临时使用时：`systemctl --user start monado`，程序加 XR_RUNTIME_JSON=
#   /run/current-system/sw/share/openxr/1/openxr_monado.json。
{
  services.monado = {
    enable = true;
    defaultRuntime = false;
    # 默认 highPriority = true：monado-service 带 cap_sys_nice，异步重投影需要。
  };
}
