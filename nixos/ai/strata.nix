# Strata：本地 LLM 推理服务（OpenAI / Anthropic 兼容 API）。
#
# 打包见 packages/strata.nix。数据目录和加载的模型（profile）在 private/default.nix 里设置
# （local.strata.dataDir / local.strata.profile）。数据目录里放可写数据：
#   components/  engine 组件（`strata update --no-control` 下载，约 0.6 GB）
#   install/     模型的 run config（strata-<model>.json），由 components/ 的位置推出
#   models/      模型文件、预处理 pack、draft layer
#   api-key      API 密钥（首次启动时随机生成；删掉后下次启动会换一个新的）
# profile、preset、settings.json 在 ~/.config/strata，运行状态和日志在 ~/.local/state/strata。
#
# 对局域网公开：监听 0.0.0.0:41873（只有 IPv4，本机有公网 IPv6，不监听 v6），防火墙只放行内网网段。
# 客户端：http://<本机局域网 IP>:41873/v1（OpenAI）或 http://<本机局域网 IP>:41873（Anthropic），
# 密钥放在 Authorization: Bearer <key> 或 x-api-key 里。
#
# strata.service 是用户级服务，不自启（没有 wantedBy），需要时手动：
#   systemctl --user start strata      # 载入模型要几分钟：journalctl --user -u strata -f
#   systemctl --user stop strata
#
# 首次使用 / 换模型：先用 `strata launch --save-preset <名字>` 生成 profile（launch-<名字>），
# 顺带下载 engine、写 run config，然后 `strata launch --stop`，把 local.strata.profile 设成它，
# 之后交给 systemd。具体命令见 private/default.nix。
{ config, lib, pkgs, ... }:

let
  cfg = config.local.strata;
  strata = pkgs.callPackage ./packages/strata.nix { componentsDir = "${cfg.dataDir}/components"; };
  port = 41873;
  keyFile = "${cfg.dataDir}/api-key";

  # 密钥经 STRATA_API_KEY 传入，不出现在命令行（ps 可见）里。
  start = pkgs.writeShellScript "strata-start" ''
    if [ ! -s ${keyFile} ]; then
      key=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 48)
      printf '%s\n' "$key" > ${keyFile}
    fi
    STRATA_API_KEY=$(head -n 1 ${keyFile})
    export STRATA_API_KEY
    exec ${strata}/bin/strata serve --profile ${cfg.profile} --host 0.0.0.0 --port ${toString port}
  '';
in
{
  options.local.strata = {
    dataDir = lib.mkOption {
      type = lib.types.str;
      description = "Strata 的可写数据目录（engine 组件、run config、模型、API 密钥）。";
    };
    profile = lib.mkOption {
      type = lib.types.str;
      description = "strata.service 启动的 profile（`strata launch --save-preset <名字>` 生成的 launch-<名字>）。";
    };
  };

  config = {
    environment.systemPackages = [ strata ];

    systemd.user.services.strata = {
      description = "Strata local LLM server";
      unitConfig.RequiresMountsFor = cfg.dataDir;
      # engine 检测显卡要用 nvidia-smi。
      path = [ "/run/current-system/sw" ];
      serviceConfig = {
        ExecStart = start;
        # SIGTERM 走和 Ctrl+C 相同的退出流程：先让 engine 收尾再退出。
        TimeoutStopSec = 120;
        Restart = "on-failure";
        RestartSec = 10;
      };
    };

    # 只放行内网 IPv4 网段（服务本身也不监听 IPv6）。
    networking.firewall.extraCommands = ''
      for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
        iptables -A nixos-fw -p tcp --dport ${toString port} -s $net -j nixos-fw-accept
      done
    '';
  };
}
