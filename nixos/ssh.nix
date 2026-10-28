{ config, ... }:

{
  services.openssh.enable = true;
  services.openssh.settings = {
    PermitRootLogin = "prohibit-password";
    PasswordAuthentication = true;
    KbdInteractiveAuthentication = false;
  };

  # 客户端：私钥口令存进 KDE 钱包，登录桌面后自动解锁私钥，ssh 不再问口令。
  #   * ssh-agent 作为用户级服务常驻（$XDG_RUNTIME_DIR/ssh-agent，shell 里自动设 SSH_AUTH_SOCK）。
  #   * ssh-add-kwallet：图形会话启动时跑一次 ssh-add，口令由 ksshaskpass 从钱包读取。
  #     第一次会弹窗要口令，勾上「记住密码」就存进 kdewallet；之后每次登录静默加载。
  #     自动登录不会解锁钱包，所以登录后可能先弹钱包密码框（见 uu-remote.nix）。
  #   * AddKeysToAgent：万一开机时没加载成功，在终端里输一次口令后也会留在 agent 里直到注销。
  programs.ssh.startAgent = true;
  programs.ssh.extraConfig = ''
    AddKeysToAgent yes
  '';

  systemd.user.services.ssh-add-kwallet = {
    description = "Load SSH keys into ssh-agent (passphrase from KWallet)";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    requires = [ "ssh-agent.service" ];
    after = [ "graphical-session.target" "ssh-agent.service" ];
    environment = {
      SSH_AUTH_SOCK = "%t/ssh-agent";
      SSH_ASKPASS = config.programs.ssh.askPassword; # Plasma 6 默认就是 ksshaskpass
      SSH_ASKPASS_REQUIRE = "force";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${config.programs.ssh.package}/bin/ssh-add %h/.ssh/id_rsa";
    };
  };
}
