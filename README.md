# ai-max-395

Ryzen AI MAX+ 395（Radeon 8060S）无头服务器的 NixOS 配置。这是 `xkeyC/Nix` 仓库的独立分支（orphan），
与 `main` 分支（桌面 xkeyc-nixos）不共享模块。

## 硬件

- CPU/GPU：AMD Ryzen AI MAX+ 395 w/ Radeon 8060S（Strix Halo，gfx1151）
- 磁盘：ZHITAI TiPlus7100s 2TB
- 网络：2× RTL8125 2.5GbE、MT7925 Wi-Fi 7

## 磁盘布局

| 分区 | 卷标 | 内容 |
| --- | --- | --- |
| nvme0n1p1 1G | `NIXBOOT` | EFI，挂载在 `/boot`（systemd-boot） |
| nvme0n1p2 其余 | `nixos` | btrfs，子卷 `@` `@home` `@nix` `@log` `@snapshots`，`compress=zstd:1,noatime` |

## 部署

在主力机上（本分支检出为 worktree：`git -C ~/Nix worktree add ~/Nix-ai-max-395 ai-max-395`）：

```sh
cd ~/Nix-ai-max-395
nixos-rebuild switch --flake .#ai-max-395 --target-host root@ai-max-395.local
```

## 不在仓库里的东西

- `xkeyc` 用户密码：安装时直接写进目标机 `/etc/shadow`（`mutableUsers` 默认开启）。
- Wi-Fi 连接：安装时从 live 系统拷贝 `/etc/NetworkManager/system-connections/*.nmconnection`。
