# 用户账户。初始密码哈希属于隐私内容，放在 private/default.nix（不进 git）。
{ ... }:

{
  users.users.xkeyc = {
    isNormalUser = true;
    description = "xkeyc";
    extraGroups = [ "wheel" "networkmanager" "docker" ];
  };
}
