# VR 相关配置。每个工具一个文件，自己打包的东西放在 ./packages。
# 运行时用 SteamVR，头显（Quest 3）通过 Steam Link 串流。
# ALVR、WiVRn、Monado 的旧配置已删除，需要时从提交 4f5a0fb 的 archive/vr 找回。
{
  imports = [
    ./steamvr.nix      # SteamVR + Steam Link VR（防火墙、vrlink 的 OpenSSL、仪表盘依赖）、WayVR
    ./papertracker.nix # PaperTracker 面捕/眼追（GE-Proton + umu，SteamVR 叠加层）
    ./vivehub.nix      # VIVE Hub：VIVE Ultimate Tracker 配对、建图，带姿态 SDK
  ];
}
