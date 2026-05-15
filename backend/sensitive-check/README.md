# Picture Check 审核服务部署说明

这是个人主页头像、名称、个性签名审核服务。生产环境域名：

```text
https://audit.itsmappin.top
```

服务器目标目录：

```text
/home/26s-7/picture-check
```

## 1. 认证架构

生产环境不再接受写死在 APP 里的 dev token。

当前流程：

1. APP 使用华为 Account Kit 登录，拿到 `authorizationCode`。
2. APP 请求 `POST /api/v1/auth/huawei_login`，把 `authorizationCode` 发给本服务。
3. 服务端读取 AGC API Client JSON 里的 `client_id` 和 `client_secret`。
4. 服务端向华为 OAuth token endpoint 换取 `id_token`，确认登录用户身份。
5. 服务端签发自己的 APP session token。
6. APP 使用 APP session token 请求 `POST /api/v1/auth/issue_audit_token`。
7. 服务端签发短期审核 token。
8. APP 调用 `/check`、`/check_url`、`/text_check` 时只携带短期审核 token。

这样做的目的：

- 百度审核密钥只保存在服务器。
- AGC client secret 只保存在服务器。
- APP 包里不再包含长期有效的审核 token。
- 审核 token 有有效期，泄露后的影响范围更小。

## 2. 目录准备

把整个 `backend/picture-check` 目录复制到服务器：

```bash
/home/26s-7/picture-check
```

最终建议目录结构：

```text
/home/26s-7/picture-check
├── baidu_image_censor.py
├── requirements.txt
├── .env.production
├── secure/
│   └── agc-apiclient.json
├── logs/
├── deploy/
│   ├── Caddyfile
│   ├── install-production.sh
│   ├── picture-check.service
│   └── start-production.sh
└── .venv/
```

创建安全目录并放入 AGC JSON：

```bash
cd /home/26s-7/picture-check
mkdir -p secure logs
chmod 700 secure
chmod 755 logs
```

把你从 AGC 下载的 JSON 放到：

```text
/home/26s-7/picture-check/secure/agc-apiclient.json
```

然后设置权限：

```bash
chmod 600 /home/26s-7/picture-check/secure/agc-apiclient.json
```

## 3. 环境变量

复制模板：

```bash
cd /home/26s-7/picture-check
cp .env.production.example .env.production
chmod 600 .env.production
```

生成两个随机密钥：

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(48))"
python3 -c "import secrets; print(secrets.token_urlsafe(48))"
```

编辑 `.env.production`：

```bash
nano /home/26s-7/picture-check/.env.production
```

需要填写：

```env
APP_SESSION_SECRET=第一段随机密钥
BIC_AUDIT_TOKEN_SECRET=第二段随机密钥
BIC_API_KEY=你的百度审核 API Key
BIC_SECRET_KEY=你的百度审核 Secret Key
```

如果华为 OAuth 换 token 时返回 redirect URI 相关错误，再配置：

```env
HUAWEI_REDIRECT_URI=你在华为后台配置的 redirect_uri
```

不要再配置旧版静态 dev token 相关变量；生产环境只使用华为登录换取的 APP session token 和短期审核 token。

## 4. 安装依赖

```bash
cd /home/26s-7/picture-check
chmod +x deploy/*.sh
./deploy/install-production.sh
```

## 5. 手动启动测试

```bash
cd /home/26s-7/picture-check
chmod +x deploy/start-production.sh
./deploy/start-production.sh
```

服务会监听：

```text
127.0.0.1:9200
```

本机检查：

```bash
curl http://127.0.0.1:9200/health
```

## 6. systemd 生产启动

如果系统用户名不是 `26s-7`，先修改：

```bash
nano /home/26s-7/picture-check/deploy/picture-check.service
```

把：

```ini
User=26s-7
```

改成实际运行服务的 Linux 用户名。

复制服务文件：

```bash
sudo cp /home/26s-7/picture-check/deploy/picture-check.service /etc/systemd/system/picture-check.service
sudo systemctl daemon-reload
sudo systemctl enable --now picture-check
```

查看状态：

```bash
sudo systemctl status picture-check
```

查看日志：

```bash
sudo journalctl -u picture-check -f
```

重启：

```bash
sudo systemctl restart picture-check
```

## 7. Caddy HTTPS 反向代理

如果服务器使用 Caddy，把 `deploy/Caddyfile` 中的配置合并到你的 Caddy 配置里：

```caddy
audit.itsmappin.top {
    reverse_proxy 127.0.0.1:9200
}
```

重载：

```bash
sudo systemctl reload caddy
```

公网检查：

```bash
curl https://audit.itsmappin.top/health
```

## 8. 华为云安全组

生产环境建议：

- 开放 `80`：给 Caddy 申请/续期 HTTPS 证书。
- 开放 `443`：APP 访问 `https://audit.itsmappin.top`。
- 不要向公网开放 `9200`。

`9200` 只应该监听 `127.0.0.1`，由 Caddy 反代访问。

## 9. API

### `POST /api/v1/auth/huawei_login`

请求：

```json
{
  "authorization_code": "..."
}
```

响应：

```json
{
  "token_type": "Bearer",
  "app_session_token": "...",
  "issued_at": 1710000000,
  "expires_in": 604800,
  "uid": "..."
}
```

### `POST /api/v1/auth/issue_audit_token`

请求头：

```http
Authorization: Bearer <app_session_token>
```

响应：

```json
{
  "token_type": "Bearer",
  "filter_token": "...",
  "censor_token": "...",
  "issued_at": 1710000000,
  "expires_in": 1800
}
```

### `POST /check`

```bash
curl -X POST https://audit.itsmappin.top/check \
  -H "Authorization: Bearer <audit-token>" \
  -F "image=@/path/to/image.jpg" \
  -F "img_type=0"
```

### `POST /text_check`

```bash
curl -X POST https://audit.itsmappin.top/text_check \
  -H "Authorization: Bearer <audit-token>" \
  -H "Content-Type: application/json" \
  -d '{"text":"需要审核的文本"}'
```

## 10. 上线前检查

```bash
cd /home/26s-7/picture-check
python3 -m py_compile baidu_image_censor.py
curl http://127.0.0.1:9200/health
curl https://audit.itsmappin.top/health
```

无 token 调用审核接口应该失败：

```bash
curl -X POST https://audit.itsmappin.top/text_check \
  -H "Content-Type: application/json" \
  -d '{"text":"test"}'
```

预期结果是 `401 Unauthorized`。
