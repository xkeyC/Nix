# 本机 DNS 按域名分流，避免公网解析器的 NXDOMAIN 覆盖内网域名。
{ ... }:

{
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      no-resolv = true;
      listen-address = "127.0.0.1";
      bind-interfaces = true;
      server = [
        "223.5.5.5" # 公网 DNS；TUN 开启时由 FlClash 接管
        "/lan/192.168.6.1" # 路由器 DHCP 内网域名
        "//192.168.6.1" # 无后缀的局域网主机名
        "/p2p.xkeyc.com/100.100.100.100" # Headscale MagicDNS
      ];
    };
  };

  # resolvconf 每次生成 resolv.conf 时均将本地分流器放在首位。
  networking.resolvconf.extraConfig = ''
    name_servers="127.0.0.1"
  '';
}
