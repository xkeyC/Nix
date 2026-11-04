# 常驻挂载的 NTFS 数据盘，归主桌面用户所有。device（磁盘 UUID）在 private/default.nix。
#
# 用 Linux 7.1 起内核自带的新 ntfs 驱动（Namjae Jeon，原 NTFSPlus），不用 ntfs3：
# 2026-10 在 ntfs3 下这两块盘反复出现 MFT / $Bitmap / 属性列表损坏，丢失过一个 2.9 GB 的 QQ 数据库。
# errors=remount-ro：驱动发现元数据错误时把盘重新挂载为只读，防止在损坏的结构上继续写入。
# 修盘用 ntfsprogs-plus 的 fsck.ntfs（先 -n 只读检查），或者 Windows 的 chkdsk /f。
{ pkgs, lib, ... }:

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

  # ntfs 驱动的补丁：packages/ntfs/ 下的 *.patch 按文件名顺序应用。每个补丁的来源、
  # 为什么要带、什么时候删，见 packages/ntfs/README.md。
  boot.kernelPatches = map (file: {
    name = "ntfs-" + lib.removeSuffix ".patch" file;
    patch = ./packages/ntfs + "/${file}";
  }) (lib.filter (lib.hasSuffix ".patch") (lib.attrNames (builtins.readDir ./packages/ntfs)));

  environment.systemPackages = [ pkgs.ntfsprogs-plus ];
}
