# 常驻挂载的 NTFS 数据盘，归主桌面用户所有。device（磁盘 UUID）在 private/default.nix。
#
# 用 Linux 7.1 起内核自带的新 ntfs 驱动（Namjae Jeon，原 NTFSPlus），不用 ntfs3：
# 2026-10 在 ntfs3 下这两块盘反复出现 MFT / $Bitmap / 属性列表损坏，丢失过一个 2.9 GB 的 QQ 数据库。
# errors=remount-ro：驱动发现元数据错误时把盘重新挂载为只读，防止在损坏的结构上继续写入。
# 修盘用 ntfsprogs-plus 的 fsck.ntfs（先 -n 只读检查），或者 Windows 的 chkdsk /f。
{ pkgs, ... }:

let
  options = [ "uid=1000" "gid=100" "umask=022" "errors=remount-ro" "nofail" ];
in
{
  # noCheck：安装 fsck.ntfs 之后，systemd 会在每次开机时自动检查（并修复）这两块盘；
  # 1.0 版的工具还不够可靠，不让它在开机时自动修改，修盘一律手动进行。
  fileSystems."/mnt/data" = {
    fsType = "ntfs";
    inherit options;
    noCheck = true;
  };
  fileSystems."/mnt/application" = {
    fsType = "ntfs";
    inherit options;
    noCheck = true;
  };

  # 数据盘挂载前确保内核 ntfs 驱动已加载。
  boot.kernelModules = [ "ntfs" ];

  # 7.3 的 ntfs 驱动把稀疏文件的后续段（扩展 MFT 记录里 lowest_vcn ≠ 0 的 $DATA）误判为损坏：
  # 只有第一段带有 compressed_size 字段，校验却要求每一段都有。Steam、网盘下载器在 Windows 下
  # 创建的都是稀疏文件，读取碎片多的大文件时会报 “Corrupt 0x80 attribute”，并把整块盘重新挂载为只读。
  # 上游在 7.3 之后用 8deea344965f 修复了这个问题，这里是移植到 7.3 的版本；内核包含这个修复后删掉这个补丁。
  boot.kernelPatches = [
    {
      name = "ntfs-sparse-continuation-extent";
      patch = ./packages/ntfs-sparse-continuation-extent.patch;
    }
  ];

  environment.systemPackages = [ pkgs.ntfsprogs-plus ];
}
