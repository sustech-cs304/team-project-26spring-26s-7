# AI 文案功能开发指南

**创建日期**: 2026-04-08
**分支**: feature/ai
**状态**: 接口框架已搭建，待具体实现

---

## 一、功能架构概览

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              用户界面层                                       │
│  ┌─────────────────┐                                                        │
│  │  AiCopyPage     │  用户选择风格、字数、提示词，点击"生成文案"            │
│  └────────┬────────┘                                                        │
│           │ 调用                                                            │
└───────────┼─────────────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AI 能力层 (common/ai/)                          │
│  ┌─────────────────────┐    ┌─────────────────────┐                        │
│  │ MetadataAggregator  │    │  LocalImageTagger   │ ◄── 视觉Kit待实现    │
│  │  (已实现框架)        │    │   (TODO: 待实现)    │                        │
│  │  聚合节点元数据      │    │  提取照片标签        │                        │
│  └────────┬────────────┘    └──────────┬──────────┘                        │
│           │                            │                                    │
│           │ 从 RDB 读取                │ 写入 photo_metadata 表             │
│           ▼                            ▼                                    │
└───────────┼─────────────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              数据层 (common/data/)                           │
│  ┌─────────────────────┐    ┌─────────────────────┐                        │
│  │ MemoryNodeRepository│    │PhotoMetadataRepo    │                        │
│  │  (已实现)           │    │  (已实现)            │                        │
│  │  节点 CRUD          │    │  照片元数据 CRUD     │                        │
│  └─────────────────────┘    └─────────────────────┘                        │
│           │                            │                                    │
│           └────────────┬───────────────┘                                    │
│                        ▼                                                    │
│              ┌─────────────────────┐                                        │
│              │     RdbHelper       │                                        │
│              │  travels 表         │                                        │
│              │  memory_nodes 表    │                                        │
│              │  photo_metadata 表  │ ◄── 新增表                             │
│              └─────────────────────┘                                        │
└─────────────────────────────────────────────────────────────────────────────┘
            │
            │ 发送请求
            ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              API 层 (common/api/)                            │
│  ┌─────────────────────┐    ┌─────────────────────┐                        │
│  │   AiGatewayClient   │    │    HttpClient       │                        │
│  │  (TODO: 占位实现)   │────►│   (已实现)          │                        │
│  │  调用后端 AI 接口   │    │   HTTP 请求封装     │                        │
│  └─────────────────────┘    └─────────────────────┘                        │
│           │                                                                 │
└───────────┼─────────────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              后端服务 (自建服务器)                           │
│                                                                              │
│  POST /api/v1/ai/generate  ◄── 后端队友实现                                 │
│  POST /api/v1/ai/moderate  ◄── 后端队友实现                                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 二、数据流说明

### 阶段一：照片上传时（提前提取元数据）

```
用户选择照片
     │
     ▼
PhotoPickerUtil.saveToSandbox() ──── 获取沙箱路径
     │
     ▼
LocalImageTagger.extractMetadata() ── 视觉Kit提取标签 (TODO: 队友实现)
     │
     ▼
PhotoMetadataRepository.upsert() ──── 存入 photo_metadata 表
```

### 阶段二：文案生成时（消费元数据）

```
用户点击"生成文案"
     │
     ▼
MetadataAggregator.aggregateFromNode(nodeId)
     │
     ├──► 从 MemoryNodeRepository 获取节点数据
     ├──► 从 PhotoMetadataRepository 获取照片元数据
     └──► 聚合生成 JourneyMetadata
     │
     ▼
AiGatewayClient.generateCopy(request) ── 发送到后端 (TODO: 后端实现)
     │
     ▼
返回 AiCopyResponse ─────────────────── 显示生成的文案
```

---

## 三、角色与职责

### 3.1 视觉 Kit 队友

#### 需要实现的文件

| 文件路径 | 状态 | 说明 |
|---------|------|------|
| `common/ai/LocalImageTagger.ets` | ⏳ TODO | 图片标签提取器 |

#### 实现内容

```typescript
// 文件: common/ai/LocalImageTagger.ets

export class LocalImageTagger {
  /**
   * 提取单张照片的元数据
   * 
   * @param photoPath 照片沙箱路径
   * @returns PhotoMetadata 结构
   * 
   * TODO: 实现步骤
   * 1. 使用鸿蒙 ML Kit 或其他视觉 Kit 加载图片
   * 2. 调用图像分析 API 获取标签
   * 3. 将结果转换为 PhotoMetadata 结构返回
   */
  async extractMetadata(photoPath: string): Promise<PhotoMetadata> {
    // TODO: 实现具体逻辑
    // 当前返回模拟数据，需要替换为真实实现
  }
}
```

#### 输入/输出规范

**输入**:
```typescript
photoPath: string  // 照片沙箱路径，如 "/data/storage/el2/base/haps/entry/files/photos/xxx.jpg"
```

**输出** (`PhotoMetadata` 结构):
```typescript
interface PhotoMetadata {
  photoPath: string;        // 原照片路径 (必须与输入一致)
  sceneTags: string[];      // 场景标签: ['nature', 'city', 'indoor', 'outdoor']
  objectTags: string[];     // 物体标签: ['mountain', 'building', 'person', 'food']
  colorTags: string[];      // 颜色标签: ['warm', 'cool', 'colorful']
  timeTags: string[];       // 时间标签: ['morning', 'sunset', 'night']
  emotionTags: string[];    // 情感标签: ['happy', 'peaceful', 'exciting']
  extractedAt: number;      // 提取时间戳 Date.now()
}
```

#### 调用时机

照片上传时调用，建议在以下位置集成：

```typescript
// 文件: common/utils/PhotoPickerUtil.ets
// 或者在 PhotoSelector 组件中选择照片后调用

import { LocalImageTagger } from '../ai/LocalImageTagger';
import { PhotoMetadataRepository } from '../data/PhotoMetadataRepository';

const tagger = new LocalImageTagger();
const metadataRepo = new PhotoMetadataRepository();

// 每张照片上传后
const metadata = await tagger.extractMetadata(photoPath);
await metadataRepo.upsert(metadata);
```

---

### 3.2 后端开发队友

#### 需要实现的接口

| 接口 | 文件位置 | 说明 |
|------|---------|------|
| `/api/v1/ai/generate` | 后端服务器 | AI 文案生成 |
| `/api/v1/ai/moderate` | 后端服务器 | 内容审核 |

#### 需要配置的前端文件

| 文件路径 | 配置项 | 说明 |
|---------|--------|------|
| `common/api/ApiEndpoints.ets` | `API_BASE_URL` | 服务器地址 |
| `common/api/HttpClient.ets` | 认证 Token | 如需要认证，添加 Header |

#### 接口规范

**POST /api/v1/ai/generate**

请求体 (`AiCopyRequest`):
```json
{
  "journey_metadata": {
    "poiList": ["西湖", "灵隐寺"],
    "totalDistanceKm": 45,
    "durationHours": 8,
    "tags": ["nature", "temple", "lake"],
    "photoCount": 20
  },
  "user_draft": "今天玩得很开心...",
  "style": "poetic",
  "word_limit": 100,
  "custom_prompt": "强调西湖的美景"
}
```

响应体 (`AiCopyResponse`):
```json
{
  "code": 0,
  "data": {
    "generated_text": "西湖畔，柳絮飞...",
    "alternatives": ["备选方案1", "备选方案2"]
  }
}
```

**字段说明**:

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| journey_metadata | object | 是 | 旅程元数据 |
| journey_metadata.poiList | string[] | 是 | POI 名称列表 (已脱敏) |
| journey_metadata.tags | string[] | 是 | 图片标签聚合 |
| style | string | 是 | 风格: poetic/factual/casual/minimal/social |
| word_limit | number | 是 | 字数限制 |
| user_draft | string | 否 | 用户草稿/提示词 |
| custom_prompt | string | 否 | 自定义提示词 |

#### 前端调用位置

```typescript
// 文件: common/api/AiGatewayClient.ets
// 方法: generateCopy()

async generateCopy(request: AiCopyRequest): Promise<HttpResponse<AiCopyResponse>> {
  // TODO: 取消注释以下代码，删除模拟响应
  // return this.httpClient.post<AiCopyResponse>(
  //   AiEndpoints.GENERATE_COPY,
  //   request,
  //   HttpTimeout.AI_GENERATE
  // );
  
  // 当前是模拟数据，后端实现后替换为真实调用
}
```

---

### 3.3 前端开发者

#### 已完成的工作（可修改覆盖）

| 文件 | 状态 | 说明 |
|------|------|------|
| `common/api/ApiEndpoints.ets` | ✅ 已完成 | 端点定义 |
| `common/api/HttpClient.ets` | ✅ 已完成 | HTTP 客户端 |
| `common/api/AiGatewayClient.ets` | ✅ 框架完成 | 占位实现 |
| `common/ai/PhotoMetadata.ets` | ✅ 已完成 | 类型定义 |
| `common/ai/MetadataAggregator.ets` | ✅ 已完成 | 元数据聚合 |
| `common/ai/LocalImageTagger.ets` | ✅ 框架完成 | 占位实现 |
| `common/data/PhotoMetadataRepository.ets` | ✅ 已完成 | 数据仓库 |
| `common/data/RdbHelper.ets` | ✅ 已完成 | 新增 photo_metadata 表 |
| `feature/ai-copy/pages/AiCopyPage.ets` | ✅ 已完成 | 调用流程集成 |

#### 后续需要做的

1. **照片上传时触发元数据提取**
   - 在 `PhotoPickerUtil` 或 `PhotoSelector` 中集成 `LocalImageTagger`
   - 提取后调用 `PhotoMetadataRepository.upsert()` 存储

2. **后端接口联调**
   - 配置 `API_BASE_URL`
   - 取消 `AiGatewayClient.generateCopy()` 中的注释

---

## 四、数据库表结构

### photo_metadata 表 (新增)

```sql
CREATE TABLE IF NOT EXISTS photo_metadata(
  photo_path TEXT PRIMARY KEY,      -- 照片沙箱路径 (主键)
  scene_tags TEXT,                  -- 场景标签 JSON 数组
  object_tags TEXT,                 -- 物体标签 JSON 数组
  color_tags TEXT,                  -- 颜色标签 JSON 数组
  time_tags TEXT,                   -- 时间标签 JSON 数组
  emotion_tags TEXT,                -- 情感标签 JSON 数组
  extracted_at INTEGER NOT NULL,    -- 提取时间戳
  sensitivity TEXT NOT NULL DEFAULT 'S2'  -- 敏感度分级
)
```

**查询方式**:
```typescript
// 通过照片路径查询元数据
const metadata = await photoMetadataRepo.getByPath(photoPath);

// 批量查询
const metadataMap = await photoMetadataRepo.getBatch(photoPaths);
```

---

## 五、快速开始

### 视觉 Kit 队友

1. 切换到 `feature/ai` 分支
2. 打开 `frontend/entry/src/main/ets/common/ai/LocalImageTagger.ets`
3. 实现 `extractMetadata()` 方法
4. 运行编译验证

### 后端同事

1. 查看请求/响应结构：`frontend/entry/src/main/ets/common/ai/PhotoMetadata.ets`
2. 实现 `/api/v1/ai/generate` 接口
3. 实现 `/api/v1/ai/moderate` 接口 (可选)
4. 提供服务器地址给前端配置

### 前端联调

1. 配置服务器地址：
   ```typescript
   // common/api/ApiEndpoints.ets
   export const API_BASE_URL: string = 'https://your-server.com'
   ```

2. 取消真实调用：
   ```typescript
   // common/api/AiGatewayClient.ets
   // 删除模拟数据，取消注释 httpClient.post() 调用
   ```

---

## 六、文件清单

### 新增文件

```
frontend/entry/src/main/ets/common/
├── api/
│   ├── ApiEndpoints.ets      ✅ 已完成
│   ├── HttpClient.ets        ✅ 已完成
│   ├── AiGatewayClient.ets   ⏳ 框架完成，待后端实现后联调
│   └── index.ets             ✅ 已完成
├── ai/
│   ├── PhotoMetadata.ets     ✅ 已完成 (类型定义)
│   ├── LocalImageTagger.ets  ⏳ 框架完成，待视觉Kit队友实现
│   ├── MetadataAggregator.ets✅ 已完成
│   └── index.ets             ✅ 已完成
└── data/
    └── PhotoMetadataRepository.ets ✅ 已完成
```

### 修改文件

```
frontend/entry/src/main/ets/
├── common/
│   ├── data/RdbHelper.ets    ✅ 新增 photo_metadata 表
│   ├── data/index.ets        ✅ 新增导出
│   └── index.ets             ✅ 新增导出
└── feature/ai-copy/pages/
    └── AiCopyPage.ets        ✅ 调用流程集成
```