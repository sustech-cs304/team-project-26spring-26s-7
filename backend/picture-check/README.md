# picture-check — :9200

百度云内容审核服务的 RESTful 包装层，包含**图片审核**和**文本审核**两类接口。
完全独立于 AI/敏感词/分享服务，无 GPU 依赖。

## 干什么

| Method | Path | Body 类型 | 说明 |
|---|---|---|---|
| GET | `/health` | — | 存活探针 + Baidu token 缓存状态 |
| POST | `/check` | multipart/form-data | 上传图片文件（base64 编码后发送） |
| POST | `/check_url` | JSON | 通过 URL 审核图片 |
| POST | `/text_check` | JSON | 文本审核（最长 20000 字节） |

返回字段 `conclusionType`：1=合规、2=不合规、3=疑似、4=审核失败；
配套布尔 `is_safe` / `is_hit`。

`rest2.0solutionv1img_censorv2user_defined.py` / `rest2.0solutionv1text_censorv2user_defined.py`
是百度官方裸调用脚本，仅作参考样例。

## 依赖

- Python 3.10+
- 见 [requirements.txt](requirements.txt)
- **百度智能云 API Key / Secret Key**（必填）—— 控制台 → 内容审核 → 应用列表

## 环境变量

| Env Var | 默认 | 说明 |
|---|---|---|
| `BIC_API_KEY` | **必填** | 百度 API Key |
| `BIC_SECRET_KEY` | **必填** | 百度 Secret Key |
| `BIC_HOST` | `0.0.0.0` | 监听地址 |
| `BIC_PORT` | `9200` | 监听端口 |
| `BIC_API_KEYS` | 空=开放 | 客户端 Bearer token 白名单 |
| `BIC_RATE_LIMIT` | `30/minute` | 每 IP 限流（slowapi 语法） |
| `BIC_LOG_DIR` | `/data2/cse12310817/logs` | 日志目录 |

也可改用 CLI flag：`--api-key`、`--secret-key`、`--host`、`--port`。
**推荐 env**，避免 `ps aux` 泄漏。

## 启动（独立）

```bash
export BIC_API_KEY=xxx
export BIC_SECRET_KEY=yyy
python baidu_image_censor.py
```

或参见根目录 [`start_all.sh`](../start_all.sh)。

## 验证

```bash
curl http://127.0.0.1:9200/health
# {"status":"ok","token_cached":true,"token_expires_at":...}

curl -X POST http://127.0.0.1:9200/text_check \
  -H "Content-Type: application/json" \
  -d '{"text":"测试文本"}'
```

## 注意事项

- 百度 access_token 有效期约 30 天；服务启动时获取 + 提前 2h 自动刷新
- 图片上传上限 10MB（百度本身限 4MB base64，本服务留余量）
- 文本审核上限 20000 字节（约 6666 个中文字符）
