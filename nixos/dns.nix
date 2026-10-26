# 系统 DNS：腾讯 DNSPod / 阿里 AliDNS / Cloudflare 1.1.1.1。
#
# 通过 NetworkManager 的 dispatcher 脚本在每次连接事件时把这三个服务器
# 插到 /etc/resolv.conf 最前面（insertNameservers），对所有连接生效。
{ ... }:

{
  networking.networkmanager.insertNameservers = [
    "119.29.29.29" # 腾讯 DNSPod
    "223.5.5.5" # 阿里 AliDNS
    "1.1.1.1" # Cloudflare
  ];
}
