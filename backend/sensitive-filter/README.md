# sensitive-filter — :9100

纯字符串敏感词检测 HTTP 服务，与 AI/分享服务完全解耦。
41887 词的 trie + 白名单 + 单字过滤；fail-open 调用方便（断了不会瘫整条链路）。

## 干什么

| Method | Path | 说明 |
|---|---|---|
| GET | `/health` | 存活探针 + 词表加载统计 |
| POST | `/check` | `{text}` → `{blocked, hit, hits_count}` 单条检测 |
| POST | `/mask` | `{text, mask?}` → `{masked, hits[], hits_count}` 命中片段打码 |
| POST | `/batch_check` | `{texts[]}` → `{results: CheckOut[]}` 批量 |

可选 `X-User-Uid` 头，命中时记审计日志（SHA256 截断脱敏）。

## 依赖

- Python 3.10+
- 见 [requirements.txt](requirements.txt)
- 词表文件 [`data/sensitive_words.txt`](data/sensitive_words.txt)（41887 词）
- 白名单 [`data/whitelist.txt`](data/whitelist.txt)（被误收的常见无害词）

## 环境变量

| Env Var | 默认 | 说明 |
|---|---|---|
| `SF_HOST` | `0.0.0.0` | 监听地址。`0.0.0.0` 校园网内任意机器可直连 |
| `SF_PORT` | `9100` | 监听端口 |
| `SF_WORDS_FILE` | `/data2/cse12310817/sensitive_words.txt` | **务必改成本仓库下的 `data/sensitive_words.txt` 绝对路径** |
| `SF_WHITELIST_FILE` | `/data2/cse12310817/whitelist.txt` | 同上，改成 `data/whitelist.txt` 绝对路径 |
| `SF_ALLOW_SINGLE_CHAR` | `0` | 允许单字命中？默认禁（避免"日""杀"等大量误伤） |
| `SF_LOG_DIR` | `/data2/cse12310817/logs` | 日志目录（自动创建） |
| `SENSITIVE_API_KEYS` | 空=开放 | 逗号分隔的 Bearer token 白名单；空 = dev 开放模式 |
| `SENSITIVE_RATE_LIMIT` | `60/minute` | 每 IP 限流（slowapi 语法） |

## 启动（独立）

```bash
export SF_WORDS_FILE="$PWD/data/sensitive_words.txt"
export SF_WHITELIST_FILE="$PWD/data/whitelist.txt"
python sensitive_filter_service.py
```

或参见根目录 [`start_all.sh`](../start_all.sh)。

## 验证

```bash
curl http://127.0.0.1:9100/health
# {"status":"ok","words_loaded":41887,...}

curl -s http://127.0.0.1:9100/check \
  -H "Content-Type: application/json" \
  -d '{"text":"今天天气真好"}'
# {"blocked":false,"hit":null,"hits_count":0}
```

## 改词表后怎么办

服务**不会自动 reload**。需要 kill 进程 + 重启：

```bash
pkill -f sensitive_filter_service.py
# 重新执行启动命令
```
