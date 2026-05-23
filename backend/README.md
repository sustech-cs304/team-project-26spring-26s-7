# Backend_ItsMapPin —— ItsMapPin 全部后端服务

本目录集中存放 ItsMapPin（TravelPin）项目当前生产用的 **4 个后端服务**的源代码，
以及把它们从零部署、配置环境、启动、验证、停止的完整教程。

> 所有源代码**复制自**项目原仓库，未做任何修改。原始位置如有更新，需手动同步。

## 两条部署路径

| 场景 | 用什么 |
|---|---|
| **生产部署到华为云**（HTTPS / ICP / 应用上架合规） | 看 **[deploy/DEPLOY_HUAWEI_CLOUD.md](deploy/DEPLOY_HUAWEI_CLOUD.md)** —— nginx + systemd + audit.itsmappin.top 单域名路径路由，含一键 install.sh |
| **本地 / 校园网 dev 跑** | 看下面"一、环境准备" + "二、一键启动" —— nohup + quick tunnel，HTTP |

ICP 备案的子域名清单见 [deploy/icp-subdomains.md](deploy/icp-subdomains.md)。

## 目录结构

```
Backend_ItsMapPin/
├── README.md                     ← 本文件：本地 dev 启动教程
├── .env.example                  ← 凭证 / 配置模板，复制为 .env 后填值
├── start_all.sh                  ← 一键启动 4 个服务（本地 dev 用）
├── stop_all.sh                   ← 一键停止
│
├── deploy/                       ← 生产部署物（华为云）
│   ├── DEPLOY_HUAWEI_CLOUD.md    ← 完整生产部署指南（两阶段：备案前 :8443 / 备案后 :80+:443）
│   ├── icp-subdomains.md         ← ICP 备案要登记的子域名清单
│   ├── nginx/audit.itsmappin.top.test.conf   ← 备案前测试模式（:8443）
│   ├── nginx/audit.itsmappin.top.prod.conf   ← 备案后生产模式（:80 + :443）
│   ├── systemd/*.service                 ← 4 个 systemd unit
│   ├── scripts/install.sh                ← 华为云一键安装（默认装测试模式）
│   └── scripts/enable-production.sh      ← ICP 通过后切到生产
│
├── ai-relay/                     ← :8000 SiliconFlow Cloud 转发（AI 文案）
│   ├── siliconflow_relay.py
│   ├── requirements.txt
│   └── README.md
│
├── sensitive-filter/             ← :9100 敏感词字符串检测
│   ├── sensitive_filter_service.py
│   ├── data/sensitive_words.txt  (41887 词)
│   ├── data/whitelist.txt
│   ├── requirements.txt
│   └── README.md
│
├── picture-check/                ← :9200 百度图片+文本审核
│   ├── baidu_image_censor.py
│   ├── rest2.0solutionv1img_censorv2user_defined.py   (官方裸调样例)
│   ├── rest2.0solutionv1text_censorv2user_defined.py  (官方裸调样例)
│   ├── data/.gitkeep
│   ├── requirements.txt
│   └── README.md
│
└── share-service/                ← :8001 分享 + 发布（FastAPI + SQLite）
    ├── share_service/            (Python 包；包含 routers/core/db/static/tests)
    ├── requirements.txt
    ├── .env.example              (此服务专属示例；上层 .env 已覆盖其字段)
    ├── README.md
    └── README_original.md        (从原仓库复制过来的 README，参考)
```

## 服务一览

| # | 服务 | 端口 | 协议 | 上游依赖 | 进程内依赖 |
|---|------|------|------|----------|------------|
| 1 | **ai-relay** | 8000 | HTTP（OpenAI 兼容） | SiliconFlow Cloud API | 调 sensitive-filter :9100 |
| 2 | **sensitive-filter** | 9100 | HTTP | 无 | 无 |
| 3 | **picture-check** | 9200 | HTTP | 百度智能云审核 API | 无 |
| 4 | **share-service** | 8001 | HTTP | 无（本地 SQLite） | 无 |

服务依赖关系：`ai-relay → sensitive-filter`，其它都互相独立。
所以**启动顺序**：sensitive-filter → ai-relay/picture-check/share-service（后三者无顺序要求）。

---

# 一、环境准备

## 1.1 系统要求

- Linux（脚本针对 Linux 写；其它 Unix 也可，Windows 需 WSL）
- Python **3.10+**（建议 3.10 / 3.11 / 3.12 任一）
- ~500MB 磁盘（依赖 + 词表）
- 出网能力：需要能访问 `api.siliconflow.cn` 和 `aip.baidubce.com`

不需要：GPU、conda、模型权重（全部走云 API）。

## 1.2 安装系统包

```bash
# Debian/Ubuntu
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip

# CentOS/RHEL
sudo yum install -y python3 python3-venv
```

## 1.3 准备 Python 虚拟环境

本项目用 **2 个 venv**（share-service 用单独 venv 因为依赖较多）：

```bash
cd /path/to/Backend_ItsMapPin

# (1) 主 venv：ai-relay + sensitive-filter + picture-check 共用
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r ai-relay/requirements.txt
pip install -r sensitive-filter/requirements.txt
pip install -r picture-check/requirements.txt
deactivate

# (2) share-service 单独 venv
cd share-service
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
deactivate
cd ..
```

> 你也可以用同一个 venv 装所有 4 个 requirements.txt，依赖版本互兼容。
> 分开纯为隔离，方便 share-service 单独升级而不影响 AI 服务。

## 1.4 申请凭证

需要 3 个外部凭证：

| # | 服务 | 凭证 | 申请入口 |
|---|------|------|----------|
| 1 | SiliconFlow Cloud | API Key (`sk-...`) | https://cloud.siliconflow.cn/account/ak |
| 2 | 百度智能云内容审核 | API Key + Secret Key | https://console.bce.baidu.com → 智能云内容审核 |
| 3 | 高德地图 JS API（可选） | Key + 安全密钥 | https://lbs.amap.com（仅 share-service viewer 用到） |

另外要生成 2 个本地随机串：

```bash
# share-service HMAC 签名密钥（必填）
python -c "import secrets; print('SHARE_HMAC_KEY=' + secrets.token_urlsafe(32))"

# ai-relay 客户端 Bearer token（自定义，分发给前端用）
python -c "import secrets; print('AI_SERVICE_API_KEYS=DEV_' + secrets.token_hex(16))"
```

## 1.5 写 .env

```bash
cd /path/to/Backend_ItsMapPin
cp .env.example .env
$EDITOR .env   # 把所有 replace-me / replace_me 占位值替换成 1.4 拿到的真实值
chmod 600 .env # 防止他人读到密钥
```

**最少必填字段**：

- `SF_KEY` (SiliconFlow)
- `BIC_API_KEY`、`BIC_SECRET_KEY` (百度)
- `SHARE_HMAC_KEY` (HMAC)
- `AI_SERVICE_API_KEYS` (建议改成自己的随机 token)

`.env` 已加入 `.gitignore`，不会被 commit。

---

# 二、一键启动

确认 1.3 venv 已建好、1.5 `.env` 已填好，然后：

```bash
cd /path/to/Backend_ItsMapPin
./start_all.sh
```

预期输出：

```
[start] sensitive-filter ...
  → sensitive-filter PID=12345  (log: .../logs/sensitive-filter.log)
[start] picture-check ...
  → picture-check PID=12346  (log: .../logs/picture-check.log)
[start] ai-relay ...
  → ai-relay PID=12347  (log: .../logs/ai-relay.log)
[start] share-service ...
  → share-service PID=12348  (log: .../logs/share-service.log)

==========================================
全部启动完成。状态：
  ✓ 127.0.0.1:8000
  ✓ 127.0.0.1:8001
  ✓ 0.0.0.0:9100
  ✓ 0.0.0.0:9200
==========================================
```

脚本特性：

- **幂等**：检测到端口已占用会跳过，不会重复拉起
- **优雅降级**：占位凭证（`replace-me`）的服务会跳过并提示
- **后台运行**：用 `nohup` 启动，关 SSH 不影响
- **PID 跟踪**：写 `logs/<svc>.pid`，停止脚本据此 kill

## 停止

```bash
./stop_all.sh
```

先 SIGTERM 优雅停止（4 秒），不行再 SIGKILL。

---

# 三、手动启动（调试用）

如果一键脚本失败要单独排查，按下面顺序在 4 个终端里跑。

## 3.1 sensitive-filter（先启动，被 ai-relay 依赖）

```bash
cd Backend_ItsMapPin
source .venv/bin/activate

export SF_WORDS_FILE="$PWD/sensitive-filter/data/sensitive_words.txt"
export SF_WHITELIST_FILE="$PWD/sensitive-filter/data/whitelist.txt"
export SF_HOST=0.0.0.0
export SF_PORT=9100
export SF_LOG_DIR="$PWD/logs"

cd sensitive-filter
python sensitive_filter_service.py
# 看到 [load] words=41887 ... 和 Uvicorn running on 0.0.0.0:9100 即成功
```

## 3.2 picture-check

```bash
cd Backend_ItsMapPin
source .venv/bin/activate
set -a && source .env && set +a   # 把 BIC_* 注入

cd picture-check
python baidu_image_censor.py
# 看到 [boot] token OK 即成功
```

## 3.3 ai-relay

```bash
cd Backend_ItsMapPin
source .venv/bin/activate
set -a && source .env && set +a   # 把 SF_KEY / AI_SERVICE_API_KEYS 注入
unset HTTP_PROXY HTTPS_PROXY      # 防 cloudflared 时干扰；本服务也安全

cd ai-relay
python siliconflow_relay.py \
  --server-host 127.0.0.1 \
  --server-port 8000 \
  --api-keys "$AI_SERVICE_API_KEYS" \
  --rate-limit-per-min "${AI_SERVICE_RATE_LIMIT_PER_MIN:-30}" \
  --siliconflow-key "$SF_KEY" \
  --sensitive-filter-url http://127.0.0.1:9100
```

## 3.4 share-service

```bash
cd Backend_ItsMapPin/share-service
source .venv/bin/activate
set -a && source ../.env && set +a   # 注意是上一层的 .env

uvicorn share_service.main:app --host 127.0.0.1 --port 8001
# 首次启动会自动建 share.db
```

---

# 四、验证 4 个服务都活着

替换下面的 `BEARER` 为你 `.env` 里的 `AI_SERVICE_API_KEYS` 第一个 token。

```bash
BEARER='DEV_xxxxxxxxxxxxxxxx'

# sensitive-filter
curl -s http://127.0.0.1:9100/health | python -m json.tool
# 期待：{"status":"ok","words_loaded":41887,...}

curl -s http://127.0.0.1:9100/check \
  -H 'Content-Type: application/json' \
  -d '{"text":"今天天气真好"}'
# 期待：{"blocked":false,...}

# picture-check
curl -s http://127.0.0.1:9200/health | python -m json.tool
# 期待：{"status":"ok","token_cached":true,...}

# ai-relay
curl -s http://127.0.0.1:8000/health | python -m json.tool
# 期待：{"status":"ok","service":"siliconflow-relay",...}

curl -s -X POST http://127.0.0.1:8000/v1/chat/completions \
  -H "Authorization: Bearer $BEARER" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "qwen",
    "messages": [{"role":"user","content":"用一句话介绍北京"}],
    "max_tokens": 80
  }'

# share-service
curl -s http://127.0.0.1:8001/health
# 期待：{"ok":true}

# 走一遍分享业务（dev 模式用 X-Dev-Uid 头）
curl -s -X POST http://127.0.0.1:8001/api/share/create \
  -H 'X-Dev-Uid: alice' \
  -H 'Content-Type: application/json' \
  -d '{"tripCloudId":"trip-1","expireDays":7,
       "snapshot":{"v":1,"trip":{"name":"Demo"},"nodes":[]},
       "photoManifest":[],"consentVersion":"share-v1"}'
```

---

# 五、公网暴露（cloudflared，可选）

校园网防火墙挡入站、出网严格，常规反代 / Let's Encrypt / ngrok 都不能用，
只有 `*.cloudflare.com` 出网通道被放行 —— 所以**公网只能用 cloudflared quick tunnel**。

```bash
# 装 cloudflared（一次性）
# Debian/Ubuntu:
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cf.deb
sudo dpkg -i /tmp/cf.deb

# 暴露 ai-relay 公网（必须）
unset HTTP_PROXY HTTPS_PROXY   # 防响应被代理改坏报 1101
nohup cloudflared tunnel --url http://127.0.0.1:8000 \
  >> logs/cloudflared-ai.log 2>&1 &

# 暴露 share-service 公网（必须）
nohup cloudflared tunnel --url http://127.0.0.1:8001 \
  >> logs/cloudflared-share.log 2>&1 &

# 等 5 秒，从日志里抓 URL：
sleep 5
grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' logs/cloudflared-ai.log    | tail -1
grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' logs/cloudflared-share.log | tail -1
```

每条 quick tunnel 的 URL **跟进程走**：
- 进程不挂 → URL 不变
- 进程重启 → 全新 URL，前端 `ApiEndpoints.ets` 里的 `VISION_LLM_BASE_URL` 和
  `SHARE_PUBLIC_BASE` 必须同步更新

sensitive-filter (:9100) 和 picture-check (:9200) **不需要**公网暴露 ——
它们只被 ai-relay 在本机调用，校园网内业务也能直连 `172.18.35.215:9100/9200`。

---

# 六、日常运维

## 6.1 查看日志

```bash
tail -f logs/ai-relay.log
tail -f logs/share-service.log
tail -f logs/sensitive-filter.log
tail -f logs/picture-check.log
```

带轮转的服务（sensitive-filter / picture-check）会在
`$SF_LOG_DIR` / `$BIC_LOG_DIR`（默认 `/data2/cse12310817/logs/`）下另写一份
`sensitive_filter.log` / `picture_check.log`，含审计字段。

## 6.2 单独重启

```bash
# 取 PID
cat logs/ai-relay.pid

# kill
kill $(cat logs/ai-relay.pid)

# 重启（只起 ai-relay 一个）—— 复用 start_all.sh 的端口检测会自动跳过已运行的
./start_all.sh
```

## 6.3 改敏感词词表后

服务**不自动 reload**。改完 `sensitive-filter/data/sensitive_words.txt` 后：

```bash
kill $(cat logs/sensitive-filter.pid)
./start_all.sh
```

## 6.4 share-service 数据库清理

过期记录不会自动删；跑 purge 脚本（建议 cron）：

```bash
cd share-service
source .venv/bin/activate
set -a && source ../.env && set +a
python -m share_service.scripts.purge_expired
```

cron 每天凌晨 3 点：

```cron
0 3 * * * cd /path/to/Backend_ItsMapPin/share-service && \
  .venv/bin/python -m share_service.scripts.purge_expired \
  >> ../logs/share-purge.log 2>&1
```

---

# 七、常见故障排查

| 症状 | 原因 | 解决 |
|------|------|------|
| `start_all.sh` 报 `[skip] :8000 已被占用` | 之前的进程没停干净 | `./stop_all.sh`；或 `lsof -i :8000` 找出 PID 手动 kill |
| ai-relay 调 sidecar 报 502 | shell 有 `HTTP_PROXY` env，被代理把本机流量也转出去 | 启动前 `unset HTTP_PROXY HTTPS_PROXY` 或确认 relay 内部 `trust_env=False` 生效 |
| cloudflared 报 `Error unmarshaling QuickTunnel response: 1101` | 同上，代理改坏了 cf API 响应 | `unset HTTP_PROXY HTTPS_PROXY` 再起 cloudflared |
| ai-relay 文本返回空 content | Qwen3 系列默认开 thinking，回答在 `reasoning_content` 里 | relay 已有 `enable_thinking=False` + `normalize_response()` 兜底，正常不会发生 |
| ai-relay 图片接口返 415 | 客户端上传 `application/octet-stream` 且文件名无后缀 | 客户端补 `.jpg` 文件名即可，或在 multipart 里显式 `content_type=image/jpeg` |
| picture-check 启动报 `--api-key required` | `.env` 里 `BIC_API_KEY` 没改 | 填真实凭证 |
| picture-check 返 `error_code=110` | 百度 access_token 失效 | 进程会自动重试；持续失败检查 `BIC_API_KEY/SECRET_KEY` 是否被吊销 |
| share-service 启动报 `SHARE_HMAC_KEY env var is required` | `.env` 未 source 或字段未填 | `set -a && source .env && set +a` 后再启动 |
| share-service 调 `/api/share/create` 返 401 | dev 模式没开 | `.env` 里 `ALLOW_DEV_UID_HEADER=1`，或带真实 JWT |
| sensitive-filter 加载 0 词 | `SF_WORDS_FILE` 路径错 | 确认指向 `sensitive-filter/data/sensitive_words.txt` 绝对路径 |
| share-service 测试报 import 错 | 在 `share_service/` 目录而非 `share-service/` 里跑 uvicorn | 一定要在 `share_service` 包的**父目录**（即 `share-service/`）执行 |

---

# 八、生产化清单（上线前必做）

- [ ] 所有 `.env` 占位值替换成生产凭证，重新生成 `SHARE_HMAC_KEY`
- [ ] `ALLOW_DEV_UID_HEADER=0`，关掉 X-Dev-Uid 旁路
- [ ] `share-service/share_service/core/auth.py` 接 AGC 公钥真校验
- [ ] `share-service/share_service/core/storage.py` 接 AGC 对象存储 SDK
- [ ] `CORS_ORIGINS` 收紧到只允许 H5 viewer 的 production 域名
- [ ] 给所有 4 个服务的鉴权 token 限流加严（默认 30/min）
- [ ] cloudflared quick tunnel → named tunnel（域名固定 / TLS 证书）
- [ ] share-service `purge_expired` 加 cron
- [ ] `logs/` 目录配 logrotate
- [ ] `.env` 文件权限 `chmod 600`
