# Claude 多用户共享登录（add_claude_user.sh）

让一台机器上的多个 Linux 用户**共用同一个 Claude Code 登录**（一个订阅/一份凭证），
而每个用户敲 `claude` 时的**环境仍像自己原生的**（`HOME`/`USER`/`git`/`ssh` 都是自己的）。

适用场景：一个人、一台机器，用多个 Linux 账号分隔不同工作，但不想每个账号都单独登录一次 Claude。

> ⚠️ 前提：这是把**一个订阅**给**同一个人**的多个账号复用。若给不同的人共享个人订阅，违反 Anthropic 条款，请改用各自 `/login` 或 API key。

---

## 快速开始

```bash
# 新增/幂等接入一个用户（登录持有者默认 winbeau）
sudo bash scripts/add_claude_user.sh dev3

# 指定登录持有者
sudo CLAUDE_LOGIN_USER=alice bash scripts/add_claude_user.sh dev3

# 移除某用户的接入（公共基建保留）
sudo bash scripts/add_claude_user.sh dev3 cleanup
```

之后 `dev3` 登录，任意目录敲 `claude` 即用登录持有者的订阅；`$HOME`/`$USER` 等环境是原生 `dev3` 的。

## 前提假设

- Ubuntu / Debian（依赖 `setfacl`、`visudo`、`sudo --preserve-env`）。
- **登录持有者**（默认 `winbeau`）已用 native 安装装好 Claude Code（`~/.local/bin/claude`）并 `/login`。
- 家目录默认 `0750`（脚本用 ACL 而非放宽 `o+` 权限来授权）。

## 可配置变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `CLAUDE_LOGIN_USER` | `winbeau` | 登录持有者（凭证的真正主人） |
| `CLAUDE_SHARE_GROUP` | `claudeshare` | 共享组名 |
| `CLAUDE_USER_PASSWORD` | `123456` | 新建用户的初始密码（仅在**首次创建**时设置） |

## 新建用户时的默认配置

- **初始密码**：默认 `123456`（`CLAUDE_USER_PASSWORD` 可覆盖）。仅在用户**首次创建**时设置；对已存在用户重跑脚本不会改密码。
- **shell**：复用 FluxEnv 的 `configure_shell_env_for_user`，配置 **zsh + starship**（`.zshrc`、`starship.toml`、zsh 插件），并 `chsh` 到 zsh。
  此步**强制全线上**（`OFFLINE_DIR` 指向空目录 + `ALLOW_ONLINE_FETCH=1`）：starship 走 `starship.rs`、插件走 `git clone`，不使用 `offline_resources/`。
  starship 已系统级安装则跳过。若在非 FluxEnv 目录下运行（找不到 `lib/`），此步自动跳过，不影响 claude 桥接。

---

## 架构

```
公共基建（一次性，所有用户共用）
 ① /usr/local/bin/claude        wrapper：登录持有者直跑真二进制；他人→sudo 切过去 + --preserve-env 带过原生环境
 ② /usr/local/bin/claude-bridge helper：把 HOME/USER/LOGNAME/MAIL 钉回调用者、清 SUDO_*、注入内部标志，再 exec 真 claude
 ③ /etc/sudoers.d/claude-share  组级 NOPASSWD + SETENV，仅放行 claude
 ④ 组 claudeshare               登录持有者 + 所有共享用户

每个用户（脚本自动做）
 ⑤ 入组 claudeshare
 ⑥ /home/X 用 ACL 开放给组（claude 任意目录可读写）+ 保护 .ssh
 ⑦ /home/X/.claude      → 目录软链 → 登录持有者的        （共享登录，抗原子 rename）
 ⑧ /home/X/.claude.json → 拷贝一份                        （HOME 根文件原子写、不能软链；不含 token）
 ⑨ 初始密码（默认 123456）+ zsh + starship               （复用 FluxEnv，全线上；见下）
```

### 一次调用的流程（以 dev3 为例）

```
dev3 输入 claude
  └─ 命中 wrapper（以 dev3 跑）→ 不是登录持有者
       └─ sudo -u winbeau --preserve-env BRIDGE_PATH=$PATH claude-bridge …   （sudoers 免密放行）
            └─ helper（以 winbeau uid 跑，但 dev3 的环境被带过来）
                 ├─ HOME=/home/dev3 USER=dev3 …（钉回调用者，清 SUDO_*）
                 ├─ DISABLE_INSTALLATION_CHECKS=1（消假警告）
                 └─ exec 真 claude
                      ├─ 读 /home/dev3/.claude → 软链 → winbeau 的凭证（= 那个订阅登录）
                      └─ 在当前目录读写文件（winbeau uid，经 ACL 有权）
```

---

## 为什么不能直接共享凭证文件（实测的三道墙）

`~/.claude/.credentials.json` 无法简单地软链/拷贝给别的 UID 共享，实测原因：

1. **原子写**：Claude 刷新 token 用「写临时文件 + `rename()` 覆盖」。`rename` 不跟随**最后一节**的软链 →
   软链凭证文件会被**潰成普通文件**，写落在本地、与源分裂。（strace 实锤：`openat(...tmp...)` → `rename(tmp, .credentials.json)`）
2. **0600 属主锁**：凭证强制 `0600` 且属主=写入者 → 别的 UID 根本读不了。
3. **refresh token 轮换**：刷新后旧 refresh token 作废 → 多份拷贝里，一处刷新会让其它份失效、掉线。

结论：不共享文件，而是**让别的用户以登录持有者身份跑 claude**（始终只有一个 UID 碰凭证）。

## 关键设计决策（都由实验验证）

- **目录软链 vs 文件软链**：软链 `.credentials.json` 文件 ✗（原子 rename 潰掉）；软链 `.claude` **目录** ✓。
  规则：`rename` **不**跟随最后一节的软链，但**跟随中间目录**的软链 —— 覆盖发生在解析后的持有者目录内，
  软链本身不动，等于直接刷新持有者的登录。
- **环境对齐**：`sudo --preserve-env` 带过调用者全部环境，helper 再把 `HOME/USER/LOGNAME/MAIL` 钉回调用者、
  清掉 `SUDO_*`。实测 `env` 与「原生该用户的 claude」逐行一致。
- **`.claude.json`**：也是原子写、且位于 `HOME` 根目录（无中间目录可软链）→ 无法共享，给每人一份**拷贝**
  （不含 token；登录仍走 `.claude/` 软链；会话记录在 `.claude/projects/` 里仍共享）。
- **假「安装损坏」警告**：因 `HOME=调用者` 让 claude 去调用者家里找安装。用 `DISABLE_INSTALLATION_CHECKS=1`
  抑制（helper 内注入）。不能用「在 `~/.local/bin/claude` 建软链」糊弄——Ubuntu `~/.profile` 会把 `~/.local/bin`
  前插进 PATH，反而让 `claude` 绕过 wrapper、以调用者身份跑真二进制、读不到凭证。
- **并发安全**：多用户同时跑 ≡ 登录持有者同时开多个 claude 会话（Claude Code 本就支持）。
  实测「强制过期 + 3 实例并发刷新」全部成功、凭证不损坏（原子写 = last-writer-wins）。

---

## 代价与边界

1. **进程 uid = 登录持有者**，消不掉（要读它的 `0600` 凭证）。所以 claude 内 `id`/`whoami`、新建文件属主都是持有者。
   → 让 claude 帮你 `git commit`/`push`、`hf upload` 会用**持有者**的身份/凭证，不是调用者的。
   要用调用者自己的 git/hf 身份，让该用户自己 `/login`（走原生，不用这套桥接）。
2. **claude 历史/会话与登录持有者共享**（`.claude/` 整目录软链）。`.claude.json`（项目列表/UI）每人独立。
3. **额度共享**：所有人算持有者一个订阅，并发越多越快撞限流（这是配额，不是数据竞态）。
4. **ACL 打穿隔离**：`/home/X` 对 `claudeshare` 开放 → 持有者能读写该用户整个家目录（`.ssh` 已排除保护）。
   一个人多账号无所谓；给别人则等于交出该家目录访问权。

## 卸载

```bash
# 移除某用户
sudo bash scripts/add_claude_user.sh <user> cleanup

# 移除公共基建（手动）
sudo rm -f /usr/local/bin/claude /usr/local/bin/claude-bridge /etc/sudoers.d/claude-share
sudo groupdel claudeshare
```

## 排障

- **仍提示 `.claude.json not found`**：确认 `[10]` 步已给该用户拷贝了 `.claude.json`。
- **`claude` 绕过 wrapper 报登录失效**：检查该用户 `~/.local/bin/claude` 是否被别的安装抢占了 PATH；
  本方案不在其家目录放 claude 二进制，`claude` 应解析到 `/usr/local/bin/claude`（wrapper）。
- **env 自测出现差异**：`[11]` 会打印差异行，通常是 `MAIL`/`SHELL` 之类，可在 helper 里补钉。
- **`sudo` 仍要密码**：确认 `/etc/sudoers.d/claude-share` 存在、该用户在 `claudeshare` 组（`id -nG <user>`）。
