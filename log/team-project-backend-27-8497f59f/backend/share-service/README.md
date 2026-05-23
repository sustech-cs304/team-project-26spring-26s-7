# share-service — :8001

TravelPin 临时分享链接 + 发布（publish）后端。FastAPI + SQLite 本地原型。

代码原封不动从 `/data2/cse12310817/backend/share_service/` 复制过来；
保留了原始 `README.md` → 见 [`README_original.md`](README_original.md)。

## 启动

```bash
# 在 share-service/ 目录下
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 写好环境变量（拷贝 .env.example 改）
cp .env.example .env
# 至少要填 SHARE_HMAC_KEY 和 CORS_ORIGINS
#   python -c "import secrets;print(secrets.token_urlsafe(32))"

set -a && source .env && set +a
uvicorn share_service.main:app --host 127.0.0.1 --port 8001
```

> 注意：`uvicorn` 必须从 `share-service/`（即 `share_service/` 包的父目录）
> 运行，否则会找不到 `share_service.main` 模块。

数据库：首次启动会在 `DB_PATH`（默认 `./share.db`）自动建表。

## 必填环境变量

| Var | 说明 |
|---|---|
| `SHARE_HMAC_KEY` | 32 字节随机串。`python -c "import secrets;print(secrets.token_urlsafe(32))"` |
| `CORS_ORIGINS` | 逗号分隔；本地放开就 `*` |

其余可选：见 [.env.example](.env.example) 注释。

## 主要端点

| Method | Path | 鉴权 | 说明 |
|---|---|---|---|
| POST | `/api/share/create` | Bearer | 创建分享链接 |
| GET | `/api/share/{code}.{sig}` | 公开 | 查看快照 + 自增 viewCount |
| POST | `/api/share/{code}/revoke` | Bearer | 撤销 |
| GET | `/api/share/mine` | Bearer | 我的分享列表 |
| POST | `/api/publish/...` | Bearer | 发布相关（详见 `routers/publish.py`） |
| GET | `/health` | 公开 | `{ok: true}` |

完整路由详见 `share_service/routers/`。

## 跑测试

```bash
source .venv/bin/activate
pytest share_service/tests/ -v
```

## 演示模式

`ALLOW_DEV_UID_HEADER=1` 时，可用 `X-Dev-Uid: alice` 头替代真实 AGC JWT，
方便 curl 调试。**生产环境必须设为 `0`**。
