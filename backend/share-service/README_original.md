# share_service

TravelPin 临时分享链接后端 — 本地原型阶段实现（FastAPI + SQLite）。
对应交接文档 P08 §七.1。AGC 迁移路径见同文档 §七.2 / 附录 B。

## 5 分钟跑起来

```bash
cd /data2/cse12310817/backend

# 1) 建 venv，装依赖
python3 -m venv .venv
source .venv/bin/activate
pip install -r share_service/requirements.txt

# 2) 配环境变量
cp share_service/.env.example share_service/.env
# 把 SHARE_HMAC_KEY 替换成真实 32 字节随机串：
#   python -c "import secrets;print(secrets.token_urlsafe(32))"
# 演示阶段开 dev 头：
echo "ALLOW_DEV_UID_HEADER=1" >> share_service/.env

# 3) 启动（端口 8001，避开 8000 上的 AI 服务）
set -a && source share_service/.env && set +a
uvicorn share_service.main:app --host 0.0.0.0 --port 8001 --reload
```

健康检查：

```bash
curl http://127.0.0.1:8001/health
# {"ok":true}
```

## 跑测试

```bash
cd /data2/cse12310817/backend
source .venv/bin/activate
pytest share_service/tests/ -v
```

## API 速查

详见交接文档 §五。

| Method | Path | 鉴权 | 说明 |
|---|---|---|---|
| POST | `/api/share/create` | Bearer | 创建分享链接，返回 `{shortCode, sig, url, expireAt}` |
| GET  | `/api/share/{code}.{sig}` | 公开 | 查看快照 + 照片签名 URL，自动 +1 viewCount |
| POST | `/api/share/{code}/revoke` | Bearer | 撤销自己的链接（idempotent） |
| GET  | `/api/share/mine` | Bearer | 列出自己最近 50 条（不含 snapshot） |
| GET  | `/health` | 公开 | 存活探针 |

## 用 curl 走一遍完整链路

> 演示模式（`ALLOW_DEV_UID_HEADER=1`）下用 `X-Dev-Uid` 替代真实 AGC token：

```bash
BASE=http://127.0.0.1:8001

# 创建
RESP=$(curl -sX POST $BASE/api/share/create \
  -H "X-Dev-Uid: alice" \
  -H "Content-Type: application/json" \
  -d '{
    "tripCloudId": "trip-demo-1",
    "expireDays": 7,
    "snapshot": {"v":1,"trip":{"name":"Demo Trip"},"nodes":[]},
    "photoManifest": ["users/alice/travels/1/nodes/1/p.jpg"],
    "consentVersion": "share-v1"
  }')
echo "$RESP"

CODE=$(echo "$RESP" | python -c 'import json,sys;print(json.load(sys.stdin)["shortCode"])')
SIG=$(echo "$RESP"  | python -c 'import json,sys;print(json.load(sys.stdin)["sig"])')

# 公开访问
curl -s "$BASE/api/share/$CODE.$SIG" | python -m json.tool

# 我的列表
curl -s "$BASE/api/share/mine" -H "X-Dev-Uid: alice" | python -m json.tool

# 撤销
curl -sX POST "$BASE/api/share/$CODE/revoke" -H "X-Dev-Uid: alice"

# 撤销后再访问 → 404
curl -s "$BASE/api/share/$CODE.$SIG"
```

## 运行清扫脚本（本地 cron）

```bash
cd /data2/cse12310817/backend
source .venv/bin/activate
set -a && source share_service/.env && set +a
python -m share_service.scripts.purge_expired
```

加到 crontab，每天凌晨 3 点跑：

```cron
0 3 * * * cd /data2/cse12310817/backend && /data2/cse12310817/backend/.venv/bin/python -m share_service.scripts.purge_expired >> /var/log/share_purge.log 2>&1
```

## 演示阶段的 mock 行为

文档 §七.1 列了哪些是适配层、哪些是业务核心。本仓库**业务核心已完整**，
**适配层目前是 mock**：

| 模块 | 现状 | 上线前替换为 |
|---|---|---|
| `core/auth.py` | JWT body 解码（无签名校验） + `X-Dev-Uid` 头逃生口 | AGC 公钥校验，或迁到 Cloud Function 后用 `context.uid` |
| `core/storage.py` | 拼一个 `https://mock-storage.../{key}?ttl=...` 假 URL | `agconnect.cloudStorage.getDownloadURL(key, ttl)` |
| `db/repository.py` | SQLite | AGC Cloud Database `ObjectTypeInfo` |

业务核心（`core/security.py` HMAC、`routers/share.py` 校验顺序、限流、
跨用户防御、size guard）整套不动。

## 上线前清单

- [ ] 重置 `SHARE_HMAC_KEY` 为生产强随机值，从 AGC 控制台环境变量注入
- [ ] `ALLOW_DEV_UID_HEADER` 必须为 `0`（默认就是）
- [ ] `core/auth.py` 接 AGC 真实校验
- [ ] `core/storage.py` 接 AGC SDK
- [ ] `CORS_ORIGINS` 收紧到只剩 H5 viewer 的 production 域名
- [ ] HTTPS（AGC Hosting / 反代）
- [ ] 配过期清扫定时任务
