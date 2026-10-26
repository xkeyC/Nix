# DLSS5VKLayer：游戏里的 Vulkan 层 + Wine 里跑的 DLSS 5 Neural Rendering helper。
#
# 打包见 packages/dlss5vklayer.nix。用法：
#   1. dlssnr-gui（或 dlssnr-helper start）启动 helper；
#   2. Steam 启动项加 `VKLayer_DLSS5=1 %command%`（不加则层不启用）。
# 首次使用需导入 nvngx_dlssnr.dll：GUI 齿轮菜单 → NGX binaries，或
#   dlssnr-helper import-binaries <目录>。
#
# helper 的 runner 用 DW-Proton（自带 DXVK-NVAPI）。dwproton 的 wine 是给 Steam Runtime
# 编译的 FHS 二进制，在 NixOS 宿主上要经 steam-run 启动；dlssnr-dwproton 就是这个包装，
# 在 ~/.config/dlssnr/config.ini 里设 runner_type=proton、runner_path=dlssnr-dwproton。
{ config, pkgs, ... }:

let
  dlss5vklayer = pkgs.callPackage ./packages/dlss5vklayer.nix { };

  # 不能 exec：steam-run 最终 exec 成 `bwrap --die-with-parent`。若一路 exec 下去，bwrap 的
  # 父进程就成了很快退出的 `dlssnr-helper start`，它一退出内核就 SIGKILL 整个 Proton。
  # 留着这个 shell 当 bwrap 的父进程；stop 时 helper 脚本按进程组发信号，bwrap 也会收到。
  dwprotonRunner = pkgs.writeShellScriptBin "dlssnr-dwproton" ''
    ${config.programs.steam.package.run}/bin/steam-run \
      ${pkgs.dwproton-bin.steamcompattool}/proton "$@"
  '';
in
{
  environment.systemPackages = [ dlss5vklayer dwprotonRunner ];

  # 层清单放进 /run/opengl-driver(-32)/share/vulkan/implicit_layer.d，Steam 的 FHS 环境
  # 和 pressure-vessel 都从这里导入宿主的 Vulkan 层。64/32 位清单靠 library_arch 区分。
  hardware.graphics.extraPackages = [ dlss5vklayer.runtime ];
  hardware.graphics.extraPackages32 = [ dlss5vklayer.runtime ];

  # 让游戏里的层与 helper/GUI 用同一块共享内存（见打包说明里的 privateTmp 问题）。
  environment.sessionVariables.DLSSNR_SHM = "/dev/shm/dlssnr-xkeyc/shm.bin";
}
