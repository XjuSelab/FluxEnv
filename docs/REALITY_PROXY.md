# REALITY 代理一键部署（`scripts/setup_reality.sh`）

在一台干净的 VPS 上一键部署 **VLESS + XTLS-Vision + REALITY**（Xray 核心），
产出可直接导入 v2rayN 的 `vless://` 分享链接。当下最快、免域名/证书、抗封锁。

## 为什么是这套

- **Vision 流控**（`xtls-rprx-vision`）：接近线速，开销低。
- **REALITY**：借用真实大站的 TLS 握手，无需自备域名和证书，指纹与真站一致，难探测。
- **v2rayN 原生支持**：`vless://…&security=reality…` 链接直接导入（需 v2rayN 6.x+）。

## 用法

在目标 VPS 上以 root 运行：

```bash
sudo bash scripts/setup_reality.sh            # 全自动:装 xray + 自动选 dest + 自测 + 出链接
sudo bash scripts/setup_reality.sh link       # 只读:重新打印已有配置的分享链接/二维码
sudo bash scripts/setup_reality.sh probe      # 只测候选 dest 证书大小,不改配置
sudo bash scripts/setup_reality.sh cleanup    # 停用 xray 并还原最近一次配置备份
```

脚本自包含（不依赖 `lib/`），可单独 `scp` 到任意机器运行。

### 可选环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `REALITY_PORT` | `443` | 监听端口 |
| `REALITY_DEST` | 自动选优 | 指定偷跑目标（如 `www.tesla.com`），仍会自测 |
| `REALITY_UUID` | 复用/新生成 | 指定 UUID |
| `REALITY_IP` | 公网出口 IP | 分享链接里的地址（NAT 机手动指定） |
| `REALITY_LABEL` | `<主机名>-Reality` | 节点备注名 |
| `REALITY_FORCE` | `0` | 置 `1` 即使已有配置也重建（换新密钥，旧链接失效） |

## 幂等

已存在 reality 配置且未设 `REALITY_FORCE=1` 时，脚本**复用现有密钥/UUID/dest**，
只重新校验、重启、自测并重出链接——不会打断现网、不会让旧链接失效。

## 关键坑：REALITY dest 的 8192 字节证书上限

Xray 26.x 的 REALITY 有一个硬编码 **8192 字节**上限：偷跑目标（dest）返回的
TLS Certificate 记录超过它，握手就被拒，服务端日志报
`REALITY: processed invalid connection … handshake did not complete successfully`，
**即使公私钥、shortId 全部正确也连不上**（见 XTLS/Xray-core issue #6356）。

`www.microsoft.com` 的证书记录约 8273B（原始 DER 5879B + OCSP stapling/SCT 约 2400B 开销）就会直接挂。

脚本因此做了两道保险：

1. **证书链预筛**：`openssl -showcerts` 量每个候选的 DER 链大小，超过 `DER_MAX`（默认 5500B，留足开销余量）直接跳过。
2. **握手自测**：写入配置后本机起临时客户端拨自己，经 socks 访问 `generate_204`，
   返回 204 才算通过，否则换下一个候选。

### 选 dest 三原则（内置候选已满足）

1. 证书链小（避开 8192 上限）。
2. 不被 GFW 按 SNI 阻断（避开 google 系等）。
3. 不在 xray 的 `apple/icloud` 告警名单（会警告"可能被 GFW 封 IP"）。

内置候选：`www.tesla.com`（最小，约 2800B）、`www.samsung.com`、`www.nvidia.com`、
`addons.mozilla.org`、`www.amazon.com`、`www.lovelive-anime.jp`。可用 `probe` 动作随时复核。

## 其它坑（脚本已规避）

- **xray 靠文件扩展名判断配置格式**：临时配置文件必须是 `.json` 后缀，裸 `mktemp`
  会让 `xray -test` 报 `Failed to get format`。
- **新版 `xray x25519` 输出格式**：公钥那行是 `Password (PublicKey): …`，客户端 `pbk`
  取这个值；脚本用 `xray x25519 -i <私钥>` 反推公钥以支持复用。
