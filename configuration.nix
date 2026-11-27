# ai-max-395：无头服务器，只通过 SSH 管理。
# 部署（在主力机 ~/Nix-ai-max-395 里）：
#   nixos-rebuild switch --flake .#ai-max-395 --target-host root@ai-max-395.local
{ pkgs, ... }:

let
  # 主力机 ~/.ssh/id_rsa 的公钥。
  sshKeys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC9SXTBwV72WuLakQN2n9514MhqbxXb3m/QdFtHA3DiraSF/znRATbgkQRULPT1/rPANwY7TsI6jbzRpZSQvh2aCp/T2/EiO5pagFWL92nfr3FzcawLi1Yv9wB9BrGDVKGYjKhQOu/k3EQ1c6ejVm2/QhJTYBl1/g9PlnqTTJx2zvhtlIPvhHDeovHV6DyyIV2yMoqsyA7MteSD8pe+d/QMIdKcsLEKuxUhGucbNgYztlMUGIZz3Q7yC3OjCMpSr+4nLBG0dlu6+QIgw6CuC7wlOP99NckL+h1Krr4v6cZOfbMRwpEDF2lqN9QKexVZcA0ft/5ZL6x4l+qdthU5b7dR xkeyc@xkeyc-nixos"
  ];
in
{
  # 引导
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 8;
  boot.loader.efi.canTouchEfiVariables = true;
  # Strix Halo（gfx1151）在新内核上支持更完整。
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # 网络：NetworkManager。有线优先，Wi-Fi 备用。
  #   * 两个 RTL8125 2.5G 网口（eno1 68:1d:ef:67:37:fa，enp196s0 68:1d:ef:67:37:fb）各一个 DHCP 配置，
  #     插线即连。
  #   * Wi-Fi 连接文件（XK_5G）是安装时从 live 系统拷入的，含密码，不进 git。
  #   * 有线和 Wi-Fi 可以同时在线，默认路由按 metric 选：有线 100，Wi-Fi 600。拔掉网线后
  #     自动走 Wi-Fi，不用重连。
  networking.hostName = "ai-max-395";
  networking.networkmanager = {
    enable = true;
    # 不再自动生成「有线连接 N」，有线只用下面声明的配置。
    settings.main.no-auto-default = "*";
    # 没写 metric 的连接按类型取默认值（Wi-Fi 配置文件不在 git 里，靠这里统一）。
    settings.connection-ethernet = {
      match-device = "type:ethernet";
      "ipv4.route-metric" = 100;
      "ipv6.route-metric" = 100;
    };
    settings.connection-wifi = {
      match-device = "type:wifi";
      "ipv4.route-metric" = 600;
      "ipv6.route-metric" = 600;
    };
    ensureProfiles.profiles = let
      wired = ifname: {
        connection = {
          id = "wired-${ifname}";
          type = "ethernet";
          interface-name = ifname;
          autoconnect = true;
          autoconnect-priority = 100;
        };
        ipv4 = { method = "auto"; route-metric = 100; };
        ipv6 = { method = "auto"; addr-gen-mode = "stable-privacy"; route-metric = 100; };
      };
    in {
      wired-eno1 = wired "eno1";
      wired-enp196s0 = wired "enp196s0";
    };
  };
  networking.firewall.enable = true;
  # 局域网可用 ai-max-395.local 访问。
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = { enable = true; addresses = true; };
  };

  # 局域网 HTTP 代理（主力机上的代理）。只给 nix-daemon 用，拉 GitHub 上的 flake 输入；
  # 二进制缓存走国内镜像，不经过代理。代理不可用时删掉这段即可。
  systemd.services.nix-daemon.environment = {
    http_proxy = "http://192.168.6.201:7890";
    https_proxy = "http://192.168.6.201:7890";
    no_proxy = "127.0.0.1,localhost,192.168.0.0/16,.local,mirror.sjtu.edu.cn,mirrors.tuna.tsinghua.edu.cn,mirrors.ustc.edu.cn";
  };

  # Tailscale：接入 xkeyc.com 上的 Headscale，节点名 395-xkeyc。
  # 首次登录用的一次性 pre-auth key 在 /var/lib/tailscale/authkey（不进 git，登录后即失效）。
  # 与主力机一致：只连 tailnet 节点，不接收子网路由 / DNS，不用也不发布出口节点。
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "none";
    authKeyFile = "/var/lib/tailscale/authkey";
    extraUpFlags = [
      "--login-server=https://hsapi.xkeyc.com"
      "--hostname=395-xkeyc"
    ];
    extraSetFlags = [
      "--hostname=395-xkeyc"
      "--accept-dns=false"
      "--accept-routes=false"
      "--exit-node="
      "--advertise-exit-node=false"
      "--advertise-routes="
    ];
  };

  time.timeZone = "Asia/Singapore";
  i18n.defaultLocale = "zh_CN.UTF-8";

  # SSH：只允许公钥登录。
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = sshKeys;
  # 密码在安装后用 passwd 设置（mutableUsers 默认开启），不写进仓库。
  users.users.xkeyc = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "render" ];
    openssh.authorizedKeys.keys = sshKeys;
  };

  # Nix
  nixpkgs.config.allowUnfree = true;
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "@wheel" ];
    auto-optimise-store = true;
    substituters = [
      "https://mirror.sjtu.edu.cn/nix-channels/store?priority=10"
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store?priority=20"
      "https://mirrors.ustc.edu.cn/nix-channels/store?priority=30"
      "https://cache.nixos.org?priority=40"
    ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    persistent = true;
    options = "--delete-older-than 14d";
  };

  # 内存与 btrfs 维护
  zramSwap.enable = true;
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
  services.fstrim.enable = true;
  services.fwupd.enable = true;

  # GPU（无头也需要 amdgpu 用户态驱动，供 Vulkan/ROCm 计算）
  hardware.graphics.enable = true;

  environment.systemPackages = with pkgs; [
    git
    vim
    tmux
    htop
    btop
    nvtopPackages.amd
    pciutils
    usbutils
    lm_sensors
    smartmontools
    nvme-cli
    compsize
    wget
    curl
    vulkan-tools
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
  ];

  system.stateVersion = "26.11";
}
