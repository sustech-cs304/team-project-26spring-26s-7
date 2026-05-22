# ai-relay — :8000

OpenAI 兼容协议的 thin proxy，把客户端请求转发到 **SiliconFlow Cloud**（硅基流动）。
对外接口与原本地 Qwen-VL-Chat-Int4 推理服务保持一致，所以客户端代码完全不用动。

## 干什么

- `POST /v1/chat/completions` —— 纯文本聊天，后端模型 `Qwen/Qwen3.5-4B`（自动 `enable_thinking=False`）
- `POST /v1/chat/completions/image` —— 图片 + 提示词，后端模型 `Qwen/Qwen3-VL-8B-Instruct`
- `GET /health` / `GET /v1/models` —— 健康检查 / 模型列表

进程内处理：Bearer 鉴权、每 key 限流、输入敏感词预检、输出敏感词打码。

## 依赖

- Python 3.10+
- 见 [requirements.txt](requirements.txt)
- **sensitive-filter 服务**（默认 `http://127.0.0.1:9100`），用于输入/输出敏感词检查。
  调用失败时 fail-open（放行），但应保证它先启动以避免漏检。
- **SiliconFlow API key**（必填）：在 https://cloud.siliconflow.cn/account/ak 申请

## 必需的 CLI 参数

| 参数 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `--siliconflow-key` | 是 | — | SF API key；或用 `SF_KEY` 环境变量代替 |
| `--server-host` | 否 | `127.0.0.1` | 监听地址。**保持本机绑定**，公网通过 cloudflared 暴露 |
| `--server-port` | 否 | `8002`（但本项目用 `8000`）| 监听端口 |
| `--api-keys` | 否 | 空=开放 | 逗号分隔的客户端 Bearer token 白名单 |
| `--rate-limit-per-min` | 否 | `30` | 每 token 限流 |
| `--max-question-chars` | 否 | `3000` | 单条 user 消息最大字符数 |
| `--sensitive-filter-url` | 否 | `http://127.0.0.1:9100` | sensitive-filter 服务地址 |
| `--text-model` | 否 | `Qwen/Qwen3.5-4B` | 文本模型 ID（SF 端） |
| `--vision-model` | 否 | `Qwen/Qwen3-VL-8B-Instruct` | 多模态模型 ID（SF 端） |
| `--siliconflow-base` | 否 | `https://api.siliconflow.cn/v1` | SF 上游 base URL |
| `--http-timeout` | 否 | `60` | 上游请求超时（秒） |

## 启动（独立）

```bash
python siliconflow_relay.py \
  --server-host 127.0.0.1 \
  --server-port 8000 \
  --api-keys "$AI_SERVICE_API_KEYS" \
  --rate-limit-per-min 30 \
  --siliconflow-key "$SF_KEY" \
  --sensitive-filter-url http://127.0.0.1:9100
```

或参见根目录 [`start_all.sh`](../start_all.sh) 统一拉起所有服务。

## 网络/代理坑（看完再启动）

1. 用户 shell 通常设了 `HTTP_PROXY=http://127.0.0.1:17890`（出墙用），
   relay 内部已分两个 httpx client 处理：调本机 sensitive-filter 时
   `trust_env=False`，调 SF API 时走 env 代理。无需特殊处理。
2. **启动 cloudflared 暴露 :8000 时反而要 `unset HTTP_PROXY HTTPS_PROXY`**，
   否则申请 quick tunnel 时会被代理把 cloudflare API 响应改坏，报
   `Error unmarshaling QuickTunnel response: 1101`。
