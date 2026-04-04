# Task Backlog

**Last Updated**: 2026-04-03 (动态旅程回放功能 bug 修复)
**Total Tasks**: 28 (来自 base 项目)
**Completed**: 12 (含三层架构重构 + 动态旅程回放)
**In Progress**: 0
**Pending**: 16

---

## Task Status Legend
- ✅ Completed
- 🔄 In Progress
- ⏳ Pending
- 🔴 Blocked

---

## 2026-04-03 Update: 动态旅程回放功能 bug 修复

### ✅ 已完成工作 (2026-04-03)

**修复问题 1：地点变换时图文不切换**
- 根因：ReplayPhotoCard 使用 `@State node` 装饰节点数据，无法响应对象引用切换
- 解决方案：
  1. 为 `ReplayNode` 类添加 `@Observed` 装饰器
  2. 将 `ReplayPhotoCard.node` 从 `@State` 改为 `@Prop`
  3. 添加 `forceRefreshCard()` 方法强制刷新状态

**修复问题 2：拖动进度条时图文不显示**
- 根因：`jumpToNode` 调用 `moveToNode` 后，`isCardVisible=false`，但未在拖动后恢复
- 解决方案：`jumpToNode` 末尾显式设置 `isCardVisible=true`

**修改文件**:
- `common/service/types.ets`: ReplayNode 添加 @Observed，photoUri 类型改为 ResourceStr
- `feature/map-travel/components/ReplayPhotoCard.ets`: @State → @Prop
- `feature/map-travel/pages/TripReplayPage.ets`: 添加 forceRefreshCard()，修复 jumpToNode()

**编译状态**: ✅ BUILD SUCCESSFUL in 18s 929ms

---

## 2026-04-02 Update: 动态旅程回放功能完成

### ✅ 已完成工作 (2026-04-02)

**P02 - 动态旅程回放功能**:

| 组件 | 职责 | 关键特性 |
|------|------|----------|
| `TripReplayPage.ets` | 主页面 | 动画播放逻辑、相机动画、方位角计算 |
| `ReplayPhotoCard.ets` | 照片卡片 | 现代简约风格、点击展开回调 |
| `ReplayProgressBar.ets` | 进度条 | 离散步进、@Prop 接收外部进度 |
| `PhotoCardOverlay.ets` | 展开覆盖层 | 底部半屏、大图 + 完整文字 |

**动画参数**:
- 停留时长：5 秒
- 移动时长：1.5 秒
- 速度选项：0.5x / 1x / 2x
- 进度条：离散步进（只能在节点间跳转）

**数据模型**:
- `ReplayNode`: 回放节点（坐标、照片、标题、笔记、时间戳）
- `ReplayRoute`: 回放路线（节点数组、总距离、时长）
- `RouteGenerator`: 路线生成器接口（待队友实现）

**核心算法**:
- `calculateBearing()`: 计算两点方位角（相机朝向）
- `playSequence()`: 递归播放序列
- `moveToNode()`: 移动到指定节点（相机动画）

**修复的问题**:
1. 照片资源引用：从 `$rawfile` 改为 `$r('app.media.xxx')`
2. 退出按钮遮挡：容器尺寸从 100% 改为 40x40
3. 进度条不联动：@State 改为 @Prop
4. 退出按钮样式：从 '✕' 改为 '←'，加深背景

### Git Commits
- 79df842: feat: 修复动态旅程回放功能编译错误
- b425452: fix: 修复 TripReplayPage 照片资源路径
- a026056: fix: 修复照片显示和退出按钮层级问题
- 566ba14: fix: 修复退出按钮显示问题（回退）
- 61c7710: fix: 修复照片资源引用和退出按钮显示
- 11689b8: fix: 修复退出按钮容器遮挡点击事件
- 87040b8: feat: 优化退出按钮样式和进度条联动

---

## 2026-03-29 Update: 三层架构重构完成

### ✅ 已完成工作 (2026-03-29)

**Phase 1**: 创建 common 层
- 创建 `common/index.ets` 统一导出入口
- 创建 `common/utils/Constants.ets` (AppColors, AppDimens, RouterUrls)
- 创建 `common/service/types.ets` (数据模型类型定义)

**Phase 2**: 创建 feature 层目录结构
- `feature/map-travel/` (pages/, views/)
- `feature/profile/`
- `feature/social-share/`

**Phase 3**: 移动页面文件到 feature 层
- NodeEditPage, NodeDetailPage, TripDetailPage, TripReplayPage → `feature/map-travel/pages/`
- MapHomeView, TripListView → `feature/map-travel/views/`
- ProfileView → `feature/profile/views/`
- SharePage → `feature/social-share/pages/`

**Phase 4**: 配置模块导入和编译验证
- 统一 feature 层导入路径为 `'../../../common'`
- 更新 `main_pages.json` 路由配置
- 修复编译错误 (RouterUrls 未定义、页面路径找不到等)
- **BUILD SUCCESSFUL in 16s 673ms** (commit: 7d1132a)

### 重构后架构状态
```
entry/src/main/ets/
├── common/                 # 公共层
│   ├── index.ets           # 统一导出入口
│   ├── utils/Constants.ets # 工具类
│   └── service/types.ets   # 数据模型
├── feature/
│   ├── map-travel/         # 地图旅行功能
│   ├── profile/            # 个人中心
│   └── social-share/       # 社交分享
└── pages/                  # Product 层页面
    ├── Index.ets
    ├── LoginPage.ets
    └── MainPage.ets
```

---

### 分析报告摘要 (增量开发参考)

#### A. 项目结构对比

| 维度 | 当前 frontend workspace | base 项目 (目标架构) |
|------|------------------------|---------------------|
| **位置** | `frontend/entry/src/main/ets/` | `product/entry/src/main/ets/` + `common/` + `feature/` |
| **架构模式** | 扁平结构 (pages/views/common) | 四层架构 (Product → Feature → Service → Common) |
| **Pages 数量** | 8 个 (Index, LoginPage, MainPage, NodeDetail/Edit, TripDetail/Replay, Share) | 6 个 (Index, TravelEditor, RouteEditor, AiCopy, Share, Login) |
| **Common 模块** | 仅 Constants.ets | Utils, API, Auth, AI, Data, Security (7 个子目录) |
| **Feature 模块** | 无明确划分 | map-travel, route-editor, ai-copy, social-share |
| **Service Layer** | ❌ 未实现 | ✅ 接口已定义 (IDataService, IMLService, IAuthService, IShareService, ISyncService) |

#### 关键差异

1. **架构组织**:
   - 当前 frontend: 扁平组织，所有 pages/views 在 entry 内
   - base 项目: 四层架构，职责分离清晰

2. **Pages 命名**:
   - 当前 frontend: `Index.ets`, `MainPage.ets`, `LoginPage.ets`
   - base 项目: `Index.ets`, `Login.ets`, `TravelEditor.ets`, `RouteEditor.ets`, `AiCopy.ets`, `Share.ets`

3. **Constants 位置**:
   - 当前 frontend: `frontend/entry/src/main/ets/common/Constants.ets`
   - base 项目: `common/utils/Constants.ets` (独立模块)

4. **依赖管理**:
   - 当前 frontend: 直接导入相对路径
   - base 项目: 包名导入 (`travel-memory-common`, `travel-memory-feature-map-travel`)

---

### B. 任务优先级分析 (基于 base 项目)

#### 高优先级任务 (阻塞核心功能)

| 优先级 | 任务 ID | 任务名称 | 原因 | 预计工作量 |
|--------|--------|---------|------|-----------|
| **P0** | F1.1 | RdbHelper.ets | 本地数据存储基础 | 2-3h |
| **P0** | F1.2 | TravelRepository.ets | 旅行数据 CRUD | 2-3h |
| **P0** | F1.3 | MemoryNodeRepository.ets | 节点数据 CRUD | 2-3h |
| **P1** | F7.1 | ExifStripper.ets | 安全合规要求 | 1-2h |
| **P1** | F7.2 | ShareLinkSigner.ets | 分享功能安全 | 1-2h |
| **P1** | F8.1 | FileUploader.ets | 媒体上传能力 | 2-3h |

#### 中优先级任务 (功能增强)

| 优先级 | 任务 ID | 任务名称 | 原因 |
|--------|--------|---------|------|
| **P2** | F2.1/F2.2 | auth/ 目录 + HuaweiAccountAuth | 用户认证 |
| **P2** | F3.2/F3.3 | LocalImageTagger + MetadataAggregator | AI 能力 |
| **P2** | F4.1 | MapTravelComponent 节点聚合 | 性能优化 |

#### 低优先级任务 (锦上添花)

| 优先级 | 任务 ID | 任务名称 |
|--------|--------|---------|
| **P3** | F5.x | route-editor 模块 |
| **P3** | F6.x | ai-copy 模块 |
| **P3** | C1.x | 华为云集成 |

---

## 增量整合策略

### Phase 1: 数据层优先 (本周)
1. 复制 base/common/utils → frontend/entry/src/main/ets/common/utils
2. 复制 base/common/data → frontend/entry/src/main/ets/common/data
3. 实现 RdbHelper.ets (F1.1)
4. 实现 TravelRepository.ets (F1.2)
5. 实现 MemoryNodeRepository.ets (F1.3)

### Phase 2: 安全与网络 (本周后段)
1. 实现 ExifStripper.ets (F7.1)
2. 实现 ShareLinkSigner.ets (F7.2)
3. 实现 FileUploader.ets (F8.1)

### Phase 3: Service Layer (下周)
1. 实现 DataService (基于 RdbHelper)
2. 替换 Pages 中的 MockDataService

### Phase 4: Feature 模块整合 (下周后段)
1. 整合 map-travel 模块
2. 整合 route-editor 模块
3. 整合 ai-copy 模块

---

## 当前 frontend workspace 状态

### 已有文件 (可复用)
```
frontend/entry/src/main/ets/
├── common/
│   └── Constants.ets          # 需要移动到 common/utils 并重构
├── model/
│   └── DataModels.ets         # 可能包含 Travel/TravelNode 定义
├── pages/
│   ├── Index.ets              # 地图首页 (功能完整)
│   ├── LoginPage.ets          # 登录页
│   ├── MainPage.ets           # 主页
│   ├── NodeDetailPage.ets     # 节点详情
│   ├── NodeEditPage.ets       # 节点编辑
│   ├── SharePage.ets          # 分享页
│   ├── TripDetailPage.ets     # 旅行详情
│   └── TripReplayPage.ets     # 旅行回放
└── views/
    ├── MapHomeView.ets        # 地图主页视图
    ├── ProfileView.ets        # 个人主页
    └── TripListView.ets       # 旅行列表
```

### 需要从 base 项目整合的文件
```
base/common/
├── utils/         → 复制到 frontend/entry/src/main/ets/common/utils
│   ├── Logger.ets
│   ├── Constants.ets
│   ├── CoordinateConverter.ets
│   └── EventHub.ets
├── api/           → 复制到 frontend/entry/src/main/ets/common/api
│   ├── HttpClient.ets
│   ├── ApiEndpoints.ets
│   └── FileUploader.ets (待实现)
├── data/          → 复制到 frontend/entry/src/main/ets/common/data
│   ├── LocalStorage.ets (待实现)
│   ├── RdbHelper.ets (待实现)
│   ├── TravelRepository.ets (待实现)
│   └── MemoryNodeRepository.ets (待实现)
├── security/      → 复制到 frontend/entry/src/main/ets/common/security
│   ├── ExifStripper.ets (待实现)
│   └── ShareLinkSigner.ets (待实现)
├── auth/          → 复制到 frontend/entry/src/main/ets/common/auth
│   ├── HuaweiAccountAuth.ets (待实现)
│   └── SessionManager.ets (待实现)
├── ai/            → 复制到 frontend/entry/src/main/ets/common/ai
│   ├── LocalImageTagger.ets (待实现)
│   └── MetadataAggregator.ets (待实现)
└── service/       → 复制到 frontend/entry/src/main/ets/common/service
    ├── types.ets
    ├── index.ets
    ├── MockDataService.ets
    ├── IDataService.ets (接口)
    └── IService.ets (其他接口定义)
```

---

## 更新后的任务清单

### 分析任务
| ID | Task | Owner | Status | Priority |
|----|------|-------|--------|----------|
| A | 对比两个项目结构差异 | AI | ✅ | High |
| B | 分析 base 项目任务清单优先级 | AI | ✅ | High |

### 整合任务 - Phase 1 (数据层) - 架构已完成
| ID | Task | Owner | Status | Priority |
|----|------|-------|--------|----------|
| P1.1 | ✅ 创建 common 层目录结构 | AI | ✅ | High |
| P1.2 | ⏳ 复制 Logger.ets, CoordinateConverter.ets, EventHub.ets | TBD | ⏳ | High |
| P1.3 | ⏳ 重构 Constants.ets (已创建，可能需要补充) | TBD | ⏳ | Medium |
| P1.4 | ⏳ 创建 common/data 目录 | TBD | ⏳ | High |
| P1.5 | ⏳ 实现 RdbHelper.ets (F1.1) | TBD | ⏳ | High |
| P1.6 | ⏳ 实现 TravelRepository.ets (F1.2) | TBD | ⏳ | High |
| P1.7 | ⏳ 实现 MemoryNodeRepository.ets (F1.3) | TBD | ⏳ | High |

### 整合任务 - Phase 2 (安全/网络) - 架构已完成
| ID | Task | Owner | Status | Priority |
|----|------|-------|--------|----------|
| P2.1 | ✅ 创建 common/security 目录 | AI | ✅ | High |
| P2.2 | ⏳ 实现 ExifStripper.ets (F7.1) | TBD | ⏳ | High |
| P2.3 | ⏳ 实现 ShareLinkSigner.ets (F7.2) | TBD | ⏳ | High |
| P2.4 | ⏳ 创建 common/api 目录 | TBD | ⏳ | High |
| P2.5 | ⏳ 复制 HttpClient.ets, ApiEndpoints.ets | TBD | ⏳ | High |
| P2.6 | ⏳ 实现 FileUploader.ets (F8.1) | TBD | ⏳ | High |

### 整合任务 - Phase 3 (Service Layer) - 架构已完成
| ID | Task | Owner | Status | Priority |
|----|------|-------|--------|----------|
| P3.1 | ✅ 创建 common/service 目录 | AI | ✅ | High |
| P3.2 | ⏳ 复制 types.ets, index.ets, MockDataService.ets | TBD | ⏳ | High |
| P3.3 | ⏳ 复制 Service 接口定义 | TBD | ⏳ | High |
| P3.4 | ⏳ 实现 DataService | TBD | ⏳ | High |

---

## 任务分配模板

```markdown
### Task: [Task Name]
- **ID**: [e.g., F1.1]
- **Assignee**: [Name]
- **Due Date**: [YYYY-MM-DD]
- **Description**: [Brief description]
- **Acceptance Criteria**:
  - [ ] Criteria 1
  - [ ] Criteria 2
- **Dependencies**: [List dependent task IDs]
```

---

## 下一步建议

1. **确认团队分工** - 确定哪位队员负责哪个模块
2. **选择第一个整合目标** - 建议从 P1.1 (common/utils) 开始
3. **验证 DevEco Studio 配置** - 确保能够正常编译当前 frontend
4. **设置模块化导入** - 配置 oh-package.json5 支持包名导入
