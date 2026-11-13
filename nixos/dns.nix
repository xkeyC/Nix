# 系统 DNS：腾讯 DNSPod / 阿里 AliDNS / Cloudflare 1.1.1.1。
#
# 将公共 DNS 放在连接提供的 DNS 之后，让 DHCP 下发的内网 DNS 优先。
# 公共 DNS 不能解析局域网域名，且 NXDOMAIN 不会触发后续服务器重试。
{ ... }:

{
  networking.networkmanager.appendNameservers = [
    "119.29.29.29" # 腾讯 DNSPod
    "223.5.5.5" # 阿里 AliDNS
    "1.1.1.1" # Cloudflare
  ];
}
