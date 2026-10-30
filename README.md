# xkeyc 的 NixOS 配置

一台台式机的完整 NixOS 配置，以 flake 形式管理。机器是 AMD CPU 加 NVIDIA 显卡，带两块 NTFS 数据盘。
桌面用 KDE Plasma 6（Wayland）和中文环境，输入法是 Fcitx5 + 雾凇拼音，用户环境由 Home Manager 管理。
软件源是 nixpkgs unstable，固定在 `flake.lock` 记录的提交上，不会自行变化。

## 目录结构

```
flake.nix                 入口，定义系统 xkeyc-nixos 和所有外部依赖（输入）
configuration.nix         安装时生成的模板，只负责引入下面两项
hardware-configuration.nix  分区挂载与内核模块（安装时自动生成，磁盘 UUID 已移到 private/）
nixos/
  default.nix             模块清单：想知道启用了什么，先看这里
  *.nix                   按主题划分的系统模块，见下表
  packages/               自己打包的软件和补丁
  ai/                     本地 AI 服务（Strata），自己的打包在 ai/packages/
home/xkeyc.nix            用户 xkeyc 的 Home Manager 配置
archive/vr/               已存档的 VR 配置（SteamVR + ALVR、Monado、WiVRn、VIVE Hub、PaperTracker），不参与构建
private.example/          隐私配置的模板（真正的 private/ 不进 git）
```

每个 `.nix` 文件开头都有注释，写明用途、用法和已知问题。本文只做概览。

## 系统组成

| 模块 | 作用 |
|---|---|
| `system.nix` | 引导（systemd-boot，保留最近 4 个版本）、主机名、网络、时区、语言、CPU 微码 |
| `nix-settings.nix` | 允许安装非自由软件；国内镜像（上交、清华、中科大）和 CUDA 二进制缓存 |
| `users.nix` | 用户 xkeyc |
| `shell.nix` | 登录 shell 用 zsh + oh-my-zsh（自动建议、语法高亮）；Claude Code 通过 `CLAUDE_CODE_SHELL` 仍用 bash |
| `ssh.nix` | SSH 服务；root 只能用密钥登录 |
| `nvidia.nix` | NVIDIA 驱动（开源内核模块）、Docker 的 GPU 支持、CUDA 13；修复了 `nvidia-smi` 启动即崩溃的问题 |
| `gpu-unlock.nix` | RTX 4090 实验性 Tensor Core 解锁，默认启用；提供不解锁启动项 |
| `desktop.nix` | KDE Plasma 6、登录界面、XWayland、Noto 字体、音频（采样率自适应、主板光纤输出修正、RTKit 实时优先级） |
| `input-method.nix` | Fcitx5 + RIME 雾凇拼音，作为 Wayland 输入法由 KWin 启动 |
| `storage.nix` | 挂载 NTFS 数据盘 `/mnt/data` 和 `/mnt/application`（内核 7.1 起的新 ntfs 驱动，出错时重新挂载为只读） |
| `power-management.nix` | 关闭睡眠和休眠；空闲 10 分钟只关显示器 |
| `dns.nix` | DNS：DNSPod、阿里、Cloudflare |
| `gaming.nix` | Steam、DW-Proton 兼容层、ntsync |
| `dev-toolchains.nix` | 开发工具：gh、Rust、Python、Node、Flutter、Go、C/C++、.NET；git 设置；nix-ld（让下载来的通用 Linux 程序能直接运行） |
| `home-manager.nix` | 用户软件：QQ（`/mnt/data` 没挂载时不启动）、FlClash、Claude Code、Codex |
| `uu-remote.nix` | UU 远程被控端，以及开机自动登录 |
| `chaos-hdr.nix` | 把 SDR 游戏画面转成 HDR 的 KWin 特效（RTX HDR，着色器引擎作备用） |
| `dlss5vklayer.nix` | DLSS 5 Neural Rendering 的游戏插件 |
| `desktop-gpu.nix` | 桌面临时改用核显渲染，显示器仍接在 4090 上（`desktop-gpu igpu`，重新登录生效） |
| `browser-hdr-video.nix` | Brave 播放 HDR 视频：给 KWin 打补丁，不再截掉 Chromium 的 HDR 高光；Brave 开 NVIDIA VA-API 硬解（B 站 HEVC / HDR） |
| `flclash-tun.nix` | FlClash 代理 TUN 模式需要的特权服务 |
| `ai/strata.nix` | Strata 本地大模型服务（OpenAI / Anthropic 兼容 API），局域网可访问，需要手动启动 |

## RTX 4090 解锁启动项

`nixos/gpu-unlock.nix` 固定了 gpu-unlock-ada 源码及固件输入，使用当前内核编译模块，并在 initrd 的 NVIDIA 驱动加载前运行。默认启动项启用解锁，`no-gpu-unlock` 启动项不启用。构建并安装启动项：

```bash
sudo nixos-rebuild boot --flake /home/xkeyc/Nix#xkeyc-nixos
```

首次测试应完整关机后开机，默认启动项会尝试解锁。要恢复原始状态，完整关机后开机并在 systemd-boot 菜单选择 `no-gpu-unlock` 启动项。屏幕可能在解锁和驱动交接时短暂变黑；如果异常，选择 `no-gpu-unlock` 启动项。

启动后检查：

```bash
journalctl -k -b | grep -i gpu_unlock
nvidia-smi
```

目标 `0000:01:00.0` 应出现 `gpu_unlock: unlocked`；还应使用同一工作负载对比解锁前后性能和结果。若日志提示固件未停止且保留 DMA 缓冲区，关机后再试，不要强制卸载模块。此路径为实验性，内核更新后需要重新构建和验证。

## 自己打包的软件

nixpkgs 里没有，或者 nixpkgs 的版本不能用的软件，在本仓库里自己打包：

| 软件 | 版本 | 用途 | 为什么自己打包 |
|---|---|---|---|
| [uu-remote-linux](https://github.com/VallierDev/uu-remote-linux) | 0.2.32 | 用官方 UU 远程客户端控制这台电脑（非官方被控端），附带一个 Linux 控制端 | nixpkgs 没有。另加了一个补丁，让 KDE 下只共享一块显示器 |
| [Chaos HDR](https://github.com/xkeyC/chaos-hdr) | 0.5.0（fork） | 用 NVIDIA TrueHDR 把 SDR 游戏转成 HDR，失败时换用着色器引擎，Alt+Z 打开控制面板 | nixpkgs 没有；上游只提供 Arch 安装脚本。fork 增加了备用引擎和更多画面选项 |
| [DLSS5VKLayer](https://github.com/bmitch87/DLSS5VKLayer) | 0.3.2-1 | 在 Linux 游戏里使用 DLSS 5 Neural Rendering | nixpkgs 没有 |
| [FlClash](https://github.com/chen08209/FlClash) | 0.9.2 | Clash Meta 代理客户端 | nixpkgs 没有 |
| [Strata](https://github.com/Niko1221/Strata) | 0.2.7（control 0.1.52） | 在本机运行大模型，提供 OpenAI / Anthropic 兼容 API | nixpkgs 没有；上游只提供安装脚本 |
| [ALVR](https://github.com/alvr-org/ALVR) | 21.0.0-dev | 把 SteamVR 画面无线串流到 VR 一体机（已存档） | nixpkgs 的 20.14.1 和新版 SteamVR 不兼容，这里用开发版并加了补丁 |
| [VIVE Hub](https://github.com/ViveRoboticsSoftware/vivehub-linux) | 1.0.3 | VIVE Ultimate Tracker 的配对和建图工具（已存档） | nixpkgs 没有；上游只有闭源预编译包 |

打包文件在 `nixos/packages/` 和 `nixos/ai/packages/`；已存档的 VR 软件在 `archive/vr/packages/`，不参与构建，恢复方法见 `archive/vr/default.nix` 开头。

另外有四份外部源码直接从 GitHub 引用（定义在 `flake.nix`，锁定到固定提交）：

| 名字 | 是什么 |
|---|---|
| `home-manager` | Home Manager 本身 |
| `dsh-nix` | [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（命令 `dsh`）的 Nix 打包 |
| `deepseek-harness` | DeepSeek Harness 的源码，供 `dsh-nix` 构建 |
| `chaos-hdr` | [Chaos HDR fork](https://github.com/xkeyC/chaos-hdr) 的源码、打包和 NixOS 模块 |

## 日常维护

### 应用配置改动

```sh
sudo nixos-rebuild switch
```

`/etc/nixos/flake.nix` 是指向本仓库的软链接，所以不用写路径。也可以显式指定：
`sudo nixos-rebuild switch --flake ~/Nix#xkeyc-nixos`。

只想先试着构建、不切换系统：

```sh
nixos-rebuild build --flake .#xkeyc-nixos
nix store diff-closures /run/current-system ./result   # 列出将要变化的软件版本
```

> **新建文件要先 `git add`。** 本仓库是 git 仓库，构建时 Nix 只能看到 git 跟踪的文件。
> 新建的 `.nix` 文件不 `git add`（不需要提交）就会报 `path ... does not exist`。

### 隐私配置（private/）

不想公开的内容（用户初始密码的哈希、git 邮箱、磁盘 UUID、Strata 的数据目录和加载的模型）放在 `private/default.nix`。
这个目录不进 git，构建时通过 `flake.nix` 里的 `private` 输入单独读取。

- **改完 `private/` 一定要执行 `nix flake update private`**，否则构建会报哈希不匹配。
  这是因为 Nix 把它当作外部依赖，`flake.lock` 里记录了它的哈希。
- 在新机器上：`cp -r private.example private`，按注释填入真实值，再执行 `nix flake update private`。
  密码哈希用 `mkpasswd -m sha-512` 生成；它只在第一次创建用户时生效，之后改密码用 `passwd`。
  磁盘 UUID 用 `lsblk -f` 查看。
- 如果重新运行 `nixos-generate-config` 生成 `hardware-configuration.nix`，新文件里会带回
  `device = "/dev/disk/by-uuid/..."`：把这些行删掉，UUID 改填到 `private/default.nix`。

### 升级软件

```sh
nix flake update nixpkgs     # 升级系统软件
sudo nixos-rebuild switch
```

`flake.nix` 里的外部源码都在 url 中写死了提交号，`nix flake update` 不会让它们变化。
要升级时，先把 url 里的提交号改成新的，再执行 `nix flake update <名字>`。

升级 nixpkgs 时要同时升级 home-manager，否则可能出现选项不匹配的报错。

dsh-nix 更新较慢，`deepseek-harness` 可以单独锁定到上游更新的发布 tag（`dsh-v*`）。这时要同步修改
`home/xkeyc.nix` 里覆盖的 `version`，并把 `outputHash` 改成 `lib.fakeHash` 构建一次，从报错里复制新哈希填回去。
如果新版修改了构建或安装步骤（例如删掉了某个入口），也在那里用 `overrideAttrs` 覆盖。

自己打包的软件，修改 `version` 或 `rev`，把 `hash`（Rust 软件还有 `cargoHash`）改成 `lib.fakeHash`，
构建一次，再从报错里复制正确的哈希填回去。uu-remote-linux 还要用上游新的 `Cargo.lock` 替换
`nixos/packages/uu-remote-linux.Cargo.lock`，如果补丁 `uu-remote-linux-portal-monitor.patch` 打不上，
需要按上游新代码重新制作。Strata 的哈希可以直接从 release 里的 `strata-feed.json` 获取。
ALVR（已存档）的步骤见 `archive/vr/packages/alvr/package.nix` 开头的注释。

### 清理磁盘

```sh
sudo nix-collect-garbage --delete-older-than 14d
```

清理后，外部源码（GitHub 上的提交）下次构建时可能要重新下载，但都不大。dsh 的 npm 依赖只在编译 dsh 时用到，
清理时会被删除，之后只要 dsh 需要重新编译，就要重新下载全部 npm 包，数量很大。为了尽量少重新编译，
`home/xkeyc.nix` 中的 `dshSrc` 给源码指定了固定的名字，不要删掉这一行。

## 注意事项

### 开机自动登录后，KDE 钱包需要手动解锁

为了让 UU 远程开机后就能连上，系统会自动登录 xkeyc，然后立刻锁屏（远程连上后，用客户端的
「自动解锁被控端」进入桌面）。

正常手动登录时，系统会用你输入的登录密码顺带解锁 KDE 钱包；自动登录不需要输入密码，
钱包就保持锁定。gh 的 GitHub 令牌存在钱包里，所以：

- 开机后第一次 `git push`、`git pull` 或使用 `gh` 时，会弹出 KDE 钱包窗口，输入登录密码即可。
  远程控制时这个窗口也会出现，在远程画面里输入就行。
- 不想每次输入，可以让 gh 把令牌存成文件：
  `gh auth logout && gh auth login -h github.com -p https -w --insecure-storage`。
  令牌会以明文写入 `~/.config/gh/hosts.yml`（只有你能读）。

### UU 远程锁屏时是黑屏、不能操作

这是程序有意为之：本机锁屏时，被控端不传画面，也不接受键盘鼠标。
在官方客户端里打开这台电脑的 **「自动解锁被控端」**，填入 xkeyc 的登录密码，
以后连上锁屏状态的电脑时，它会自动解锁。

### UU 远程只显示一块显示器

KDE 的远程桌面接口不提供选择屏幕的窗口，有多块显示器时，会把所有屏幕拼成一整张画面。
本配置给程序打了补丁，改为只共享其中一块，由 `nixos/uu-remote.nix` 中的
`UU_PORTAL_MONITOR` 指定（默认 `"0"`，一般是主显示器）。

换成另一块显示器：

1. 把 `UU_PORTAL_MONITOR` 改成 `"1"`，执行 `sudo nixos-rebuild switch`；
2. 执行 `systemctl --user restart uuremote-native`，重新连接。

不确定哪个序号对应哪块屏幕时，连接一次后运行
`journalctl --user -u uuremote-native | grep 'Portal monitor stream'`，
每行会列出一块屏幕的位置和尺寸，正在显示的那块标有 `(selected)`。
删掉 `UU_PORTAL_MONITOR` 这一行，就恢复为共享整个桌面。
