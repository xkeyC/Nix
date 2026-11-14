# 系统 DNS：腾讯 DNSPod / 阿里 AliDNS / Cloudflare 1.1.1.1。
#
# 先使用阿里 DNS；TUN 开启时，发往该地址的 DNS 查询由 FlClash 接管。
# DHCP 下发的 DNS 保留在其后；公共 DNS 返回 NXDOMAIN 时不会尝试内网 DNS。
{ ... }:

{
  # 由 resolvconf 在每次生成 resolv.conf 时维护顺序，避免被后续更新覆盖。
  networking.resolvconf.extraConfig = ''
    name_servers="223.5.5.5"
    name_servers_append="119.29.29.29 1.1.1.1"
  '';
}
