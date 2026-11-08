# Strata：本地 LLM 推理服务（OpenAI / Anthropic 兼容 API）。
#
# 打包见 packages/strata.nix。数据目录在 private/default.nix 里设置（local.strata.dataDir）。
# 数据目录里放可写数据：
#   components/  engine 组件（`strata update --no-control` 下载，约 0.6 GB）
#   install/     模型的 run config（strata-<model>.json），由 components/ 的位置推出
#   models/      模型文件、预处理 pack、draft layer
#   api-key      strata-switch 使用的 API 密钥
# profile、preset、settings.json 在 ~/.config/strata，运行状态和日志在 ~/.local/state/strata。
#
# 对局域网公开：监听 0.0.0.0:41873（只有 IPv4，本机有公网 IPv6，不监听 v6），防火墙只放行内网网段。
# 客户端：http://<本机局域网 IP>:41873/v1（OpenAI）或 http://<本机局域网 IP>:41873（Anthropic），
# 密钥放在 Authorization: Bearer <key> 或 x-api-key 里。
#
# 通过 strata-switch 选择并启动模型，用 strata launch --stop 停止。
{ config, lib, pkgs, ... }:

let
  cfg = config.local.strata;
  strata = pkgs.callPackage ./packages/strata.nix { componentsDir = "${cfg.dataDir}/components"; };
  port = 41873;
in
{
  options.local.strata = {
    dataDir = lib.mkOption {
      type = lib.types.str;
      description = "Strata 的可写数据目录（engine 组件、run config、模型、API 密钥）。";
    };
    profile = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "兼容旧配置；strata-switch 不使用此选项。";
    };
  };

  config = {
    environment.systemPackages = [ strata (pkgs.writeShellScriptBin "strata-switch" (builtins.readFile ../../scripts/strata-switch)) ];

    # 只放行内网 IPv4 网段（服务本身也不监听 IPv6）。
    networking.firewall.extraCommands = ''
      for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
        iptables -A nixos-fw -p tcp --dport ${toString port} -s $net -j nixos-fw-accept
      done
    '';
  };
}
