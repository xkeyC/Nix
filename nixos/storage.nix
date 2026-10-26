# 常驻挂载的 NTFS 数据盘，归主桌面用户所有。device（磁盘 UUID）在 private/default.nix。
{ ... }:

{
  fileSystems."/mnt/data" = {
    fsType = "ntfs3";
    options = [ "uid=1000" "gid=100" "umask=022" "nofail" ];
  };
  fileSystems."/mnt/application" = {
    fsType = "ntfs3";
    options = [ "uid=1000" "gid=100" "umask=022" "nofail" ];
  };

  # 数据盘挂载前确保内核 NTFS3 驱动已加载。
  boot.kernelModules = [ "ntfs3" ];
}
