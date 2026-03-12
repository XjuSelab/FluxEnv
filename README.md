# FluxEnv

FluxEnv 是一个基于 Bash 的环境初始化工具，面向 Ubuntu / Debian 宿主机、AutoDL 容器用户环境，以及 root-only 容器环境。

## 入口脚本

- `scripts/fluxenv`：统一初始化入口
- `scripts/fetch_resources.sh`：离线资源抓取入口

## 仓库结构

- `lib/`：公共运行时、配置加载和各阶段安装逻辑
- `config/`：内置 profile、示例配置和资源清单
- `offline_resources/`：安装时使用的离线资源
- `docs/`：补充说明文档

## 使用方法

先进入仓库目录：

```bash
cd /path/to/FluxEnv
```

如需先准备离线资源：

```bash
./scripts/fetch_resources.sh
```

### 1. `standard` 标准模式

普通用户通过 `sudo` 启动：

```bash
cd /path/to/FluxEnv
sudo ./scripts/fluxenv --profile standard
```

这种方式会复用当前 `sudo` 用户，不会新建用户。

纯 root 会话启动：

```bash
cd /path/to/FluxEnv
./scripts/fluxenv --profile standard
```

这种方式会进入新建用户流程。

### 2. `autodl` 模式

适用于 AutoDL 和容器环境，会根据启动上下文自动判定目标用户：

```bash
cd /path/to/FluxEnv
sudo ./scripts/fluxenv --profile autodl
```

普通用户通过 `sudo` 启动时，会复用当前用户：

```bash
cd /path/to/FluxEnv
sudo ./scripts/fluxenv --profile autodl
```

纯 root 会话启动时，会继续配置 `root`：

```bash
cd /path/to/FluxEnv
./scripts/fluxenv --profile autodl
```

如需指定配置文件并关闭交互：

```bash
cd /path/to/FluxEnv
sudo ./scripts/fluxenv --profile standard --config ./config/example.env --non-interactive
```

查看帮助：

```bash
./scripts/fluxenv --help
```

## 代理说明

如果在 WSL 或切换用户后访问 GitHub 很慢，建议直接为目标用户设置 Git 全局代理：

```bash
git config --global http.proxy http://127.0.0.1:xxxx
git config --global https.proxy http://127.0.0.1:xxxx
```

将 `xxxx` 替换为你本地代理端口。相比只设置 `http_proxy` / `https_proxy`，这种方式在 `sudo` 或 `su -` 切换用户后通常更稳定。

如需清空 Git 代理：

```bash
git config --global http.proxy ""
git config --global https.proxy ""
```

## 说明

- 默认会在 `apt update` 前切换 Ubuntu 软件源到清华源；如需关闭，可设置 `ENABLE_APT_MIRROR=0`
- apt 源备份写入 `/var/backups/fluxenv/apt/`，不会污染 `sources.list.d`
- 默认优先使用 `offline_resources/` 中的离线资源，除非显式开启在线抓取
- `standard` 和 `autodl` 两种模式结束后都会自动进入 `zsh`
- 在 WSL 的 `standard` 模式下，会自动检查并修正 `/etc/wsl.conf` 的默认登录用户；修改后需要在 Windows 侧执行 `wsl --shutdown`
- 资源来源说明见 `docs/RESOURCE_SOURCES.md`
