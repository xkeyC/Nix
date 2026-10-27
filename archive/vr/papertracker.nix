# PaperTracker：无线面捕/眼追设备，Windows 客户端用 GE-Proton 运行
# （~/.local/share/papertracker/papertracker.sh，各项修正写在脚本注释里）。
#
# 客户端每秒在局域网广播自己的地址，设备收到后通过 UDP 把握手和图像流发送到客户端的 45454 端口。
# 防火墙默认静默丢弃这些 UDP，表现为“设备找不到 PC”。
# OSC（9000/9001）和 OSCQuery 只跟本机的 VRChat 通信，经过回环接口，不需要放行。
{
  networking.firewall.allowedUDPPorts = [ 45454 ];
}
