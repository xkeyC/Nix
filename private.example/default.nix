# 隐私配置模板。新机器上：
#   cp -r private.example private   # 然后填入真实值
#   nix flake update private
# private/ 已被 .gitignore 忽略，通过 flake.nix 的 private 输入（path:）引入构建。
{ ... }:

{
  # 仅在首次创建用户时生效；生成：mkpasswd -m sha-512
  users.users.xkeyc.initialHashedPassword = "<sha-512 crypt 哈希>";

  home-manager.sharedModules = [
    { programs.git.settings.user.email = "<git 提交邮箱>"; }
  ];

  # 磁盘 UUID（`lsblk -f` 查看）。挂载点、文件系统类型与选项见
  # hardware-configuration.nix、nixos/storage.nix；根分区的五个 btrfs 子卷在同一块盘上。
  fileSystems = let uuid = id: "/dev/disk/by-uuid/${id}"; root = uuid "<btrfs 根分区 UUID>"; in {
    "/".device = root;
    "/home".device = root;
    "/nix".device = root;
    "/var/log".device = root;
    "/.snapshots".device = root;
    "/boot".device = uuid "<EFI 分区 UUID>";
    "/mnt/data".device = uuid "<NTFS 数据盘 UUID>";
    "/mnt/application".device = uuid "<NTFS 应用盘 UUID>";
  };
}
