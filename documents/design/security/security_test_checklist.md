# TravelPin 安全测试清单

> 对应脚本: `scripts/security_audit.sh`
> 参考文档: HarmonyOS NEXT 安全技术白皮书 V1.0 (2024-08-13)
> 生成日期: 2026-05-17

## 总览

| 类别 | 测试项 | 自动化 | 对应白皮书章节 |
|------|--------|--------|---------------|
| A. 权限最小化 | A1-A4 | 全自动 | 7.4 纯净权限 |
| B. 数据存储安全 | B1-B5 | 全自动 | 6.1-6.2 数据分级与加密 |
| C. 网络通信安全 | C1-C4 | 全自动 | 6.3 数据传输安全 |
| D. 身份认证安全 | D1-D5 | 全自动 | 4.1-4.3 身份管理与认证 |
| E. 隐私合规 | E1-E4 | 全自动 | 7.3-7.4 隐私访问可知可控 |
| F. 照片与 EXIF 安全 | F1-F4 | 全自动 | 6.1 数据分级 S3 |
| G. 内容审查 | G1-G3 | 全自动 | 7.3 纯净上架 |
| H. 敏感信息泄露 | H1-H4 | 全自动 | 7.2 纯净开发 |

---

## A. 权限最小化 (7.4 纯净权限)

HarmonyOS AppGallery 要求应用仅申请业务必需的最小权限集合，位置等敏感权限必须限定使用场景。

### A1: 权限数量检查

- **文件**: `frontend/entry/src/main/module.json5` → `requestPermissions`
- **预期**: 恰好声明 4 项权限（LOCATION, APPROXIMATELY_LOCATION, INTERNET, GET_NETWORK_INFO）
- **通过**: `perm_count == 4`
- **失败**: 多余权限可能被审核驳回

### A2: 位置权限作用域

- **文件**: `module.json5` → LOCATION 权限的 `usedScene.when`
- **预期**: `"when": "inuse"` — 仅前台使用
- **通过**: 不包含 `"when": "always"`（后台定位需要额外审批）

### A3: 无危险权限

- **文件**: `module.json5`
- **预期**: 不包含 SMS、电话、通讯录、相机、麦克风等系统级危险权限
- **通过**: 不匹配以下任一: READ_CONTACTS, CALL_PHONE, SEND_SMS, CAMERA, MICROPHONE 等

### A4: System Picker 使用

- **文件**: 源码中 PhotoPicker 相关引用
- **预期**: 照片选择使用 `PhotoViewPicker`（系统选择器）而非直接图库权限
- **通过**: 至少 1 处引用 PhotoViewPicker / PhotoSelectOptions

---

## B. 数据存储安全 (6.1-6.2)

HarmonyOS 要求数据按分级存储，S3 以上数据必须加密。

### B1: 数据库加密等级

- **文件**: `common/data/RdbHelper.ets`
- **预期**: `SecurityLevel.S2` — 数据存储在通用加密区
- **通过**: 源码包含 `SecurityLevel.S2`

### B2: Session Token 存储方式

- **文件**: `common/auth/AppSessionManager.ets`
- **预期**: 使用 HarmonyOS `preferences` API（应用沙箱加密存储）
- **通过**: 至少 1 处 `preferences.` 调用用于 token 管理

### B3: 用户数据隔离

- **文件**: `common/data/RdbHelper.ets`, `TravelRepository.ets`, `MemoryNodeRepository.ets`
- **预期**: 所有查询使用 `owner_uid` 过滤，防止跨用户数据泄露
- **通过**: 至少 5 处 `owner_uid` 引用

### B4: 临时文件清理

- **文件**: `feature/social-share/services/SharePhotoHelper.ets`, `common/utils/ImageSanitizer.ets`
- **预期**: EXIF 清洗产物在 `finally` 块中清理，避免崩溃后残留
- **通过**: 存在 `cleanupTemporaryPhotos` / `deleteSanitized` / `purgeAll` 调用

### B5: 账号注销数据清理

- **文件**: `common/auth/AuthService.ets`
- **预期**: 账号注销时完整清理: 云 DB → 云存储 → 本地 DB → 同意状态
- **通过**: 至少 2 处清理函数引用 (`wipeAllUserData`, `deleteUserFromCloud`, `clearAllConsent`)

---

## C. 网络通信安全 (6.3)

HarmonyOS 默认禁止明文 HTTP，应用需确保所有通信走 HTTPS。

### C1: 无明文 HTTP 端点

- **范围**: 所有 `.ets` 文件
- **预期**: 不包含 `http://` API 端点（排除 license 头和 xmlns 命名空间）
- **通过**: grep 结果为 0

### C2: HTTPS 端点确认

- **文件**: `common/api/ApiEndpoints.ets`
- **预期**: 所有 API 基础 URL 使用 `https://`
- **通过**: 至少 1 处 `https://` API 端点声明

### C3: Bearer Token 认证

- **文件**: `common/api/HttpClient.ets`, 各 Service 文件
- **预期**: API 调用使用 `Bearer` token 认证
- **通过**: 至少 2 处 `Bearer ` 引用
- **注意**: `HttpClient.ets` 基类未统一注入 auth header，需人工确认各 Service 自行注入

### C4: TLS 证书固定

- **范围**: 所有 `.ets` 文件
- **预期**: 信息性检查 — 当前未实现证书固定
- **状态**: INFO 级别，不阻塞上架但建议生产环境考虑

---

## D. 身份认证安全 (4.1-4.3)

HarmonyOS 要求使用安全的认证协议，OAuth 2.0 需实现 state 参数防 CSRF。

### D1: OAuth State 参数验证

- **文件**: `common/auth/AuthService.ets`
- **预期**: 使用 `generateRandomUUID()` 生成 state，回调时验证 `response.state !== loginRequest.state`
- **通过**: 源码包含 state 比较逻辑

### D2: 签名算法

- **文件**: `common/auth/AuthService.ets`
- **预期**: 使用 `IdTokenSignAlgorithm.PS256`（RSA-PSS-SHA256）
- **通过**: 源码包含 `PS256`

### D3: Token TTL 与提前刷新

- **文件**: `common/api/AiTokenManager.ets`, `common/auth/AppSessionManager.ets`
- **预期**: Token 有过期时间，并在到期前 60 秒自动刷新
- **通过**: 包含 `expiry` / `TOKEN_LEEWAY` / 60s buffer 相关逻辑

### D4: Token 仅存内存

- **文件**: `common/api/AiTokenManager.ets`
- **预期**: AI 服务 token 仅缓存在内存变量中，不持久化到磁盘
- **通过**: 不存在 `token.*write` / `token.*save` / `persist.*token` 等持久化调用

### D5: 硬编码 DEV Token

- **文件**: `common/api/AiTokenManager.ets`
- **预期**: **不应存在** 硬编码的 `FALLBACK_DEV_TOKEN` 或类似开发绕过凭据
- **失败**: 发现 `DEV_` 前缀的硬编码 token — **上架前必须移除**

---

## E. 隐私合规 (7.3-7.4)

AppGallery 要求应用首次启动必须展示隐私政策，云功能需获取用户同意。

### E1: 首次启动隐私同意

- **文件**: `common/utils/ConsentManager.ets`, 页面路由逻辑
- **预期**: 首次启动检测 `hasAcceptedPrivacy`，未同意时拦截并展示隐私政策页
- **通过**: 至少 2 处隐私同意相关引用

### E2: 云功能 JIT 同意

- **文件**: `common/utils/ConsentManager.ets`
- **预期**: 触发云同步/上传前，弹窗请求云功能使用同意
- **通过**: 至少 2 处 cloud consent 相关引用

### E3: 隐私政策版本化

- **文件**: `common/utils/ConsentManager.ets`
- **预期**: 隐私政策有版本号，升级版本时强制重新获取同意
- **通过**: 包含 `POLICY_VERSION` / `privacyVersion` / `consent.*version`

### E4: 注销清除同意

- **文件**: `common/auth/AuthService.ets`, `common/utils/ConsentManager.ets`
- **预期**: 账号注销时调用 `clearAllConsent` 或等价方法
- **通过**: 至少 1 处同意清除引用

---

## F. 照片与 EXIF 安全 (6.1 S3)

用户照片属 S3 级个人多媒体数据，分享前必须剥离 EXIF（含 GPS 坐标）。

### F1: PixelMap 重编码

- **文件**: `common/utils/ImageSanitizer.ets`
- **预期**: 通过 `image.createImagePacker()` + `packing()` 重编码为 JPEG，自动剥离所有 EXIF
- **通过**: 包含 packing / PixelMap / createImagePacker 引用

### F2: 随机临时文件名

- **文件**: `common/utils/ImageSanitizer.ets`
- **预期**: 临时文件名格式为 `san_${timestamp}_${random}`，不暴露原始文件名
- **通过**: 包含 `san_` 前缀或 `randomUUID` 调用

### F3: 启动时清理残留

- **文件**: `common/utils/ImageSanitizer.ets`
- **预期**: 应用启动时调用 `purgeAll()` 清理上次崩溃未清理的临时文件
- **通过**: 包含 `purgeAll` 调用

### F4: 预检阻止清洗失败

- **文件**: `feature/social-share/services/SharePreflight.ets`
- **预期**: EXIF 清洗失败的图片被预检拦截，阻止发布
- **通过**: 包含 `SANITIZE_FAILED` / `PHOTO_SANITIZE` 错误码

---

## G. 内容审查 (7.3 纯净上架)

AppGallery 要求应用对用户生成内容进行合规性审查。

### G1: 用户文本审查

- **文件**: `common/api/ContentFilterService.ets` / `ImageCensorService.ets`
- **预期**: 用户昵称、签名等文本在保存前经过内容过滤服务审查
- **通过**: 包含 `ContentFilter` / `contentFilter` / `textCensor` 引用

### G2: 内容审查桩检查

- **文件**: `common/api/AiGatewayClient.ets` 或类似文件
- **预期**: 内容审查函数应调用真实审查 API，而非硬编码 `is_safe: true`
- **警告**: 如果发现硬编码安全结果，标记为 WARN — 需接通真实审查服务

### G3: 分享内容异步审查

- **文件**: 后端分享发布流程
- **预期**: 分享链接内容经过后端异步审查，命中敏感内容后下线
- **通过**: 包含 `audit` / `review` / `censor` / `sensitive` 相关逻辑

---

## H. 敏感信息泄露 (7.2 纯净开发)

应用代码不应包含硬编码凭据，日志不应输出敏感数据。

### H1: 硬编码密钥扫描

- **范围**: 所有 `.ets` 文件
- **预期**: 不包含 `api_key = "xxx"` / `apiSecret = "xxx"` 等硬编码凭据
- **通过**: grep 结果为 0
- **注意**: AGC SDK 的 `[!00...]` 加密格式凭据在 `agconnect-services.json` 中是正常设计

### H2: 日志无敏感数据

- **范围**: 所有 `.ets` 文件
- **预期**: `Logger.info()` / `Logger.error()` 调用不包含 password、token、secret 参数
- **通过**: 不匹配 `Logger.*password|Logger.*token|Logger.*secret`

### H3: AGC 凭据文件管理

- **文件**: `frontend/entry/src/main/resources/rawfile/agconnect-services.json`
- **预期**: 文件包含凭据但使用 AGC 加密信封格式；应检查 `.gitignore` 是否覆盖
- **通过**: 文件被 `.gitignore` 排除（不进入 git 历史）
- **失败**: 文件被 git 追踪（凭据在历史中可见）

### H4: 无第三方遥测

- **范围**: 所有 `.ets` 文件
- **预期**: 不集成 Bugly、Sentry、Firebase Analytics 等第三方数据收集 SDK
- **通过**: 不匹配 telemetry / analytics / Bugly / Sentry / Firebase

---

## 人工补充测试项

以下测试需要人工在设备/模拟器上验证：

1. **隐私政策页**: 首次启动 → 隐私政策弹窗 → 不同意无法继续
2. **权限说明**: 申请位置权限时，弹窗显示开发者填写的 `reason` 字段
3. **EXIF 验证**: 分享一张含 GPS 信息的照片 → 下载后检查 EXIF 已清除
4. **账号注销**: 执行账号注销 → 确认本地数据、云端数据、同意状态全部清除
5. **分享过期**: 发布一个 5 分钟有效期的分享 → 5 分钟后访问返回已过期
6. **内容审查**: 尝试设置违规昵称 → 确认被拦截

---

## 运行方式

```bash
# 自动化部分
cd project-root
bash scripts/security_audit.sh          # 普通输出
bash scripts/security_audit.sh --verbose # 详细输出（含 grep 匹配行）

# 查看日志
cat scripts/security_audit_log.txt
```
