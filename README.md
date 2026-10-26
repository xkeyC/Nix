# xkeyc 的 NixOS 配置

单机 NixOS flake：AMD CPU + NVIDIA 显卡，KDE Plasma 6（Wayland），Home Manager 管理用户环境。
nixpkgs 跟随 unstable，锁定在 `flake.lock` 的提交上。

## 目录结构

```
flake.nix                 # 入口：nixosConfigurations.xkeyc-nixos 与全部输入
configuration.nix         # nixos-generate-config 生成的模板，只负责引入下面两项
hardware-configuration.nix
nixos/
  default.nix             # 各模块的引入清单
  system.nix  users.nix  ssh.nix  nix-settings.nix  storage.nix
  nvidia.nix  desktop.nix  input-method.nix  dns.nix  power-management.nix
  home-manager.nix  dev-toolchains.nix  gaming.nix
  chaos-hdr.nix  dlss5vklayer.nix  flclash-tun.nix  uu-remote.nix
  packages/               # 自己打包的软件与补丁
  vr/                     # VR 相关（各工具一个文件，自己打包的在 vr/packages/）
home/xkeyc.nix            # Home Manager 用户配置
private.example/          # 隐私配置模板（真实的 private/ 不进 git）
```

每个 `.nix` 文件开头都有注释，写明用途、用法和已知问题；下文只做概览。

## 系统组成

| 模块 | 内容 |
|---|---|
| `system.nix` | systemd-boot（保留 4 代）、主机名、NetworkManager、时区与 `zh_CN.UTF-8`、固件与微码 |
| `nix-settings.nix` | `allowUnfree`；上交 / 清华 / 中科大镜像，外加 CUDA 二进制缓存 |
| `nvidia.nix` | NVIDIA open 内核模块（`new_feature` 分支，修正 nvidia-smi 等的 ELF 段问题）、Docker + NVIDIA 容器工具链（CDI）、CUDA 13 |
| `desktop.nix` | Plasma 6 + plasma-login-manager、XWayland、Noto 字体 |
| `input-method.nix` | Fcitx5 + RIME 雾凇拼音，由 KWin 以 Wayland 输入法方式启动 |
| `storage.nix` | 两块 NTFS 数据盘（`/mnt/data`、`/mnt/application`，ntfs3 驱动） |
| `power-management.nix` | 禁用睡眠/休眠，空闲 10 分钟只关屏 |
| `dns.nix` | DNSPod / AliDNS / Cloudflare |
| `ssh.nix` | OpenSSH（root 只允许密钥登录） |
| `gaming.nix` | Steam + DW-Proton |
| `dev-toolchains.nix` | gh、rustup、Python/uv、Node/pnpm/yarn、Flutter、Go、C/C++、.NET，以及 nix-ld；git 配置 |
| `home-manager.nix` | 用户软件：QQ、FlClash、Claude Code、Codex |
| `vr/` | SteamVR + ALVR、Monado、WiVRn、VIVE Hub |

## 自己打包的软件

nixpkgs 里没有、或现有版本不能用的软件，打包放在 `nixos/packages/` 和 `nixos/vr/packages/`：

| 软件 | 版本 | 上游 | 说明 |
|---|---|---|---|
| [uu-remote-linux](nixos/packages/uu-remote-linux.nix) | 0.2.32（`ab5d0a6`） | [VallierDev/uu-remote-linux](https://github.com/VallierDev/uu-remote-linux) | 非官方网易 UU 远程被控端 + 控制端，源码构建（`wayland,portal`）。补丁新增 `UU_PORTAL_MONITOR`，让 KDE 下只共享一块显示器。开机自动登录后立即锁屏，远程用客户端的「自动解锁被控端」进入桌面 |
| [Chaos HDR](nixos/packages/chaos-hdr.nix) | 0.4.3 | [chaosfox26/chaos-hdr](https://github.com/chaosfox26/chaos-hdr) | NVIDIA TrueHDR（SDR→HDR）KWin 特效，Alt+Z 打开控制面板 |
| [DLSS5VKLayer](nixos/packages/dlss5vklayer.nix) | 0.3.1-2 | [bmitch87/DLSS5VKLayer](https://github.com/bmitch87/DLSS5VKLayer) | DLSS 5 Neural Rendering 的 Vulkan 层 + Wine helper（预编译包） |
| [FlClash](nixos/packages/flclash.nix) | 0.9.2 | [chen08209/FlClash](https://github.com/chen08209/FlClash) | Clash Meta 客户端（官方 .deb），TUN 模式 helper 见 `flclash-tun.nix` |
| [ALVR](nixos/vr/packages/alvr/package.nix) | 21.0.0-dev（`adaa16b`） | [alvr-org/ALVR](https://github.com/alvr-org/ALVR) | master 版：20.14.1 不兼容 SteamVR 2.16+；附带 direct-mode 帧同步等补丁 |
| [VIVE Hub](nixos/vr/packages/vivehub.nix) | 1.0.3 | [ViveRoboticsSoftware/vivehub-linux](https://github.com/ViveRoboticsSoftware/vivehub-linux) | VIVE Ultimate Tracker 配对/建图（闭源预编译包，FHS 环境运行） |

以下几项不是自己打包，而是作为 flake 输入引入，以源码目录方式 import（`flake = false`）：

| 输入 | 用途 |
|---|---|
| `home-manager` | Home Manager 的 NixOS 模块 |
| `dsh-nix` | [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）的 Nix 打包与 Home Manager 模块；`home/xkeyc.nix` 里覆盖了它的 pnpm 依赖哈希 |
| `deepseek-harness` | dsh 源码，与 dsh-nix 自身锁定的提交相同 |

## 日常维护

### 应用配置

```sh
sudo nixos-rebuild switch          # /etc/nixos/flake.nix 软链到本仓库
# 或显式指定：
sudo nixos-rebuild switch --flake ~/Nix#xkeyc-nixos
```

本仓库是 git flake，**构建只看得到 git 跟踪的文件**。新建的 `.nix` 文件要先 `git add`
（不必提交），否则会报 `path ... does not exist`。

只想检查、不切换：

```sh
nixos-rebuild build --flake .#xkeyc-nixos
nix store diff-closures /run/current-system ./result   # 看版本变化
```

### 隐私配置（private/）

初始密码哈希、git 邮箱等放在 `private/default.nix`，该目录被 `.gitignore` 忽略，
通过 `flake.nix` 中的 `private` 输入（`path:/home/xkeyc/Nix/private`）引入。

- **修改 `private/` 后必须执行** `nix flake update private`，否则构建会报 NAR 哈希不匹配。
- 新机器上：`cp -r private.example private`，填入真实值，再执行 `nix flake update private`。
  密码哈希用 `mkpasswd -m sha-512` 生成；它只在首次创建用户时生效。

### 升级

```sh
nix flake update nixpkgs           # 只升级 nixpkgs
nix flake update                   # 升级全部输入（private 也会重新读取）
```

`nixpkgs`、`home-manager`、`dsh-nix`、`deepseek-harness` 的 url 里都写死了提交号，
`nix flake update <名字>` 只会刷新同一提交的元数据。要升级，先改 url 里的提交号
（或去掉提交号改为跟随分支），再执行 `nix flake update <名字>`。

- **home-manager**：与 nixpkgs 同步升级，避免模块选项不匹配。
- **dsh-nix / deepseek-harness**：两者一起升级，`deepseek-harness` 应与 dsh-nix 的
  `flake.nix` 中锁定的提交一致。pnpm 依赖哈希变化时，构建会报出新哈希，把它填进
  `home/xkeyc.nix` 的 `outputHash`。
- **自己打包的软件**：改 `version`/`rev`，把 `hash`（以及 Rust 包的 `cargoHash`）先置为
  `lib.fakeHash`，构建一次后从报错里拿到正确值。
  - uu-remote-linux 的 `Cargo.lock` 是上游副本（`uu-remote-linux.Cargo.lock`），升级时一并替换；
    补丁 `uu-remote-linux-portal-monitor.patch` 如果打不上，需要对照上游的 `c_engine/portal_engine.c`
    和 `src/input.rs` 重新生成。
  - ALVR 升级步骤见 `vr/packages/alvr/package.nix` 开头的注释。

### 缓存与垃圾回收

flake 输入（`github:` tarball）下载一次后缓存在 store 和 `~/.cache/nix`，提交号不变就不会重新下载。

dsh 的 npm 依赖（`deepseek-harness-pnpm-deps`）只在构建时使用，`nix-collect-garbage`
会把它删掉；之后只要 dsh 需要重建，就要重新下载全部 npm 包。`home/xkeyc.nix` 中的
`dshSrc` 特意保留原目录名 `deepseek-harness`，内容不变时 store 路径不变，可以避免无谓的重建。

```sh
sudo nix-collect-garbage --delete-older-than 14d
```

## 备注

- **UU 远程与 KDE 钱包**：开机自动登录不输入密码，`pam_kwallet` 不会解锁 KDE 钱包；
  gh 令牌存在钱包里，开机后首次使用 `git push`/`gh` 时会弹出钱包密码框。
- **UU 远程多显示器**：`nixos/uu-remote.nix` 里的 `UU_PORTAL_MONITOR` 是显示器序号，
  对应日志 `journalctl --user -u uuremote-native | grep 'Portal monitor stream'`。
