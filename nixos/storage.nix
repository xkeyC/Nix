# 常驻挂载的 NTFS 数据盘，归主桌面用户所有。device（磁盘 UUID）在 private/default.nix。
#
# 用 Linux 7.1 起内核自带的新 ntfs 驱动（Namjae Jeon，原 NTFSPlus），不用 ntfs3：
# 2026-10 在 ntfs3 下这两块盘反复出现 MFT / $Bitmap / 属性列表损坏，丢过一个 2.9 GB 的 QQ 数据库。
# errors=remount-ro：驱动发现元数据错误就转只读，别在坏的结构上接着写。
# 修盘用 ntfsprogs-plus 的 fsck.ntfs（先 -n 只读检查），或者 Windows 的 chkdsk /f。
{ pkgs, ... }:

let
  options = [ "uid=1000" "gid=100" "umask=022" "errors=remount-ro" "nofail" ];
in
{
  # noCheck：装了 fsck.ntfs 之后 systemd 会在每次开机时自动检查（并修复）这两块盘；
  # 1.0 版的工具不放心让它开机时自动改，修盘一律手动。
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

  environment.systemPackages = [ pkgs.ntfsprogs-plus ];
}
