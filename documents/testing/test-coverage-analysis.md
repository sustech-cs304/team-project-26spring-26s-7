# TravelPin 测试覆盖分析 — API 层替身技术与缺口评估

本文档完成三项工作：
1. 对现有 API 相关测试标注模拟服务器的方式
2. 评估 social-share、AI、华为云三大 feature 的测试覆盖是否满足 CI 质量门禁要求
3. 给出需要补充的测试清单及理由

---

## 一、现有 API 相关测试的替身技术标注

### 1.1 替身技术定义（本文档语境）

| 技术 | 含义 | 在本项目中的表现 |
|------|------|-----------------|
| **FAKE** | 有完整工作实现但走捷径的替代品，不依赖真实 I/O | `FakeStore`、`FakeMultipartFormData`、`FakePredicates` |
| **STUB** | 对调用返回固定应答，不包含逻辑 | `TestShareService.sendRequest()`、`TimeSequence`、`StubTravelRepository` |
| **MOCK** | 在替身内部预设交互期望并自动验证 | **本项目未使用**，所有交互验证通过手动 ASSERT 完成 |
| **ASSERT** | 在测试用例中手动断言状态、返回值、副作用 | 所有用例末尾的 `expect()` 调用 |

### 1.2 逐套件标注

#### ShareServiceTest（8 条用例）

| 用例 | 隔离方式 | 技术标注 |
|------|---------|----------|
| rejects mismatched photo count | 不触发网络，纯前端校验 | **ASSERT** |
| builds publish request with expiryMinutes/replace/replay | `FakeMultipartFormData` 记录字段 + `sendRequest()` 返回成功响应 | **FAKE** + **STUB** + **ASSERT** |
| falls back to expiryHours and omits optional fields | 同上 | **FAKE** + **STUB** + **ASSERT** |
| returns parsed backend error for failed publish | `sendRequest()` 返回 400 响应 | **STUB** + **ASSERT** |
| maps request exceptions to network error | `sendRequest()` 抛异常 | **STUB** + **ASSERT** |
| parses share status success envelope | `sendRequest()` 返回 200 + 成功信封 | **STUB** + **ASSERT** |
| maps share status error envelopes | `sendRequest()` 返回 404 + 错误信封 | **STUB** + **ASSERT** |
| parses revoke by trip success envelope | `sendRequest()` 返回 200 + 成功信封 | **STUB** + **ASSERT** |

**替身机制总结**：
- `TestShareService extends ShareService` 覆盖 `createFormData()` → 返回 `FakeMultipartFormData`（**FAKE**）
- `TestShareService` 覆盖 `sendRequest()` → 返回预设 `FakeHttpResponse`（**STUB**）
- 断言通过 `service.requestCount`、`service.lastUrl`、`form.capturedFields` 等手动验证（**ASSERT**）

#### SharePhotoHelperTest（5 条用例）

| 用例 | 隔离方式 | 技术标注 |
|------|---------|----------|
| skips cloud only refs and missing local files | 纯路径字符串判断 | **ASSERT** |
| ignores empty path entries | 纯路径字符串判断 | **ASSERT** |
| collects issues during prepare | 注入 `PrepareHooks implements SharePhotoHelperHooks` | **FAKE** + **ASSERT** |
| keeps sanitized jpeg outputs and cleanupPath | 注入 `SanitizeHooks implements SharePhotoHelperHooks` | **FAKE** + **ASSERT** |
| cleans only photos carrying cleanupPath | 注入 `CleanupHooks implements SharePhotoHelperHooks` | **FAKE** + **ASSERT** |

**替身机制总结**：通过 `SharePhotoHelper.hooks` 静态属性注入实现 `SharePhotoHelperHooks` 接口的假类（**FAKE**），每个测试在 `finally` 中恢复原始 hooks。

#### SharePreflightTest（6 条用例）

| 用例 | 隔离方式 | 技术标注 |
|------|---------|----------|
| blocks empty node list | 纯函数调用 | **ASSERT** |
| blocks invalid expiry | 纯函数调用 | **ASSERT** |
| blocks mismatched photo count | 纯函数调用 | **ASSERT** |
| blocks cloud only issue before size checks | 纯函数调用 | **ASSERT** |
| blocks missing local file issue | 纯函数调用 | **ASSERT** |
| passes valid publish payload | 纯函数调用（0 张照片避开了 `statBytes`） | **ASSERT** |

**替身机制总结**：无替身。`SharePreflight.validatePublish()` 是纯输入校验，但内部 `statBytes()` 调用了 `fs.statSync`，现有测试因 0 张照片而未触发该路径。

#### ShareErrorMapperTest（4 条用例）

| 用例 | 隔离方式 | 技术标注 |
|------|---------|----------|
| formats cloud only preflight errors | 纯函数调用 | **ASSERT** |
| formats invalid expiry publish errors | 纯函数调用 | **ASSERT** |
| passes through generic preflight message | 纯函数调用 | **ASSERT** |
| passes through generic publish message | 纯函数调用 | **ASSERT** |

**替身机制总结**：无替身。`ShareErrorMapper` 是纯错误格式化器。

---

## 二、三大 Feature 测试覆盖评估

### 评估标准

为满足 GitHub Actions CI 的质量门禁要求，测试需满足：
- **回归保护**：新改动不会静默破坏已有功能
- **关键路径覆盖**：API 请求构造、响应解析、错误映射三条主线均有断言
- **边界值验证**：空输入、溢出、非法值等边界条件有专门用例
- **可重复性**：测试不依赖外部服务，可在 CI 环境中稳定运行

### 2.1 Social-Share（社交分享）

| 维度 | 评估 | 说明 |
|------|------|------|
| API 请求构造 | ✅ 良好 | `publish` 的 multipart 字段、`replace` 字段、`replayPrefs` 字段均有验证 |
| 响应解析 | ✅ 良好 | 成功/错误信封解析已覆盖 `publish`、`status`、`revokeByTrip` |
| 错误映射 | ⚠️ 部分 | `ShareErrorMapper` 仅测试了 4/24 种错误码映射 |
| 边界值 | ⚠️ 缺失 | `SharePreflight` 缺少节点上限、单照片大小上限、总大小上限、边界过期时间测试 |
| 网络异常 | ⚠️ 部分 | 仅测试了 `publish` 的网络异常，`status` 和 `revokeByTrip` 缺少 |
| 信封解析边界 | ❌ 缺失 | `parseEnvelope` 对 `undefined`、非 JSON 字符串、缺失字段等边界未测试 |
| 系统分享 | ❌ 无覆盖 | `SystemShareService` 完全没有测试 |

**CI 覆盖评级：中等** — 主链路有保护，但错误分支和边界值存在回归风险。

### 2.2 AI（智能文案）

| 维度 | 评估 | 说明 |
|------|------|------|
| `VisionLLMClient` | ❌ 无覆盖 | `askText`、`askImage`、`testConnection` 均无测试 |
| `AiGatewayClient` | ❌ 无覆盖 | 多步 AI 生成管线、云端开关分支逻辑、缓存逻辑均无测试 |
| `ContentFilterService` | ❌ 无覆盖 | `check`、`batchCheck`、`mask` 三个 HTTP 端点无测试 |
| `HttpClient` | ❌ 无覆盖 | 基础 HTTP 层无测试 |
| 纯逻辑函数 | ❌ 无覆盖 | `charLimitToMaxTokens`、`buildBatchPrompt`、`describePhotoBatch` 等纯函数无测试 |
| 可测试性 | ❌ 严重不足 | 所有服务无依赖注入、无 protected 方法、无 hook 机制 |

**CI 覆盖评级：极低** — 整个 AI 功能没有任何自动化测试保护，任何改动都可能引入静默回归。且因缺少测试桩设计，无法在不重构的前提下添加隔离测试。

### 2.3 华为云（Auth / Sync / Storage）

| 维度 | 评估 | 说明 |
|------|------|------|
| `AuthService` | ❌ 无覆盖 | 登录、会话恢复、保存个人资料、注销、删除账号均无测试 |
| `CloudStorageService` | ❌ 无覆盖 | 30+ 方法的云存储操作无测试 |
| `CloudSyncService` | ❌ 无覆盖 | 云数据库 CRUD、ID 构建器均无测试 |
| `SyncManager` | ❌ 无覆盖 | 最复杂的服务（546 行），推送/拉取/协调逻辑无测试 |
| 纯逻辑函数 | ⚠️ 部分 | `buildTravelCloudId`、`extractLocalIdFromCloudId` 等纯函数无测试但可测 |
| 可测试性 | ❌ 严重不足 | 全部使用 static 方法，直接调用 AGConnect SDK，无依赖注入 |

**CI 覆盖评级：极低** — 整个云同步管线没有任何自动化测试，且与华为 SDK 强耦合。

---

## 三、需补充的测试清单

以下按优先级分为三个层级。**第一层级**可在不改动生产代码的前提下直接编写；**第二层级**需要先为生产代码添加测试桩（test seam）；**第三层级**涉及架构重构。

### 第一层级：无需改生产代码，可直接编写（9 项）

这些测试覆盖纯逻辑或有已有桩的模块，可立即加入 CI。

| # | 测试名称 | 被测模块 | 理由 |
|---|---------|---------|------|
| 1 | ShareErrorMapper 完整错误码映射 | `ShareErrorMapper` | 当前仅覆盖 4/24 种错误码。CI 中无法发现新增错误码导致的映射遗漏。补充后可确保每种用户可见错误都有正确输出。 |
| 2 | SharePreflight 节点上限与边界过期时间 | `SharePreflight` | 缺少 `TOO_MANY_NODES`（>30）、`PHOTO_TOO_LARGE`（>20MB）、`BODY_TOO_LARGE`（>100MB）、过期时间边界值（1h、720h）测试。这些是后端拒绝请求前的前端最后防线。 |
| 3 | SharePreflight PHOTO_SANITIZE_FAILED 阻断 | `SharePreflight` | `validateIssues` 对 `PHOTO_SANITIZE_FAILED` 的阻断逻辑未测试。 |
| 4 | ShareService.revokeByTrip 网络异常与错误响应 | `ShareService` | 当前仅测试了 revoke 的成功路径。非 200 响应和网络异常会导致未映射错误泄露到 UI。 |
| 5 | ShareService.parseEnvelope 边界 | `ShareService` | `undefined` 响应、非 JSON 字符串、缺失 `code` 字段等边界。`parseEnvelope` 是所有 API 方法的共享解析器，其稳定性影响全局。 |
| 6 | ShareService.publish HTTP header 验证 | `ShareService` | 验证传给 `sendRequest` 的 options 包含正确的 `Content-Type` 和 `method`。 |
| 7 | MultipartFormData 文件字段构建 | `MultipartFormData` | 现有 2 条用例仅测试文本字段。文件字段是 `publish` 的核心功能，缺少验证。 |
| 8 | CloudSyncService ID 构建与解析 | `CloudSyncService` | `buildTravelCloudId`、`buildNodeCloudId`、`extractLocalIdFromCloudId` 是纯字符串函数，无 I/O。若 ID 格式出错会导致云端数据关联断裂。 |
| 9 | CloudStorageService 纯路径构建函数 | `CloudStorageService` | `getUserScopedPath`、`buildNodePhotoPath`、`buildTravelPhotoRoot`、`buildProfileAvatarPath` 等纯路径拼接函数。路径错误会导致文件上传到错误位置。 |

### 第二层级：需先添加测试桩，再编写测试（8 项）

这些测试覆盖涉及 HTTP 或 SDK 调用的模块，需要先为生产代码添加 protected 方法、hook 属性或构造函数注入等测试桩，模式参照已有的 `ShareService.createFormData()/sendRequest()` 和 `SharePhotoHelper.hooks`。

| # | 测试名称 | 被测模块 | 需添加的桩 | 理由 |
|---|---------|---------|-----------|------|
| 10 | VisionLLMClient 请求构造与响应解析 | `VisionLLMClient` | 添加 `protected sendRequest()` 可覆盖桩（同 ShareService 模式） | `askText` 和 `askImage` 是 AI 功能的核心 API 调用，请求体构造（prompt 嵌套、model 参数）和响应解析（`choices[0].message.content`）必须被 CI 保护。 |
| 11 | VisionLLMClient 错误与连接测试 | `VisionLLMClient` | 同上 | `testConnection` 连接测试、网络异常映射、非 200 响应处理。 |
| 12 | ContentFilterService 三端点 | `ContentFilterService` | 改为实例方法 + `protected sendRequest()`，或将 `FILTER_BASE_URL` 改为可注入 | `check` 是个人资料保存的前置关卡（`saveLocalProfile` 调用它），若其解析逻辑出错会导致合规内容被误拦。 |
| 13 | AiGatewayClient 多图管线 | `AiGatewayClient` | 构造函数注入 `VisionLLMClient`、`LocalImageTagger` | `generateCopyFromImages` 有云端开关分支（cloud on → `askImage`，cloud off → `askText`）。分支逻辑和 prompt 构建必须被覆盖。 |
| 14 | AiGatewayClient 缓存与去重 | `AiGatewayClient` | 同上 | `getOrExtractMetadata` 有 LRU 缓存 + 进行中请求去重逻辑，缓存失效或重复请求会导致性能问题和数据不一致。 |
| 15 | AiGatewayClient 纯逻辑函数 | `AiGatewayClient`（模块级函数） | 将 `charLimitToMaxTokens`、`buildBatchPrompt`、`describeSinglePhoto`、`describePhotoBatch` 导出或提取为独立工具模块 | 这些纯函数影响 prompt 质量。`charLimitToMaxTokens` 的 token 换算公式若出错会导致生成文本截断或浪费。 |
| 16 | CloudSyncService payload 序列化 | `CloudSyncService` | 将 `buildTravelPayload`、`buildNodePayload` 改为 protected 或提取为独立函数 | payload 序列化是本地数据到云端数据的桥梁。字段遗漏或格式错误会导致云端数据不完整。 |
| 17 | SyncManager 同步队列处理 | `SyncManager` | 将 `CloudSyncService`、`CloudStorageService`、`RdbHelper` 改为可注入属性 | `handleItem` 根据实体类型和操作类型分发到不同处理路径（create/update/delete × travel/memory_node）。任何分支回归都会导致数据丢失。 |

### 第三层级：需架构重构后才能测试（4 项）

这些模块深度耦合华为 AGConnect SDK，需要引入接口抽象层或依赖注入框架。

| # | 测试名称 | 被测模块 | 所需重构 | 理由 |
|---|---------|---------|---------|------|
| 18 | AuthService 登录与会话流 | `AuthService` | 引入 `IAuthSdk` 接口包装华为认证 SDK，构造函数注入 | 登录是多步流程（华为 ID 请求 → AGConnect 登录 → 个人资料授权），任何步骤失败都会影响用户体验。CI 需验证各步骤的异常路径。 |
| 19 | CloudStorageService 上传下载 | `CloudStorageService` | 引入 `ICloudBucket` 接口包装 `StorageBucket`，实例化后注入 | 照片上传/下载是核心功能。`uploadFile` 有任务生命周期管理（进度、完成、失败），`downloadNodePhotoToSandbox` 有缓存路径逻辑。 |
| 20 | SyncManager 全量同步协调 | `SyncManager` | 依赖全部从 static 改为实例化注入 | `syncAllLocalToCloud` 包含双向协调逻辑（本地新增 → 云端 upsert，云端已删 → 本地删除，孤儿照片清理）。这是整个应用最复杂的数据流。 |
| 21 | SyncManager 照片同步 | `SyncManager` | 同上 | `syncNodePhotosForUpload` 和 `syncNodePhotosForDownload` 包含清单比对、孤儿清理、重试逻辑。照片丢失是最严重的用户数据问题。 |

---

## 四、实施建议

### 立即可做（投入 1-2 天）

执行第一层级的 9 项测试。这些测试：
- 不需要改动任何生产代码
- 使用已有的 FAKE/STUB/ASSERT 模式
- 可立即加入 CI pipeline
- 预计增加约 25-30 条用例

### 短期规划（投入 3-5 天）

按以下顺序执行第二层级：
1. 先改 `VisionLLMClient` 和 `ContentFilterService`（改动最小，收益最高）
2. 再改 `AiGatewayClient`（需要同时改 3 个依赖的注入方式）
3. 最后改 `CloudSyncService` 和 `SyncManager`（涉及面最广）

### 长期规划

第三层级的重构应与功能开发结合，不建议单独进行。每次触及相关模块时，顺便添加测试桩并补充测试。

### CI 质量门禁建议

当前 35 条用例全部通过时应为 CI 通过条件。随着测试补充，建议分阶段提升门禁：
1. **Phase 1**：第一层级完成后（~65 条），CI 必须 100% 通过
2. **Phase 2**：第二层级完成后（~100 条），加入按模块覆盖率检查
3. **Phase 3**：第三层级完成后，核心数据路径覆盖率目标 ≥ 80%
