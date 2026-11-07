# 编译缓存：内核用 ccacheStdenv 编译（见 configuration.nix 的 boot.kernelPackages）。
# 内核带着 packages/ntfs/ 的补丁，没有二进制缓存，只能本地编；改一个补丁只会让 fs/ntfs 等少数
# 文件的缓存失效，其余目标文件直接从 ccache 取。
#
# 缓存目录不存在或不可写时（第一次 switch 之前，或目录被删掉），包装器不报错，直接退回普通编译；
# nixpkgs 自带的 programs.ccache.packageNames 包装器会在这种情况下让构建失败。
# 查看命中率：nix-ccache --show-stats
{ config, ... }:

let
  cacheDir = config.programs.ccache.cacheDir;
in
{
  # 创建 /var/cache/ccache（root:nixbld 0770），并提供 nix-ccache 命令。
  programs.ccache.enable = true;

  # 构建沙箱里要能访问缓存目录；结尾的 ? 表示目录不存在时忽略。
  nix.settings.extra-sandbox-paths = [ "${cacheDir}?" ];

  nixpkgs.overlays = [
    (final: prev: {
      ccacheWrapper = prev.ccacheWrapper.override {
        extraConfig = ''
          export CCACHE_COMPRESS=1
          export CCACHE_SLOPPINESS=random_seed
          export CCACHE_DIR="${cacheDir}"
          export CCACHE_UMASK=007
          if [ ! -d "$CCACHE_DIR" ] || [ ! -w "$CCACHE_DIR" ]; then
            export CCACHE_DISABLE=1
          fi
        '';
      };
    })
  ];
}
