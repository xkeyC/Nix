# UU 主机加速（Steam Deck 插件）：只加速 Steam，其他程序不受影响。
#
# UU 只运行在网络命名空间 uu 里，用哪个快捷方式决定 Steam 进不进这个空间：
#   * Steam（UU 加速）：Steam 及其子进程在 uu 空间，由 UU 加速。UU 随它启动和退出。
#   * Steam（原来的快捷方式）：Steam 在主机网络里，和 UU 无关。
# 这个空间用 macvlan 直接接到 enp6s0，有自己的 MAC 和局域网 IP，不经过主机的路由表和防火墙，
# 所以 FlClash TUN 管不到它（Steam 商店也不走代理）。主机和这个空间之间不能互相访问。
#
# 首次使用：启动「Steam（UU 加速）」，手机和电脑连同一局域网，用 UU 主机加速 App 绑定 Steam Deck。
# 绑定信息在 /var/lib/uuplugin。日志：journalctl -u uuplugin -f
#
# 插件以 root 运行，会连接网易服务器、上报崩溃，并能执行服务器下发的命令。因此：
#   * 不给 curl / wget，让它无法自更新（升级见 packages/uuplugin.nix）。
#   * 看不到 /home、硬盘设备和主机的 /run（docker.sock、D-Bus），系统目录只读，只保留必要的 capability。
#     CAP_DAC_OVERRIDE 不能去掉：它要在 /sys/fs/cgroup（权限 555）建 cgroup，
#     再用 iptables -m cgroup 给自身流量打标记，否则这些流量会绕回它自己的 TUN。
#
# Steam 只能运行一个实例，换快捷方式前要先退出。命名空间里收不到 udevd 的广播，
# 手柄可能要在启动「Steam（UU 加速）」之前连好。
{ config, pkgs, ... }:

let
  uuplugin = pkgs.callPackage ./packages/uuplugin.nix { };

  lan = "enp6s0";
  # 固定 MAC，路由器的 DHCP 租约不变。
  macvlanAddress = "02:75:75:00:00:01";
  # App 通过这些端口发现和绑定设备（ss 实测，与 AUR 评论一致）。
  tcpPorts = [ 14554 16363 ];
  udpPorts = [ 16363 ];

  netnsUp = pkgs.writeShellScript "uu-netns-up" ''
    set -eu
    ip netns del uu 2>/dev/null || true
    ip netns add uu
    ip link add link ${lan} name uuwan0 netns uu address ${macvlanAddress} type macvlan mode bridge

    ns() { ip netns exec uu "$@"; }
    ns ip link set lo up
    # 只走 IPv4，避免游戏的 IPv6 流量绕过 UU。
    ns sysctl -q -w net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1

    # 主机防火墙管不到这个空间，这里只放行回包、DHCP 和绑定端口。
    # UU 启动后会自己插入 TUN 网卡的放行规则。
    ns iptables -w -A INPUT -i lo -j ACCEPT
    ns iptables -w -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ns iptables -w -A INPUT -p udp --sport 67 --dport 68 -j ACCEPT
    for port in ${toString tcpPorts}; do
      ns iptables -w -A INPUT -i uuwan0 -p tcp --dport "$port" -j ACCEPT
    done
    for port in ${toString udpPorts}; do
      ns iptables -w -A INPUT -i uuwan0 -p udp --dport "$port" -j ACCEPT
    done
    ns iptables -w -P INPUT DROP
    ns iptables -w -P FORWARD DROP
  '';

  dhcpScript = pkgs.writeShellScript "uu-netns-dhcp-event" ''
    case "$1" in
      deconfig)
        ip addr flush dev "$interface"
        ip link set "$interface" up
        ;;
      bound)
        ip addr flush dev "$interface"
        ip addr add "$ip/$mask" dev "$interface"
        ip route replace default via "''${router%% *}" dev "$interface"
        ;;
      renew)
        ip addr replace "$ip/$mask" dev "$interface"
        ip route replace default via "''${router%% *}" dev "$interface"
        ;;
    esac
  '';

  sandbox = {
    NetworkNamespacePath = "/run/netns/uu";
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" "CAP_NET_BIND_SERVICE" ];
  };

  uuNetns = pkgs.runCommandCC "uu-netns" { buildInputs = [ pkgs.glibc.static ]; } ''
    mkdir -p $out/bin
    cc -static -O2 -Wall -Wextra -Werror -o $out/bin/uu-netns ${./packages/uu-netns.c}
  '';

  netnsRun = "/run/wrappers/bin/uu-netns";
  steamUu = pkgs.writeShellApplication {
    name = "steam-uu";
    runtimeInputs = with pkgs; [ coreutils iproute2 libnotify procps systemd ];
    # 运行 Steam 用系统 PATH 里的 steam。
    inheritPath = true;
    text = ''
      fail() {
        echo "steam-uu: $1" >&2
        notify-send -a steam-uu -i steam "UU 加速" "$1" || true
        exit 1
      }

      want="net:[$(stat -L -c %i /run/netns/uu 2>/dev/null || true)]"
      running=
      for pid in $(pgrep -x -u "$UID" steam || true); do
        [ "$(readlink "/proc/$pid/ns/net")" = "$want" ] || fail "Steam 正在 UU 空间外运行，请先退出 Steam。"
        running=1
      done
      # steam:// 链接之类，只是转交给已运行的实例，不影响 UU。
      if [ -n "$running" ]; then
        exec ${netnsRun} steam "$@"
      fi

      systemctl start uuplugin.service || fail "无法启动 uuplugin.service，见 journalctl -u uuplugin。"
      # 等 DHCP 拿到地址，否则 Steam 一启动就进入离线状态。
      for _ in $(seq 15); do
        [ -n "$(${netnsRun} ip -4 route show default)" ] && break
        sleep 1
      done

      # 不用 exec：Steam 退出后要停掉 UU。
      status=0
      ${netnsRun} steam "$@" || status=$?
      systemctl stop uuplugin.service || true
      exit "$status"
    '';
  };
in
{
  environment.systemPackages = [
    steamUu
    (pkgs.makeDesktopItem {
      name = "steam-uu";
      desktopName = "Steam（UU 加速）";
      comment = "UU 只加速 Steam 及其子进程";
      exec = "steam-uu %U";
      icon = "steam";
      categories = [ "Game" ];
    })
  ];

  systemd.services.uu-netns = {
    description = "Network namespace shared by UU and Steam";
    bindsTo = [ "sys-subsystem-net-devices-${lan}.device" ];
    after = [ "sys-subsystem-net-devices-${lan}.device" ];
    path = with pkgs; [ iproute2 iptables procps ];
    # 重建命名空间后，运行中的 Steam 还留在旧空间里，和 UU 分开了。
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = netnsUp;
      ExecStop = "${pkgs.iproute2}/bin/ip netns del uu";
    };
  };

  systemd.services.uu-netns-dhcp = {
    description = "DHCP client of the UU network namespace";
    bindsTo = [ "uu-netns.service" ];
    after = [ "uu-netns.service" ];
    path = [ pkgs.iproute2 ];
    serviceConfig = sandbox // {
      ExecStart = "${pkgs.busybox}/bin/udhcpc -f -i uuwan0 -s ${dhcpScript}";
      Restart = "always";
      RestartSec = 5;
    };
  };

  systemd.services.uuplugin = {
    description = "UU accelerator in the uu network namespace";
    bindsTo = [ "uu-netns.service" ];
    wants = [ "uu-netns-dhcp.service" ];
    after = [ "uu-netns.service" "uu-netns-dhcp.service" ];
    # 不放 curl / wget / tar，见文件开头。
    path = with pkgs; [ coreutils gawk gnugrep gnused iproute2 iptables ipset nftables procps ];
    serviceConfig = sandbox // {
      ExecStart = "${uuplugin}/bin/uuplugin ${uuplugin}/share/uuplugin/uu.conf";
      # .uuplugin_uuid（设备标识）写在工作目录。
      StateDirectory = "uuplugin";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/uuplugin";
      # 空的 /run，只用来放 uuplugin.pid 和 xtables.lock。
      TemporaryFileSystem = "/run";
      CapabilityBoundingSet = sandbox.CapabilityBoundingSet ++ [ "CAP_DAC_OVERRIDE" ];
      BindPaths = [ "/dev/net/tun" ];
      DeviceAllow = [ "/dev/net/tun rw" ];
      Restart = "on-failure";
      RestartSec = 5;
      # 收到 SIGINT 才会清理自己加的路由和 iptables 规则。
      KillSignal = "SIGINT";
      KillMode = "mixed";
      TimeoutStopSec = 20;
    };
  };

  # 快捷方式启动和停止 UU 时不用输入密码。
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" && subject.user == "xkeyc" &&
          action.lookup("unit") == "uuplugin.service" &&
          ["start", "stop"].indexOf(action.lookup("verb")) >= 0) {
        return polkit.Result.YES;
      }
    });
  '';

  security.wrappers.uu-netns = {
    source = "${uuNetns}/bin/uu-netns";
    capabilities = "cap_sys_admin+ep";
    owner = "root";
    group = config.users.users.xkeyc.group;
    permissions = "u+rx,g+x";
  };

  # UU 没有加载模块的权限，提前加载它要用的。
  boot.kernelModules = [ "macvlan" "tun" "nfnetlink" "nf_conntrack_netlink" "xt_cgroup" ];
}
