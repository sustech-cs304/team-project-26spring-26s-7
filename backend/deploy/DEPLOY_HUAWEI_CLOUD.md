# 华为云生产部署指南 —— audit.itsmappin.top

把 `Backend_ItsMapPin/` 整套部署到华为云服务器 `139.159.143.195`，
对外只暴露 `https://audit.itsmappin.top`，4 个后端服务通过 nginx
路径路由分流，全程 HTTPS、符合应用上架合规要求。

> 部署目标：让前端只需把 BASE_URL 改成 `https://audit.itsmappin.top`，
> 路径前缀（`/v1/...`、`/api/share/...`）保持原样不变，零业务代码改动。

## 两阶段部署（**重要**）

华为云对未备案域名的 **80/443** 端口有强制拦截（国家政策），但**非标端口
不拦**。所以推荐这样分两步：

| 阶段 | 触发 | 公网端口 | 前端 BASE_URL | nginx 配置 |
|---|---|---|---|---|
| **1. 备案前测试** | 现在 | **8443** | `https://audit.itsmappin.top:8443` | `audit.itsmappin.top.test.conf` |
| **2. 备案后生产** | ICP 审批通过 | **80 / 443** | `https://audit.itsmappin.top` | `audit.itsmappin.top.prod.conf` |

**全程 HTTPS、证书相同、路径不变**——切换只动 nginx vhost + 安全组 + 前端
BASE_URL，4 个后端服务**不重启**。

`deploy/scripts/install.sh` 默认装阶段 1；ICP 下来后跑
`deploy/scripts/enable-production.sh` 切到阶段 2。

---

## 一、最终架构

```
[App / H5 / 浏览器]
       ↓ HTTPS (TLS 1.2/1.3, HSTS, CSP)
[华为云 ECS 139.159.143.195]
  └─ nginx :443   (audit.itsmappin.top, 证书=华为云免费 DV)
        ├── /v1/*                  → 127.0.0.1:8000   ai-relay
        ├── /api/*                 → 127.0.0.1:8001   share-service
        ├── /s/*  /smap/*  /static/*  /assets/*  /cache/*  /share/*
        │                           → 127.0.0.1:8001   share-service viewer
        ├── /filter/*  (rewrite)   → 127.0.0.1:9100   sensitive-filter
        ├── /censor/*  (rewrite)   → 127.0.0.1:9200   picture-check
        ├── /docs  /openapi.json   → 127.0.0.1:9200   picture-check
        └── /health                → nginx 直接 200
```

每个后端服务只监听 **127.0.0.1**（除 sensitive-filter / picture-check 在内网做
解耦后端时 nginx 仍走环回），公网流量必须经过 nginx → HTTPS。

---

## 二、前置准备（华为云控制台）

### 2.1 ICP 备案

按用户选的"1 个 audit.itsmappin.top + 路径路由"策略，**只需要备案 1 个子域名**：

| 项目 | 填写 |
|---|---|
| 主域名 | `itsmappin.top` |
| 网站名称 | ItsMapPin（或团队约定） |
| 网站首页 URL | `https://audit.itsmappin.top` |
| 服务器 IP | `139.159.143.195`（华为云 ECS） |
| 服务器所在地 | 华为云对应区域 |
| 网站内容 | 软件后端 API + H5 viewer |

> 注意：ICP 备案中"网站域名"一栏可以同时填 `itsmappin.top` 和 `audit.itsmappin.top`，
> 都同一备案号即可。**不需要**为 ai./share./filter./censor. 单独备案，因为根本没有
> 这些子域名（所有路由都在 audit. 一个域名下）。

完整子域名清单见 [icp-subdomains.md](icp-subdomains.md)。

### 2.2 SSL 证书

华为云控制台 → SSL 证书管理 → 申请免费 DV 证书

| 字段 | 值 |
|---|---|
| 证书品牌 | DigiCert（免费版，1 年） |
| 域名 | `audit.itsmappin.top`（单域名版） |
| 验证方式 | DNS（华为云自家 DNS 就在控制台勾一下自动） |

签发后下载 **Nginx 格式** 的证书包，解压得到两个文件：

- `audit.itsmappin.top_xxxxxxxx.pem` → 改名 `fullchain.pem`
- `audit.itsmappin.top_xxxxxxxx.key` → 改名 `privkey.pem`

### 2.3 安全组 / 防火墙

ECS 控制台 → 安全组 → 入方向放行：

**阶段 1（备案前测试）只需要：**

| 协议 | 端口 | 来源 | 用途 |
|---|---|---|---|
| TCP | 22 | 你的 IP | SSH |
| TCP | **8443** | 0.0.0.0/0 | **HTTPS 测试入口（非标端口华为云不拦未备案域名）** |

**阶段 2（备案后生产）追加：**

| 协议 | 端口 | 来源 | 用途 |
|---|---|---|---|
| TCP | 80 | 0.0.0.0/0 | HTTP（仅 → 443 跳转 + ACME） |
| TCP | 443 | 0.0.0.0/0 | HTTPS 主入口 |
| TCP | ~~8443~~ | — | 稳定后可删 |

**8000 / 8001 / 9100 / 9200 任何时候都不要对外开放**——服务只本地监听，
公网必须走 nginx。

---

## 三、部署步骤

### 3.1 把代码上传到服务器

在校园网这台 dev 服务器上：

```bash
cd /data2/cse12310817
# 打包（排除 .git / .venv / logs / *.db）
tar --exclude='.git' --exclude='.venv' --exclude='logs' \
    --exclude='*.db' --exclude='*.db-wal' --exclude='*.db-shm' \
    --exclude='__pycache__' \
    -czf /tmp/backend.tar.gz Backend_ItsMapPin/

# scp 到华为云
scp /tmp/backend.tar.gz root@139.159.143.195:/tmp/
```

到华为云服务器：

```bash
ssh root@139.159.143.195

mkdir -p /opt/itsmappin
cd /opt/itsmappin
tar -xzf /tmp/backend.tar.gz
# 现在 /opt/itsmappin/Backend_ItsMapPin/ 里有全部代码
```

### 3.2 准备 .env

```bash
cd /opt/itsmappin/Backend_ItsMapPin
cp .env.example .env
nano .env          # 把所有 replace-me 占位值填上
chmod 600 .env
```

**必填**：`SF_KEY`、`BIC_API_KEY`、`BIC_SECRET_KEY`、`SHARE_HMAC_KEY`、
`AI_SERVICE_API_KEYS`、`CORS_ORIGINS`（建议设成 `https://audit.itsmappin.top`）、
`SHARE_PUBLIC_BASE`（设成 `https://audit.itsmappin.top`）。

### 3.3 放 SSL 证书

```bash
mkdir -p /etc/nginx/ssl/audit.itsmappin.top
# 把 fullchain.pem 和 privkey.pem 上传到这里
scp fullchain.pem privkey.pem root@139.159.143.195:/etc/nginx/ssl/audit.itsmappin.top/
chmod 600 /etc/nginx/ssl/audit.itsmappin.top/privkey.pem
```

### 3.4 跑一键安装脚本（**阶段 1：备案前测试模式**）

```bash
cd /opt/itsmappin/Backend_ItsMapPin/deploy/scripts
sudo ./install.sh                     # 默认装测试模式 = 监听 :8443
# 或显式：sudo DEPLOY_MODE=test ./install.sh
# （备案下来后想直接跳到生产用：sudo DEPLOY_MODE=production ./install.sh）
```

脚本会做：

1. 装 nginx + python3 + venv
2. 建 `itsmappin` 系统用户、`/var/log/itsmappin/`、`/var/lib/itsmappin/`
3. 建两个 venv，装 4 个服务的依赖
4. 装 4 个 systemd unit
5. 装 nginx vhost 配置
6. 校验 SSL 证书
7. 启动 4 个服务 + nginx
8. 跑本机自测（curl 5 个 /health）

预期最后输出（测试模式）：

```
=========================================
安装完成。状态：
  ✓ 127.0.0.1:8000
  ✓ 127.0.0.1:8001
  ✓ 127.0.0.1:9100
  ✓ 127.0.0.1:9200
  ✓ 0.0.0.0:8443

本机自测：
  /health        → HTTP 200
  /health/ai     → HTTP 200
  /health/share  → HTTP 200
  /health/filter → HTTP 200
  /health/censor → HTTP 200

公网测试 URL：https://audit.itsmappin.top:8443/health
=========================================
```

### 3.5 备案下来后切到生产模式

```bash
cd /opt/itsmappin/Backend_ItsMapPin/deploy/scripts
sudo ./enable-production.sh
```

脚本会：
1. 卸下 test.conf，装上 prod.conf（监听 80 + 443）
2. nginx reload（4 个后端服务不重启）
3. 跑公网自测验证

期间需要**先**把华为云安全组里的 80、443 入方向放行（如果还没做的话）。

切完之后：
- 前端 BASE_URL 改成 `https://audit.itsmappin.top`（去掉 `:8443`）
- 安全组里的 8443 入方向规则可以删了

---

## 四、对外验证

### 阶段 1（测试模式）

从任意公网机器（手机 / 笔记本）：

```bash
TEST=https://audit.itsmappin.top:8443

# 基础 + TLS 头
curl -sI $TEST/health
# 期待：HTTP/2 200, x-deploy-mode: pre-icp-test

# AI 服务（替换 BEARER 为 .env 里的 AI_SERVICE_API_KEYS）
curl -X POST $TEST/v1/chat/completions \
  -H "Authorization: Bearer DEV_xxxxxxxxxxxxxxxx" \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen","messages":[{"role":"user","content":"你好"}],"max_tokens":50}'

# share-service
curl -X POST $TEST/api/share/create \
  -H 'X-Dev-Uid: alice' \
  -H 'Content-Type: application/json' \
  -d '{"tripCloudId":"t-1","expireDays":7,"snapshot":{"v":1,"trip":{},"nodes":[]},"photoManifest":[],"consentVersion":"share-v1"}'

# 敏感词
curl -X POST $TEST/filter/check \
  -H 'Content-Type: application/json' -d '{"text":"测试"}'

# 图片审核
curl -X POST $TEST/censor/text_check \
  -H 'Content-Type: application/json' -d '{"text":"测试文本"}'
```

### 阶段 2（生产模式）

跑 `enable-production.sh` 之后，把上面所有 `$TEST=https://audit.itsmappin.top:8443`
换成 `BASE=https://audit.itsmappin.top`（去掉 `:8443`），其它都一样，再跑一遍。

---

## 五、前端要改的内容

前端只改 BASE_URL 一处。本次部署同步把前端 `ApiEndpoints.ets` 已改好，见
[前端变更](#前端变更)。逻辑：

```typescript
// 阶段 1（测试，正在用）：
const BASE_URL = "https://audit.itsmappin.top:8443"

// 阶段 2（备案下来后改这一行，去掉 :8443）：
const BASE_URL = "https://audit.itsmappin.top"

// 派生的几个 base 不动：
const VISION_LLM_BASE_URL = BASE_URL                   // 用 /v1/...
const SHARE_BASE_URL      = BASE_URL                   // 用 /api/share/...
const FILTER_BASE_URL     = BASE_URL + "/filter"       // /filter/check ...
const CENSOR_BASE_URL     = BASE_URL + "/censor"       // /censor/check, /censor/text_check ...
```

所有路径**前缀**（`/v1/chat/completions`、`/api/share/...`）保持原样，零业务代码改动。
sensitive-filter 和 picture-check 的客户端调用要加 `/filter` 或 `/censor` 前缀（在
nginx 这层 rewrite 去掉，后端代码不变）。

---

## 六、切流量（零停机方案）

校园网那台 dev 服务器现在还在跑 4 个旧服务 + 2 个 cloudflared，**前端可能还在用**。
切流量步骤：

1. **完成上面的 3.1～3.4**，确认华为云这一套自测全过
2. **公网验证**（上面四、）全过
3. 前端发版（改 BASE_URL）→ 灰度测试一两个用户
4. 校园网 dev 这台机器跑 `Backend_ItsMapPin/stop_all.sh` 停掉旧服务
5. 校园网两个 cloudflared 进程也 kill 掉（`pkill -af 'cloudflared.*trycloudflare'`）

只有第 4 步真正切断旧链路。在此之前两套都跑，**前端用哪个由它自己的 BASE_URL 决定**。

---

## 七、运维 cheatsheet

### 看状态
```bash
systemctl status ai-relay share-service sensitive-filter picture-check nginx
ss -tlnp | grep -E ':80|:443|:8000|:8001|:9100|:9200'
```

### 看日志
```bash
journalctl -u ai-relay -f --since "10 min ago"
journalctl -u share-service -f
tail -f /var/log/itsmappin/ai-relay.log
tail -f /var/log/nginx/audit.access.log
tail -f /var/log/nginx/audit.error.log
```

### 重启某个服务（不影响其它）
```bash
sudo systemctl restart ai-relay
```

### 改 .env 后所有服务重读
```bash
sudo systemctl restart ai-relay share-service sensitive-filter picture-check
```

### nginx reload（改完 vhost 配置不停服务）
```bash
sudo nginx -t && sudo systemctl reload nginx
```

### SSL 证书续期
华为云免费 DV 证书 1 年期满，到期前 30 天控制台会提醒。流程同 2.2，
拿到新证书后：

```bash
sudo cp new-fullchain.pem /etc/nginx/ssl/audit.itsmappin.top/fullchain.pem
sudo cp new-privkey.pem  /etc/nginx/ssl/audit.itsmappin.top/privkey.pem
sudo chmod 600 /etc/nginx/ssl/audit.itsmappin.top/privkey.pem
sudo systemctl reload nginx
```

### share-service 数据库过期清理（cron）
```bash
sudo crontab -u itsmappin -e
# 加一行：
0 3 * * * cd /opt/itsmappin/Backend_ItsMapPin/share-service && \
  .venv/bin/python -m share_service.scripts.purge_expired \
  >> /var/log/itsmappin/share-purge.log 2>&1
```

---

## 八、常见坑

| 症状 | 原因 | 解决 |
|---|---|---|
| 自测 `/health` 返 502 | 后端服务没起 | `systemctl status ai-relay`，看错误日志 |
| `nginx -t` 报 `cannot load certificate` | 证书路径或权限错 | 确认 `/etc/nginx/ssl/.../fullchain.pem` 存在且 nginx 可读 |
| 外网访问报 ERR_SSL_PROTOCOL_ERROR | 证书域名不匹配 | 重新申请证书时填的 `audit.itsmappin.top` 不能写错 |
| 外网 403 / 404 | 路径没走对 | 看 nginx access.log 看 location 是否命中 |
| 外网超时（永远 connect） | 安全组没放 443 | 华为云 ECS → 安全组 → 入方向放 443 |
| `journalctl -u ai-relay` 报 SF_KEY 缺 | EnvironmentFile 没读到 | 确认 `/opt/itsmappin/Backend_ItsMapPin/.env` 存在且 `chmod 640`，owner=itsmappin |
| share-service 启动报 import 错 | venv 路径不对 | systemd unit 里 ExecStart 用的是 `share-service/.venv/bin/uvicorn`，确认这条 venv 真的建好了 |
| AI 调用返回空 content | Qwen3 thinking 模式（理论已兜底） | 看 ai-relay 日志 `normalize_response` 是否触发；若没有，确认 SiliconFlow 配额 |
| 跨域报 CORS error | `.env` 里 CORS_ORIGINS 没设对 | 改成 `https://audit.itsmappin.top` 或 `*`（dev only） |

---

## 九、回滚方案

如果新部署有问题，立即回滚：

```bash
# 在华为云上
sudo systemctl stop ai-relay share-service sensitive-filter picture-check nginx

# 在校园网 dev 上重启旧服务（如果之前停了）
cd /data2/cse12310817/Backend_ItsMapPin
./start_all.sh
# 然后重新拉两个 cloudflared，把 URL 抄回给前端
```

前端如果发版了，回滚的方法是把 `BASE_URL` 改回 quick tunnel URL 再热更新。

---

## 十、关于"应用上架合规"的具体点

按主流应用商店（华为应用市场 / 苹果 App Store / 国内安卓商店）的隐私与传输合规要求，
本架构满足：

| 要求 | 满足方式 |
|---|---|
| 所有用户数据传输 HTTPS | nginx 强制 80 → 443，TLS 1.2+ |
| 服务器位置合规（中国大陆境内服务用境内 IP） | 华为云 ECS 境内 IP + ICP 备案 |
| 证书可信链 | DigiCert / 华为云签发，浏览器原生信任 |
| HSTS（防降级攻击） | `Strict-Transport-Security` 6 个月，含 includeSubDomains |
| 防止 MIME 嗅探 | `X-Content-Type-Options: nosniff` |
| Clickjacking 防护 | `X-Frame-Options: SAMEORIGIN`（viewer.html 只允同站嵌套） |
| 跨域明确白名单 | nginx CORS 由各后端控制；建议 `.env` 收紧 `CORS_ORIGINS` |
| 限流防滥用 | nginx + 各服务进程内双层 |
| 日志可审计 | nginx access/error + 各服务日志 + sensitive-filter 命中审计（uid 已 hash） |
| 隐私敏感字段不上传第三方 | sensitive-filter 完全本地；picture-check 仅图片 base64 转百度（已隐含告知用户） |

**还需要在前端隐私政策里声明**：

1. 文本会送 SiliconFlow Cloud（北京）做大模型推理
2. 图片会送百度智能云（北京）做内容审核
3. 数据回收政策（用户撤销分享立即删除）

应用市场上架时这三点要写进隐私政策。
