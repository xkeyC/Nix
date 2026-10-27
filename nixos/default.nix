# 本机 NixOS 自定义配置入口。
#
# 由 flake.nix 通过 `nixosConfigurations.xkeyc-nixos` -> configuration.nix
# -> `./nixos/default.nix` 引入。日常改动后用系统命令重建即可：
#   sudo nixos-rebuild switch   # 自动使用本 flake
{
  imports = [
    ./system.nix       # 引导、主机名、网络、时区与语言、固件
    ./nix-settings.nix # allowUnfree、国内镜像与 CUDA 缓存
    ./users.nix        # 用户账户（密码哈希在 private/）
    ./ssh.nix          # OpenSSH
    ./nvidia.nix       # NVIDIA 驱动、Docker + 容器工具链、CUDA
    ./desktop.nix      # KDE Plasma 6 + 字体
    ./storage.nix      # NTFS 数据盘
    ./input-method.nix # Fcitx5 + RIME(雾凇拼音)，以及 KWin 启动输入法
    ./dns.nix          # 系统 DNS（腾讯 / 阿里 / Cloudflare）
    ./power-management.nix # 禁用睡眠/休眠，保留 KDE 自动关屏
    ./flclash-tun.nix  # FlClash TUN 模式的特权 Helper
    ./gaming.nix       # Steam 与 DW-Proton 兼容工具
    ./chaos-hdr.nix    # NVIDIA TrueHDR KWin 特效（给 SDR 游戏窗口做 HDR）
    ./desktop-gpu.nix  # 桌面临时改用核显渲染（desktop-gpu igpu|nvidia，重新登录生效）
    ./dlss5vklayer.nix # DLSS 5 Neural Rendering Vulkan 层 + Wine helper
    ./uu-remote.nix    # UU 远程 Linux 被控端（非官方 uu-remote-linux）
    ./home-manager.nix # 用户级软件包（QQ / FlClash）与 Home Manager 设置
    ./dev-toolchains.nix # 开发工具链（Rust / Python / Node / Flutter / Go / C++）+ nix-ld
    ./ai               # 本地 AI 服务（Strata，不自启）
  ];

  # 启用 flakes（nixos-rebuild 调用 nix 时会自带 nix-command/flakes 参数）。
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
