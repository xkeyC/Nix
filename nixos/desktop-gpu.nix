# 桌面临时改用核显渲染：显示器仍然接在 4090 上，KWin 在核显（Raphael，amdgpu）上合成画面，
# 每一帧再拷贝到 4090 输出。Strata 等程序占满 4090 时，桌面不会跟着卡顿。
#
# 切换：`desktop-gpu igpu` 或 `desktop-gpu nvidia`，然后注销重新登录；不带参数查看当前状态。
# startplasma 登录时会执行 ~/.config/plasma-workspace/env/*.sh，导出的变量会传给
# plasma-kwin_wayland.service。核显模式下这个脚本设置：
#   * KWIN_DRM_DEVICES=<核显>:<独显>：第一个设备负责渲染，其余设备只负责输出。card 序号每次开机
#     可能不同，所以登录时按 sysfs 里的驱动名查找。
#   * EGL / GLX 只使用 Mesa：浏览器、Electron 等 OpenGL 程序也在核显上渲染。Vulkan 程序（游戏）
#     仍然会选 4090，CUDA 不受影响。
# Chaos HDR 特效依赖 NVIDIA NGX，核显模式下不加载（见 chaos-hdr.nix）。
# 核显只有 2 个 CU，带两块 4K 高刷 HDR 屏比较勉强；不够流畅时可以把刷新率降到 60 Hz。
{ pkgs, ... }:

let
  flag = "kwin-render-igpu"; # 位于 ~/.config，存在时表示核显模式

  envScript = ''
    # 由 nixos/desktop-gpu.nix 生成：~/.config/${flag} 存在时让 KWin 在核显上渲染。
    if [ -e "''${XDG_CONFIG_HOME:-$HOME/.config}/${flag}" ]; then
      igpu= dgpu=
      for card in /sys/class/drm/card[0-9]*; do
        case ''${card##*/} in *-*) continue ;; esac
        driver=$(${pkgs.coreutils}/bin/readlink "$card/device/driver")
        case ''${driver##*/} in
          amdgpu) igpu=/dev/dri/''${card##*/} ;;
          nvidia) dgpu=/dev/dri/''${card##*/} ;;
        esac
      done
      if [ -n "$igpu" ] && [ -n "$dgpu" ]; then
        export KWIN_DRM_DEVICES="$igpu:$dgpu"
        export __EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json
        export __GLX_VENDOR_LIBRARY_NAME=mesa
      fi
    else
      # 核显会话异常退出时，这些变量可能留在 systemd 用户环境里。
      ${pkgs.systemd}/bin/systemctl --user unset-environment \
        KWIN_DRM_DEVICES __EGL_VENDOR_LIBRARY_FILENAMES __GLX_VENDOR_LIBRARY_NAME
    fi
  '';

  desktop-gpu = pkgs.writeShellApplication {
    name = "desktop-gpu";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.systemd ];
    text = ''
      flag="''${XDG_CONFIG_HOME:-$HOME/.config}/${flag}"
      case "''${1:-}" in
        igpu)
          touch "$flag"
          echo "已切换为核显渲染，注销后重新登录生效。" ;;
        nvidia)
          rm -f "$flag"
          echo "已切换为 4090 渲染，注销后重新登录生效。" ;;
        "") ;;
        *)
          echo "用法：desktop-gpu [igpu|nvidia]" >&2
          exit 2 ;;
      esac
      if [ -e "$flag" ]; then echo "下次登录：核显渲染"; else echo "下次登录：4090 渲染"; fi
      # KWin 带 cap_sys_nice，/proc/<pid>/environ 读不到；改看 systemd 用户环境（KWin 服务的环境就来自这里）。
      if devices=$(systemctl --user show-environment | grep '^KWIN_DRM_DEVICES='); then
        echo "当前会话：核显渲染（''${devices#*=}）"
      else
        echo "当前会话：4090 渲染"
      fi
    '';
  };
in
{
  environment.systemPackages = [ desktop-gpu ];

  home-manager.sharedModules = [
    { xdg.configFile."plasma-workspace/env/desktop-gpu.sh".text = envScript; }
  ];
}
