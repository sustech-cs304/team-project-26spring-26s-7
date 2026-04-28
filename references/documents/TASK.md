# 任务清单 (Task Backlog)

**最后更新**: 2026-03-29
**总任务数**: 26
**已完成**: 5
**进行中**: 0
**待开始**: 21

---

## 状态图例
- ✅ 已完成
- 🔄 进行中
- ⏳ 待开始
- 🔴 已阻塞

---

## 数据存储说明

本项目的数据存储分为三层，注意区分：

| 层级 | 位置 | 存储内容 | 技术实现 |
|------|------|---------|---------|
| **本地存储层** | 设备本地 | 元数据、结构化数据 | RDB (@kit.ArkData) |
| **云端同步层** | 华为云空间 | 照片原图、视频、备份 | Cloud Kit SDK |
| **后端服务层** | 自建服务器 | AI 生成数据、分享验证 | REST API |

> **注意**: F1 任务中的 "本地存储层" 指的是 HarmonyOS 本地的 RDB 数据库，**不是**华为云存储。

---

## 前端任务 (HarmonyOS App)

### F1 - 本地存储层 (Local Storage)

**职责**: 实现设备本地的 RDB 数据库操作，支持离线使用和快速查询。

| ID | 任务 | 文件路径 | 负责人 | 状态 | 优先级 | 说明 |
|----|------|----------|--------|------|--------|------|
| F1.1 | 实现 RdbHelper.ets | `common/data/RdbHelper.ets` | TBD | ⏳ | 高 | RDB 数据库助手，用于结构化数据存储（本地） |
| F1.2 | 实现 TravelRepository.ets | `common/data/TravelRepository.ets` | TBD | ⏳ | 高 | 旅行实体的 CRUD 操作（本地 RDB） |
| F1.3 | 实现 MemoryNodeRepository.ets | `common/data/MemoryNodeRepository.ets` | TBD | ⏳ | 高 | 记忆节点实体的 CRUD 操作（本地 RDB） |
| F1.4 | 添加数据敏感度分级 (S0-S4) | `common/data/RdbHelper.ets` | TBD | ⏳ | 中 | 安全合规要求 |

**存储的数据类型**（本地 RDB）:
- 旅行元数据（名称、日期范围、封面 URI）
- 记忆节点（经纬度、描述、地址、时间戳）
- 用户草稿、标签、心情标记
- **不存储**: 照片原图（存在华为云）、视频文件

### F2 - 认证模块
| ID | 任务 | 文件路径 | 负责人 | 状态 | 优先级 | 说明 |
|----|------|----------|--------|------|--------|------|
| F2.1 | 创建 auth/ 目录结构 | `common/auth/` ✅ | TBD | ⏳ | 高 | 新建模块目录 |
| F2.2 | 实现 HuaweiAccountAuth.ets | `common/auth/HuaweiAccountAuth.ets` | TBD | ⏳ | 高 | 华为账号 SDK 集成 |
| F2.3 | 实现 SessionManager.ets | `common/auth/SessionManager.ets` | TBD | ⏳ | 中 | Token/Session 管理 |

### F3 - AI 文案生成 (合并原 F3 + F6)

**职责**: 基于鸿蒙 ML 服务提取图片 metadata，结合用户风格选择、字数限制、提示词，生成优美文案。

| ID | 任务 | 文件路径 | 负责人 | 状态 | 优先级 | 说明 |
|----|------|----------|--------|------|--------|------|
| F3.1 | 创建 ai/ 目录结构 | `common/ai/` ✅ | TBD | ⏳ | 高 | 新建模块目录 |
| F3.2 | 实现 LocalImageTagger.ets | `common/ai/LocalImageTagger.ets` | TBD | ⏳ | 高 | 本地图像标签提取（鸿蒙 ML Kit） |
| F3.3 | 实现 MetadataAggregator.ets | `common/ai/MetadataAggregator.ets` | TBD | ⏳ | 高 | 旅程元数据聚合（POI 列表、距离、时长、标签） |
| F3.4 | 实现 AiCopyGenerator.ets | `common/ai/AiCopyGenerator.ets` | TBD | ⏳ | 高 | AI 文案生成核心逻辑（风格/字数/提示词处理 + API 调用） |
| F3.5 | 实现 AiCopyGeneratorComponent.ets | `feature/ai-copy/components/AiCopyGeneratorComponent.ets` | TBD | ⏳ | 高 | UI 组件（风格选择器、字数控制、提示词输入框、生成结果展示） |
| F3.6 | 实现 AiCopyPage.ets | `feature/ai-copy/views/AiCopyPage.ets` | TBD | ⏳ | 中 | 完整页面包装器 |

**AI 服务交互流程**：
```
1. LocalImageTagger → 提取照片标签（本地 ML Kit）
2. MetadataAggregator → 聚合旅程元数据（本地 RDB）
3. AiCopyGenerator → 组装请求 → 自建服务器 AI Gateway
   - 用户输入：风格选择、字数限制、提示词
   - 请求内容：脱敏后的 POI 名称、距离、时长、标签
   - 响应：生成的文案 + 备选方案
```

### F4 - 地图功能
| ID | 任务 | 文件路径 | 负责人 | 状态 | 优先级 | 说明 |
|----|------|----------|--------|------|--------|------|
| F4.1 | 为 MapTravelComponent 添加节点聚合 | `feature/map-travel/components/MapTravelComponent.ets` | TBD | ⏳ | 高 | 密集节点场景性能优化 |
| F4.2 | 为 MapTravelPage 添加筛选 UI | `feature/map-travel/views/MapTravelPage.ets` | TBD | ⏳ | 中 | 按时间/区域/标签筛选 |

### F5 - 路线编辑器 (新模块)
| ID | 任务 | 文件路径 | 负责人 | 状态 | 优先级 | 说明 |
|----|------|----------|--------|------|--------|------|
| F5.1 | 创建 route-editor/ 目录 | `feature/route-editor/` ✅ | TBD | ⏳ | 高 | 新建功能模块 |
| F5.2 | 实现 RouteEditorComponent.ets | `feature/route-editor/components/RouteEditorComponent.ets` | TBD | ⏳ | 高 | 路线编辑 UI |
| F5.3 | 实现 PlaybackEngine.ets | `feature/route-editor/components/PlaybackEngine.ets` | TBD | ⏳ | 高 | 轨迹动画回放引擎 |
| F5.4 | 实现 RouteEditorPage.ets | `feature/route-editor/views/RouteEditorPage.ets` | TBD | ⏳ | 中 | 页面包装器 |

### F6 - 安全
| ID | 任务 | 文件路径 | 负责人 | 状态 | 优先级 | 说明 |
|----|------|----------|--------|------|--------|------|
| F6.1 | 实现 ExifStripper.ets | `common/security/ExifStripper.ets` | TBD | ⏳ | 高 | 使用 @kit.ImageKit 剥离 EXIF |
| F6.2 | 实现 ShareLinkSigner.ets | `common/security/ShareLinkSigner.ets` | TBD | ⏳ | 高 | 使用 @kit.ArkCrypto 实现 HMAC-SHA256 |
| F6.3 | 实现 LocalStorage.ets | `common/data/LocalStorage.ets` | TBD | ⏳ | 中 | 使用 @kit.ArkData.Preferences |

### F7 - 网络
| ID | 任务 | 文件路径 | 负责人 | 状态 | 优先级 | 说明 |
|----|------|----------|--------|------|--------|------|
| F7.1 | 实现 FileUploader.ets | `common/api/FileUploader.ets` | TBD | ⏳ | 高 | 使用 @ohos.request 上传文件 |
| F7.2 | 实现 SharePortalClient.ets | `common/api/SharePortalClient.ets` | TBD | ⏳ | 中 | 分享链接生成 |

### F8 - 产品层
| ID | 任务 | 文件路径 | 负责人 | 状态 | 优先级 | 说明 |
|----|------|----------|--------|------|--------|------|
| F8.1 | 完善 TravelEditor.ets | `product/entry/src/main/ets/pages/TravelEditor.ets` | TBD | ⏳ | 中 | 节点拖拽排序与编辑 |
| F8.2 | 完善 Index.ets 集成 | `product/entry/src/main/ets/pages/Index.ets` | TBD | ⏳ | 低 | 整合所有功能 |

---

## 后端任务 (自建服务器)

**注意**: 这些任务在独立仓库中实现，此处仅为协调追踪。

**自建服务器存储的数据类型**:
- AI 生成的文案内容
- 分享链接的签名验证记录
- **不存储**: 用户照片原图（华为云）、用户身份信息（华为账号）

| ID | 任务 | 负责人 | 状态 | 优先级 | 说明 |
|----|------|--------|------|--------|------|
| B1.1 | 设计 AI Gateway API | TBD | ⏳ | 高 | /api/v1/ai/generate |
| B1.2 | 实现内容合规审核 | TBD | ⏳ | 高 | 过滤不当内容 |
| B1.3 | 部署 LLM 服务 | TBD | ⏳ | 高 | 本地 LLM 部署 |
| B2.1 | 设计分享链接 API | TBD | ⏳ | 中 | /api/v1/share/verify |
| B2.2 | 实现链接验证 | TBD | ⏳ | 中 | HMAC-SHA256 验证 |
| B3.1 | 构建 Web 门户 (前端) | TBD | ⏳ | 中 | React/Vue 分享页面 |
| B3.2 | 构建 Web 门户 (后端) | TBD | ⏳ | 中 | 门户数据 API |

---

## 云端任务 (华为云)

**注意**: 这些是华为云 SaaS 服务，仅需前端集成配置，不涉及服务器开发。

**华为云存储的数据类型**:
- 照片原图、视频文件（媒体存储）
- RDB 数据库的云端备份
- 跨设备同步数据（变更日志、冲突解决）

| ID | 任务 | 负责人 | 状态 | 优先级 | 说明 |
|----|------|--------|------|--------|------|
| C1.1 | 配置华为账号 | TBD | ⏳ | 高 | AGC 项目搭建 |
| C1.2 | 集成 Cloud Kit SDK | TBD | ⏳ | 高 | 数据同步能力（前端调用 SDK） |
| C1.3 | 配置云存储 | TBD | ⏳ | 中 | 媒体文件存储配置 |

---

## 测试任务

| ID | 任务 | 文件路径 | 负责人 | 状态 | 优先级 | 说明 |
|----|------|----------|--------|------|--------|------|
| T1.1 | common/utils 单元测试 | `common/utils/Logger.ets`, `common/utils/Constants.ets`, `common/utils/EventHub.ets`, `common/utils/CoordinateConverter.ets` | TBD | ⏳ | 中 | Logger, Constants 等 |
| T1.2 | common/api 单元测试 | `common/api/HttpClient.ets`, `common/api/FileUploader.ets`, `common/api/ApiEndpoints.ets` | TBD | ⏳ | 中 | HttpClient 等 |
| T1.3 | 同步集成测试 | TBD | TBD | ⏳ | 低 | 云同步测试 |
| T2.1 | E2E 测试：添加记忆节点 | `feature/map-travel/`, `common/data/` | TBD | ⏳ | 高 | 完整用户旅程 |
| T2.2 | E2E 测试：生成 AI 文案 | `feature/ai-copy/`, `common/ai/` | TBD | ⏳ | 高 | AI 功能测试（LocalImageTagger, MetadataAggregator, AiCopyGenerator） |
| T2.3 | E2E 测试：分享路线 | `feature/social-share/`, `common/security/ShareLinkSigner.ets` | TBD | ⏳ | 中 | 分享功能测试 |

---

## 任务分配模板

复制以下模板用于分配任务：

```markdown
### 任务：[任务名称]
- **ID**: [例如 F1.1]
- **负责人**: [姓名]
- **截止日期**: [YYYY-MM-DD]
- **描述**: [简要描述]
- **验收标准**:
  - [ ] 标准 1
  - [ ] 标准 2
- **依赖**: [列出依赖的任务 ID]
```

---

## API 端点定义 (草案)

### 自建 AI 服务

**数据来源说明**: `journey_metadata` 来自前端本地 RDB 聚合，**不包含**用户身份信息和照片原图。

```
POST /api/v1/ai/generate
Content-Type: application/json
Authorization: Bearer {session_token}

请求:
{
  "journey_metadata": {
    "poi_list": ["西湖", "灵隐寺"],    // 脱敏后的 POI 名称
    "total_distance_km": 45,           // 距离（无位置信息）
    "duration_hours": 8,               // 时长
    "tags": ["nature", "temple"]       // 场景标签（本地图像分析结果）
  },
  "user_draft": "今天玩得很开心...",    // 用户草稿（可选）
  "style": "poetic",                   // 文案风格（poetic/casual/professional）
  "word_limit": 200,                   // 字数限制
  "custom_prompt": "强调西湖的美景"     // 用户自定义提示词
}

响应:
{
  "code": 0,
  "data": {
    "generated_text": "生成的文案内容...",
    "alternatives": ["方案 1", "方案 2"]
  }
}

POST /api/v1/ai/moderate
Content-Type: application/json

请求:
{
  "text": "待检查的用户生成内容..."
}

响应:
{
  "code": 0,
  "data": {
    "is_safe": true,
    "categories": []
  }
}
```

### 分享链接验证

**数据来源说明**: 验证通过后返回的 `journey_data` 来自华为云存储的旅行元数据备份。

```
GET /api/v1/share/{travel_id}
Query: signature, expires

响应:
{
  "code": 0,
  "data": {
    "valid": true,
    "journey_data": {...}
  }
}
```

### 华为云集成点

**存储的数据类型**:
- **媒体文件**: 照片原图、视频（大文件）
- **备份数据**: RDB 数据库的加密备份
- **同步数据**: 变更日志、冲突解决信息

```typescript
// 认证 - 华为账号
- onAccountSignIn() -> 获取华为 ID Token
- exchangeToken(huaweiToken) -> 从自建服务器获取 Session Token

// 数据同步 - RDB 数据的云端备份
- CloudKit.put(travelData)   // 上传旅行数据备份
- CloudKit.get(travelId)     // 下载旅行数据
- CloudKit.subscribe(travelChanges) // 监听其他设备的变更

// 媒体存储 - 照片和视频
- CloudKit.uploadPhoto(photoUri)   // 上传照片原图
- CloudKit.downloadPhoto(photoId)  // 下载照片原图
```

---

## 数据存储责任矩阵

| 数据类型 | 本地 RDB | 华为云 | 自建服务器 |
|---------|:-------:|:-----:|:---------:|
| 旅行元数据（名称、日期） | ✅ | ✅ 备份 | ❌ |
| 记忆节点（经纬度、描述） | ✅ | ✅ 备份 | ❌ |
| 照片原图 | ❌ | ✅ | ❌ |
| 照片缩略图/缓存 | ✅ | ❌ | ❌ |
| AI 生成文案 | ❌ | ❌ | ✅ 临时 |
| 分享链接记录 | ❌ | ❌ | ✅ |
| 用户身份信息 | ❌ | ✅ 华为账号 | ❌ |
| Session Token | ✅ 本地 | ❌ | ✅ 服务端 |

---

## 任务优先级说明

| 优先级 | 说明 | 建议处理时间 |
|--------|------|-------------|
| **高** | 核心功能，阻塞其他任务 | 本周内 |
| **中** | 重要但不阻塞其他任务 | 本周内 |
| **低** | 锦上添花功能 | 本周后段 |
