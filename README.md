# FluxEnv

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian%20%7C%20WSL-blue)
![Mode](https://img.shields.io/badge/Mode-Offline--first-brightgreen)

FluxEnv 是一个 Bash 驱动的 Ubuntu-like 主机初始化工具，用于快速配置 WSL、Ubuntu / Debian 宿主机、AutoDL 容器用户环境，以及 root-only 容器环境。

它会按 profile 执行系统包安装、apt 源配置、SSH 优化、用户创建或复用、zsh + Starship + 插件、Vim 配置、WSL 默认用户修正，以及系统级 `uv` 安装。

> 这些脚本会修改系统包、用户、sudo、SSH、hostname 和 shell 配置。请优先在 VM、容器或一次性服务器上验证后再用于真实机器。

## Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Profiles](#profiles)
- [Usage](#usage)
- [Configuration](#configuration)
- [Offline Resources](#offline-resources)
- [What Gets Changed](#what-gets-changed)
- [Proxy Notes](#proxy-notes)
- [Development](#development)
- [Project Layout](#project-layout)
- [Notes](#notes)

## Features

- Profile 驱动：内置 `normal`、`standard`、`autodl` 三种模式。
- 离线优先：安装时优先使用 `offline_resources/` 中的缓存资源。
- 系统级 `uv`：默认安装到 `/usr/local/bin`，root 和普通用户都可使用。
- Shell 体验：配置 zsh、Starship、`zsh-autosuggestions`、`zsh-syntax-highlighting`。
- Vim 配置：支持最小配置或离线完整配置资源。
- WSL 适配：`standard` profile 会检查并修正 `/etc/wsl.conf` 默认用户。
- apt 源控制：默认换到 TUNA 镜像，可通过配置或 CLI 跳过。
- Dry run：支持查看计划动作，降低首次运行风险。
- 交互终端完成后自动进入 zsh 登录 shell。

## Quick Start

```bash
git clone https://github.com/XjuSelab/FluxEnv.git
cd FluxEnv
```

准备离线资源：

```bash
./scripts/fetch_resources.sh
```

查看计划动作：

```bash
sudo ./scripts/fluxenv --profile normal --dry-run
```

运行宿主机初始化：

```bash
sudo ./scripts/fluxenv --profile normal
```

跳过默认 apt 换源：

```bash
sudo ./scripts/fluxenv --profile normal --no-apt-mirror
```

## Profiles

| Profile | 场景 | sudo 用户启动 | 纯 root 会话启动 |
| --- | --- | --- | --- |
| `normal` | Ubuntu / Debian 宿主机 | 复用当前 sudo 用户 | 创建目标用户，并同时配置 `/root` 的 shell/Vim 状态 |
| `standard` | WSL | 复用当前 sudo 用户，并修正 WSL 默认用户 | 创建目标用户 |
| `autodl` | AutoDL / 容器 | 复用当前 sudo 用户 | 配置 root 用户 |

默认 profile 是 `normal`。

## Usage

```text
Usage: scripts/fluxenv [options]

Options:
  --profile <name>       Built-in profile: standard, normal, autodl
  --config <path>        Optional .env config overrides
  --non-interactive      Disable prompts; require config values up front
  --dry-run              Print planned mutations without executing them
  --no-apt-mirror        Do not replace apt sources with the configured mirror
  --help                 Show this help
```

WSL 标准模式：

```bash
sudo ./scripts/fluxenv --profile standard
```

AutoDL / 容器模式：

```bash
sudo ./scripts/fluxenv --profile autodl
```

使用配置文件并关闭交互：

```bash
sudo ./scripts/fluxenv --profile normal --config ./config/example.env --non-interactive
```

## Configuration

配置覆盖文件是普通 `.env` 文件。可以从 `config/example.env` 开始：

```bash
cp config/example.env config/local.env
```

常用配置项：

```bash
HOST_NAME=myserver
USER_NAME=winbeau
USER_PASSWORD=change-me
ENABLE_VIM=1
ALLOW_ONLINE_FETCH=0
ENABLE_APT_MIRROR=1
APT_MIRROR_PRESET=tuna
APT_UBUNTU_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ubuntu
APT_UBUNTU_PORTS_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports
```

关键开关：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `ALLOW_ONLINE_FETCH` | `0` | 是否允许缺失离线资源时在线拉取 |
| `ENABLE_APT_MIRROR` | `1` | 是否在 `apt update` 前替换 apt 源 |
| `ENABLE_VIM` | profile 决定 | 是否配置 Vim，`ask` 表示交互确认 |
| `CHANGE_DEFAULT_SHELL` | `1` | 是否将目标用户默认 shell 改为 zsh |
| `INSTALL_VIM_PLUGINS` | profile 决定 | 是否执行 Vim 插件安装 |
| `UV_INSTALL_DIR` | `/usr/local/bin` | 系统级 `uv` 安装目录 |

## Offline Resources

FluxEnv 默认优先消费 `offline_resources/`，资源清单在 `config/resource-manifest.lock` 中维护。

```bash
./scripts/fetch_resources.sh
```

当前资源包含：

- Starship 安装脚本和 x86_64 离线二进制。
- `uv` 官方安装脚本缓存为 `offline_resources/uv-install.sh`。
- zsh 插件镜像：`zsh-autosuggestions`、`zsh-syntax-highlighting`。
- Vim 配置和 Vundle 镜像。
- 若干 legacy helper 上游脚本。

资源来源说明见 [docs/RESOURCE_SOURCES.md](docs/RESOURCE_SOURCES.md)。

## What Gets Changed

根据 profile 和配置，脚本可能会修改：

- `/etc/apt/sources.list` 和 `/etc/apt/sources.list.d/*`
- `/etc/ssh/sshd_config`
- `/etc/hostname` 和 `/etc/hosts`
- `/etc/sudoers.d/temp_install`
- `/etc/wsl.conf`
- `/usr/local/bin/starship`
- `/usr/local/bin/uv`
- 目标用户和 root 的 `.zshrc`、`.config/starship.toml`、`.zsh/plugins/`、`.vimrc`

apt 源备份写入 `/var/backups/fluxenv/apt/`，普通路径备份会追加时间戳后缀。

## Proxy Notes

如果在 WSL 或切换用户后访问 GitHub 很慢，建议直接为目标用户设置 Git 全局代理：

```bash
git config --global http.proxy http://127.0.0.1:xxxx
git config --global https.proxy http://127.0.0.1:xxxx
```

清空代理：

```bash
git config --global http.proxy ""
git config --global https.proxy ""
```

## Development

这个仓库没有编译步骤。提交前至少运行语法检查：

```bash
bash -n scripts/fluxenv lib/*.sh lib/steps/*.sh scripts/fetch_resources.sh
```

推荐 dry-run：

```bash
sudo ./scripts/fluxenv --profile normal --dry-run
sudo ./scripts/fluxenv --profile normal --dry-run --no-apt-mirror
```

真实验收建议在 `Ubuntu 24.04 x86_64` VM、容器或一次性服务器中执行，并确认：

- `uv --version` 可由 root 和目标用户执行。
- root 和目标用户均可进入 zsh。
- zsh 插件目录存在并可 source。
- Starship 配置和 Vim 配置写入目标路径。
- WSL 模式下 `/etc/wsl.conf` 默认用户符合预期。

## Project Layout

```text
.
├── config/             # profiles, example config, resource manifest
├── docs/               # resource source notes
├── lib/                # shared runtime and step implementations
│   └── steps/          # preflight, packages, uv, shell, Vim, finalize...
├── offline_resources/  # curated offline installers and mirrors
└── scripts/            # fluxenv entrypoint and resource fetcher
```

## Notes

- `standard` profile 仅支持 WSL；非 WSL 宿主机请使用 `normal`。
- `normal` 在纯 root 会话中会创建目标用户，并额外配置 `/root` 的 shell/Vim 用户状态。
- 在线抓取默认关闭；缺少离线资源时会跳过对应可选安装并继续执行。
- Starship 离线包目前仅内置 x86_64 版本；非 x86_64 架构会跳过离线安装，除非允许在线回退。
