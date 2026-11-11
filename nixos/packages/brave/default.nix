# Brave 浏览器：nixpkgs 2026-11-03 删除了 brave（无提交权限的维护者处理安全更新），
# 这里沿用 nixpkgs 原来的打包（pkgs/applications/networking/browsers/brave，删除前的 1d06008）自行维护，
# 只保留 Brave 本体，不带 Brave Origin。
#
# 升级：python3 nixos/packages/brave/update.py
#   从 versions.brave.com 取最新稳定版，按官方 .deb 的 .sha256 重写 brave.nix。
#   Brave 跟随 Chromium 发布安全更新，建议每次升级 nixpkgs 时一起执行。
{ callPackage }:

callPackage ((import ./make-brave.nix) (import ./brave.nix // {
  optStem = "brave";
  fileStem = "brave-browser";
  appIdStem = "com.brave.Browser";
  darwinStem = "Brave Browser";
  changelogFile = "CHANGELOG_DESKTOP.md";
  homepage = "https://brave.com/";
  innerBinary = "brave";
})) { }
