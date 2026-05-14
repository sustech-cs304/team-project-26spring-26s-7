# AppGallery 上架检查清单

> 创建日期：2026-05-09
> 项目：TravelPin (com.ran.login_test)
> 范围：team-project-26spring-26s-7（前端） + Qwen-VL / picture-check / backend / ai-service（后端）

按"**可直接修改 + 不花钱 + 不影响调试**"→"**配置改造**"→"**外部依赖/换证书**"三档排序。

---

## 协议合规问题速查

| ID | 文件 | 问题 |
|---|---|---|
| P1 | privacy_policy.html / user_agreement.html | `class="placeholder"` 占位符（邮箱、主体、地址、生效日期）需替换为真实信息 |
| P2 | privacy_policy.html §4 | 第三方清单缺百度智能云图像审核（picture-check 实际接入） |
| P3 | privacy_policy.html §4 | 缺自建敏感词过滤服务说明 |
| P4 | privacy_policy.html | 缺华为 SDK 清单（Map Kit / Push Kit / Account Kit / Safety Detect / AGConnect Cloud DB & Storage）及各方隐私政策链接 |
| P5 | privacy_policy.html | 缺"个人信息存储于中华人民共和国境内，不进行跨境传输"声明 |
| P6 | privacy_policy.html §9 | 缺工信部 12321 / 网信办 12377 投诉举报渠道 |
| P7 | user_agreement.html §9 | 主体、邮箱占位符未替换 |
| P8 | user_agreement.html | 缺 UGC 内容被审核拦截后的申诉机制 |

---

## 🟢 第 1 档 · 可直接修改、零成本、不影响调试

### 1.1 修协议（P1-P8）
- [ ] 替换两个 HTML 中所有 `class="placeholder"` 占位符（主体、邮箱、地址、生效日期）
- [ ] 隐私政策 §4 共享表格补 2 行：百度图片审核、自建敏感词过滤
- [ ] 隐私政策补 SDK 清单章节
- [ ] 加"信息存储于中国境内不出境"声明
- [ ] §9 加 12321 / 12377 投诉渠道
- [ ] 用户协议补 UGC 申诉机制

### 1.2 删除前端代码内网泄露
- [ ] `VisionLLMPage.ets` UI 中删除 `Text('API 端点: http://172.18.35.215:8000/...')`
- [ ] `ApiEndpoints.ets:36` 注释删除 `LAN 直连地址：http://172.18.35.215:8000`
- [ ] grep 全工程其它残留 `172.18.` / `localhost` / `127.0.0.1` 字符串

### 1.3 清理日志泄露
- [ ] 删除 `console.log('VisionLLMPage loaded')` 等调试语句
- [ ] `obfuscation-rules.txt` 末尾追加 `-remove-log`

### 1.4 后端凭证移到环境变量（保留 fallback）
- [ ] `picture-check/baidu_image_censor.py:179-183` 的 `--api-key` / `--secret-key` 改读 `BAIDU_API_KEY` / `BAIDU_SECRET_KEY`
- [ ] `ai-service/openai_api.py:843` 的 `--api-keys` 改读 `AI_SERVICE_API_KEYS`
- [ ] 写入 `~/.env` 或 systemd EnvironmentFile，启动脚本 source

### 1.5 后端稳定性补丁
- [ ] picture-check 加上传文件大小限制（10MB，413）
- [ ] share_service `main.py:21-27` CORS 去除 `or ["*"]` 隐式回退
- [ ] `baidu_image_censor.py:48-60` token 提前刷新 1h → 2h
- [ ] 四个服务 logging 统一改 `RotatingFileHandler(maxBytes=50MB, backupCount=5)`
- [ ] `sensitive_filter_service.py` 命中分支加审计日志（uid_hash + 命中词 + ts）

### 1.6 国际化资源补充
- [ ] `resources/zh_CN/element/string.json` 显式新建（华为审核检查）

### 1.7 注销 / 导出功能核实
- [x] 注销已在 `AuthService.deleteAccount()` 实现，`ProfileView` 有入口（已确认）
- [ ] 数据导出（可选，后续）

---

## 🟡 第 2 档 · 需要少量改造，仍不花钱

### 2.1 后端鉴权统一
- [ ] picture-check 加 `Authorization: Bearer xxx` 中间件
- [ ] sensitive_filter_service 同上
- [ ] 引入 `slowapi` rate limit（30 req/min/ip）

### 2.2 前端 Token 改运行时获取
- [ ] share_service 加 `/auth/issue_ai_token` 接口
- [ ] `ApiEndpoints.ets:46` 的 `VISION_LLM_AUTH_TOKEN` 改成动态获取
- [ ] release 包彻底拿掉硬编码 dev token

### 2.3 JWT 真实验签（迁移到 AGC ID-token JWKS）
- [ ] `share_service/core/auth.py:_decode_jwt_unverified` 改 RS256 + 华为 JWKS
- [ ] 至少先校验 `iss` / `aud` / `exp` 三个 claim
- [ ] `ALLOW_DEV_UID_HEADER` 用环境变量严格守卫

### 2.4 release 签名分离（影响构建流程，但本身零成本）
- [ ] `build-profile.json5` 加 `signingConfigs.release`，使用 `release_testRelease.p7b`
- [ ] 密码移到 `local.properties`（已 .gitignore）
- [ ] debug 配置保留原样

### 2.5 资源瘦身
- [ ] 评估 `resources/base/media/photo_*.jpg`（7.2MB）是否上架版本必需

---

## 🔴 第 3 档 · 影响调试 / 需要外部资源

### 3.1 HTTPS 反代上线
- [ ] 申请正式域名（约 ¥55/年）+ Let's Encrypt 证书 + nginx 反代（推荐）
- [ ] 备选：cloudflared named tunnel 固定子域
- [ ] 前端两个 `http://172.18.35.215:9100/9200` 切到 `https://正式域名`
- [ ] 保留 dev/prod 双套配置

### 3.2 替换 release 证书 & AGC 配置
- [ ] AGC 控制台申请正式发布证书 + Profile
- [ ] AGC 后台开通 Push Kit / Map Kit / Account Kit / Safety Detect
- [ ] 验证 `agconnect-services.json` 是 release 项目而非测试项目

### 3.3 上架材料（非代码）
- [ ] 软件著作权登记证（AI 类应用建议提前 1-2 周加急）
- [ ] ICP 备案号（后端在中国大陆需备案）
- [ ] 应用截图：手机 / 平板 / 折叠屏 各 3-5 张
- [ ] 宣传图、应用图标 1024×1024 PNG
- [ ] 版本说明文案
- [ ] HarmonyOS NEXT 适配测试报告

---

## 推荐执行节奏

| 时间 | 内容 |
|---|---|
| 今天 | 1.1（协议）+ 1.2（删 IP）+ 1.3（清日志） |
| 本周内 | 1.4-1.7 全部完成 |
| 下周 | 第 2 档（鉴权 + 动态 token + JWT 验签 + 签名分离） |
| 上架前 1-2 周 | 第 3 档（域名 + 证书 + 上架材料） |
