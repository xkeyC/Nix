# Sunshine：登录 Plasma 后启动，首次访问 https://localhost:47990 创建账号并配对。
# CUDA 构建支持 NVIDIA HDR 路径；KMS 捕获需要 CAP_SYS_ADMIN。
# NVIDIA Wayland HDR 仍需通过 Moonlight 实际验证。
# 状态：systemctl --user status sunshine；日志：journalctl --user -u sunshine -f
{ pkgs, ... }:
{
  services.sunshine = {
    enable = true;
    package = pkgs.sunshine.override { cudaSupport = true; };
    capSysAdmin = true;
    openFirewall = true;
  };
}
