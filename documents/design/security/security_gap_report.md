# TravelPin 安全缺口调查报告

> 生成日期: 2026-05-17
> 基于: HarmonyOS NEXT 安全技术白皮书 + 源码审计
> 分支: `feature/security-audit`

---

## 缺口总览

| # | 缺口 | 风险等级 | 阻塞上架 | 修复工作量 |
|---|------|---------|---------|-----------|
| 1 | 硬编码 DEV 回退 Token | HIGH | **是** | 小 |
| 2 | agconnect-services.json 凭据暴露 | CRITICAL | **是** | 中 |
| 3 | ShareService 无认证回退 | HIGH | **是** | 小 |
| 4 | HttpClient 未统一注入 Auth Header | MEDIUM | 否（潜在风险） | 中 |
| 5 | 无 TLS 证书固定 | MEDIUM | 否 | 中 |
| 6 | moderateContent 桩实现 | LOW (未调用) / HIGH (若调用) | 可能 | 极小 |

---

## GAP 1: 硬编码 DEV 回退 Token

**风险**: HIGH | **阻塞上架**: 是

### 位置

- 文件: `frontend/entry/src/main/ets/common/api/AiTokenManager.ets`
- Line 62: 常量声明
- Lines 141-146: `makeVisionFallback()` 工厂函数
- Lines 148-198: `fetchVisionToken()` 激活回退

### 问题代码

```typescript
// Line 62
const FALLBACK_DEV_TOKEN = 'DEV_05436de19d4ad0029b4d722b9288167b'

// Lines 141-146
function makeVisionFallback(): CachedVisionToken {
  return {
    token: FALLBACK_DEV_TOKEN,
    expiresAt: Math.floor(Date.now() / 1000) + 60
  }
}
```

### 激活条件

`fetchVisionToken()` 在以下三种情况回退到 DEV token:
1. 用户未登录 AGC 且 `refreshFromAgcAuth()` 返回 null → 立即回退
2. `issue_vision_token` HTTP 请求返回非 200/201 → 回退
3. 响应缺少 `vision_token` 字段或抛出异常 → 回退

对比: `fetchAuditTokens()` 和 `fetchShareToken()` 在无 session 时正确抛出异常，唯独 vision 路径静默回退。

### 攻击场景

1. 攻击者反编译 HAP（标准 ZIP + protobuf，可提取）
2. 提取 `DEV_05436de19d4ad0029b4d722b9288167b`
3. 直接调用 `https://audit.itsmappin.top:8443/v1/chat/completions/image`
4. 如后端有 dev bypass，获得无限免费 LLM API 访问

### 修复方案

```typescript
// 删除常量: const FALLBACK_DEV_TOKEN = ...
// 删除函数: makeVisionFallback()

// fetchVisionToken() 改为在无 session 时抛出异常:
async function fetchVisionToken(): Promise<CachedVisionToken> {
  let appSessionToken = await AppSessionManager.getToken()
  if (!appSessionToken) {
    appSessionToken = await AppSessionManager.refreshFromAgcAuth()
  }
  if (!appSessionToken) {
    throw new Error('VISION_AUTH_REQUIRED')  // 不再回退
  }
  // ... 移除所有 makeVisionFallback() 返回路径
}
```

### 验证方法

- grep 确认 `FALLBACK_DEV_TOKEN` 和 `DEV_` 不再出现在源码中
- 未登录状态下尝试使用 AI 文案功能，确认返回"需要登录"而非静默继续

---

## GAP 2: agconnect-services.json 凭据暴露

**风险**: CRITICAL | **阻塞上架**: 是

### 位置

- 文件: `frontend/entry/src/main/resources/rawfile/agconnect-services.json`
- `.gitignore` Line 85: 仅排除 `agc-apiclient-*.json`，未排除本文件

### 问题内容

文件包含以下凭据:

| 凭据类型 | 字段 | 适用对象 |
|---------|------|---------|
| `client_secret` | `client.client_secret` | `its.map.pin` (生产) |
| `api_key` | `client.api_key` | `its.map.pin` (生产) |
| `client_secret` | `appInfos[1].client.client_secret` | `com.ran.login_test` (测试残留) |
| `api_key` | `appInfos[1].client.api_key` | `com.ran.login_test` (测试残留) |

凭据使用 `[!00...]` AGC 加密信封格式，SDK 运行时可解密，**不是安全的公开格式**。

`.gitignore` 未覆盖此文件，凭据已进入 git 历史。

`appInfos` 数组还包含 `com.ran.login_test` 测试应用条目，应移除。

### 攻击场景

1. 攻击者获取仓库（公开或泄露）
2. 从 git 历史读取 `agconnect-services.json`
3. 使用 api_key 和 client_secret 冒充应用调用华为 AGConnect API
4. 推送恶意通知、访问云存储 `test-2rqgu`、创建任意用户认证会话

### 修复方案

**Step 1** — 添加到 `.gitignore`:
```
agconnect-services.json
frontend/entry/src/main/resources/rawfile/agconnect-services.json
```

**Step 2** — 从 git 移除追踪:
```bash
git rm --cached frontend/entry/src/main/resources/rawfile/agconnect-services.json
```

**Step 3** — 在华为 AppGallery Connect 控制台轮换所有凭据（生成新 api_key, client_secret, code 值）

**Step 4** — 从 `appInfos` 数组中移除 `com.ran.login_test` 条目，仅保留 `its.map.pin`

**Step 5** — 考虑构建时注入机制，将文件从安全位置注入到 HAP

### 验证方法

- `git ls-files | grep agconnect` 应返回空
- `.gitignore` 包含该文件路径
- `appInfos` 仅含一个条目

---

## GAP 3: ShareService 无认证回退

**风险**: HIGH | **阻塞上架**: 是（若后端 ALLOW_DEV_UID=1）

### 位置

- 文件: `frontend/entry/src/main/ets/feature/social-share/services/ShareService.ets`
- Lines 164-171: `publish()` 中 token 获取与条件注入
- Lines 285-291: `revokeByTrip()` 相同模式
- 文件: `frontend/entry/src/main/ets/common/api/AiTokenManager.ets`
- Lines 312-318: `tryGetShareToken()` 捕获所有异常返回 null

### 问题代码

```typescript
// ShareService.ets Line 164-171
const shareToken = await AiTokenManager.tryGetShareToken()  // 静默失败返回 null
const reqHeader: Record<string, string> = { 'Content-Type': form.getContentType() }
if (shareToken) {
  reqHeader['Authorization'] = `Bearer ${shareToken}`
}
// token 为 null 时不带 Authorization header，请求仍发出

// AiTokenManager.ets Lines 312-318
static async tryGetShareToken(): Promise<string | null> {
  try {
    return await getShareTokenCached()
  } catch (_) {
    return null  // 静默吞掉所有错误
  }
}
```

前端注释 Line 164 明确引用后端 bypass:
```
// 用 share_token 作为 Bearer；登录态拿不到则不带（后端 ALLOW_DEV_UID_HEADER=1 时仍可通过）
```

### 后端 Dev Bypass

`backend/share-service/share_service/core/auth_tokens.py` Lines 100-120:
```python
def require_share_token(...):
    if _ALLOW_DEV_UID and x_dev_uid:
        return x_dev_uid  # 直接通过
    raise HTTPException(status_code=401)
```

测试配置 `conftest.py` 确认默认 `ALLOW_DEV_UID_HEADER=1`。

### 攻击场景

1. 攻击者无需登录
2. 发送 `POST /api/v1/share/publish` 带 `X-Dev-Uid: victim_user_id` 无 `Authorization`
3. 后端 `ALLOW_DEV_UID_HEADER=1` 时直接通过
4. 攻击者以受害者身份发布分享、上传照片
5. 类似地，`revoke-by-trip` 可删除他人分享

### 修复方案

**前端** — 使用 `getShareToken` 替代 `tryGetShareToken`:
```typescript
// publish() 和 revokeByTrip() 中:
const shareToken = await AiTokenManager.getShareToken()  // 失败时抛出异常
const reqHeader: Record<string, string> = {
  'Content-Type': form.getContentType(),
  'Authorization': `Bearer ${shareToken}`
}
```

**后端** — 生产环境确保 `ALLOW_DEV_UID_HEADER=0`，最终从 `require_share_token()` 中移除 dev bypass 路径。

### 验证方法

- 未登录状态下尝试发布分享，确认返回 401 而非成功
- grep 确认 `tryGetShareToken` 不再被 ShareService 调用

---

## GAP 4: HttpClient 未统一注入 Auth Header

**风险**: MEDIUM | **阻塞上架**: 否（潜在风险）

### 位置

- 文件: `frontend/entry/src/main/ets/common/api/HttpClient.ets`
- Lines 105-111: `request()` 方法 header 配置
- Line 76: 方法级 TODO 注释
- Line 109: auth token TODO 注释

### 问题代码

```typescript
const options: http.HttpRequestOptions = {
  method: method,
  header: {
    'Content-Type': 'application/json'
    // TODO: 添加认证 Token
    // 'Authorization': `Bearer ${token}`
  },
  // ...
};
```

### 当前各 Service 认证状况

| Service | 文件 | 自行处理 Auth? |
|---------|------|--------------|
| VisionLLMClient | `VisionLLMClient.ets` | 是 — 从 `AiTokenManager` 获取 token |
| ImageCensorService | `ImageCensorService.ets` | 是 — 获取 `censorToken` |
| ContentFilterService | `ContentFilterService.ets` | 是 — 获取 `censorToken` |
| ShareService | `ShareService.ets` | 部分 — `tryGetShareToken` 静默失败 |
| HttpClient (基类) | `HttpClient.ets` | 否 — 从不注入 auth |

### 修复方案

重构 `HttpClient` 接受可选的 token provider:

```typescript
export class HttpClient {
  private baseUrl: string
  private tokenProvider?: () => Promise<string | null>

  constructor(baseUrl: string, tokenProvider?: () => Promise<string | null>) {
    this.baseUrl = baseUrl
    this.tokenProvider = tokenProvider
  }

  private async request<T>(...): Promise<HttpResponse<T>> {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' }
    if (this.tokenProvider) {
      const token = await this.tokenProvider()
      if (token) headers['Authorization'] = `Bearer ${token}`
    }
    // ...
  }
}
```

### 验证方法

- `HttpClient` 构造时可传入 token provider
- 无 token provider 时 header 中不含 Authorization（向后兼容）
- 有 provider 时自动注入

---

## GAP 5: 无 TLS 证书固定

**风险**: MEDIUM | **阻塞上架**: 否

### 位置

- 所有 `frontend/entry/src/main/ets/common/api/` 下的文件
- 使用 `@kit.NetworkKit` 的 `http.createHttp()` 发起请求
- 无任何 `securityConfiguration` / `pinConfig` 配置

### 攻击场景

1. 用户连接公共 Wi-Fi（机场/咖啡厅）
2. 攻击者运行恶意接入点 + 伪造 `audit.itsmappin.top` 证书
3. 设备可能接受伪造证书（取决于 CA 信任库）
4. 攻击者截获 Bearer token、用户照片、位置数据

### 修复方案

**短期** — 服务端添加 HSTS header 和短有效期 token（已实现 60 秒提前刷新）

**中期** — 利用 HarmonyOS `securityConfiguration`:
```typescript
const options: http.HttpRequestOptions = {
  method: method,
  header: headers,
  securityConfiguration: {
    domainSettings: {
      domains: [{ domain: 'audit.itsmappin.top' }],
      pinConfig: {
        pinHashes: ['sha256/XXXX...'], // 服务端证书 SHA-256
        chain: 'certificate_chain'
      }
    }
  }
}
```

### 验证方法

- 使用 mitmproxy 尝试中间人攻击，确认连接被拒绝
- 或使用 Charles Proxy + 自签名证书，确认请求失败

---

## GAP 6: moderateContent 桩实现

**风险**: LOW (未调用) / HIGH (若被使用) | **阻塞上架**: 可能

### 位置

- 文件: `frontend/entry/src/main/ets/common/api/AiGatewayClient.ets`
- Lines 473-489: `moderateContent()` 方法

### 问题代码

```typescript
async moderateContent(text: string): Promise<HttpResponse<ModerateResponse>> {
  const mockData: ModerateResponseData = {
    is_safe: true,    // 硬编码安全
    categories: []
  };
  return { statusCode: 200, data: { code: 0, data: mockData } };
}
```

函数无条件返回 `is_safe: true`，`text` 参数完全未使用。

### 当前状态

grep 确认 `.moderateContent(` 在整个代码库中**零调用**。实际的文本审查由 `ContentFilterService.check()` 处理（调用真实后端 API），此方法为早期设计的遗留代码。

### 修复方案

**推荐** — 删除整个方法和关联类型:
- 删除 `moderateContent()` (Lines 473-489)
- 删除 `ModerateResponse` / `ModerateResponseData` 接口
- 所有需要文本审查的地方统一使用 `ContentFilterService.check()`

### 验证方法

- grep 确认 `moderateContent` 不再存在于源码中
- 确认所有文本审查走 `ContentFilterService`

---

## 修复优先级建议

| 优先级 | 缺口 | 理由 |
|--------|------|------|
| P0 立即 | GAP 2: agconnect-services.json | 凭据已入 git 历史，需轮换 |
| P0 立即 | GAP 1: DEV fallback token | 硬编码凭据是上架自动拒绝项 |
| P1 上架前 | GAP 3: ShareService 无认证 | 后端需关闭 dev bypass |
| P1 上架前 | GAP 6: moderateContent 桩 | 删除死代码，避免误用 |
| P2 后续版本 | GAP 4: HttpClient auth 注入 | 架构改进，当前无利用路径 |
| P2 后续版本 | GAP 5: TLS 证书固定 | 安全加固，非强制要求 |
