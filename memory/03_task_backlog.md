# Task Backlog

**Last Updated**: 2026-05-10 (GitHub Actions Jenkins bridge)
**Total Tasks**: 按模块滚动维护
**Completed**: 三层架构、动态旅程回放、地点搜索替换、首页地图搜索、云同步认证、UI 页面更新、social-share 模块 1 主链路
**In Progress**: social-share 图片分享完善
**Pending**: cloud-only 自动回源、分享链路测试补充、发布阶段提示优化

---

## 2026-05-10 Update: GitHub Actions Jenkins Bridge

### ✅ Completed

- Added a repo workflow that listens to `push` on `test/ci-cd` and triggers the local Jenkins job `travelpin-ci` through the Jenkins HTTP API.
- Wired the GitHub Actions side to upload `.ci-logs` and the matching `ci-artifacts/build-<BUILD_NUMBER>` directory for the Jenkins run.
- Kept the existing local Jenkins + DevEco + hvigor flow as the execution backend instead of replacing it with Jenkinsfile Runner.

### ⏳ Pending

- Register the Windows self-hosted GitHub Actions runner on the Jenkins machine and confirm it carries the `self-hosted` and `windows` labels.
- Add `JENKINS_USERNAME` and `JENKINS_API_TOKEN` repository secrets, then push a test commit to `test/ci-cd` for end-to-end validation.
- If needed later, generalize the hard-coded local artifact root in the workflow into a machine-level variable or secret.

---

## Task Status Legend
- ✅ Completed
- 🔄 In Progress
- ⏳ Pending
- 🔴 Blocked

---

## 2026-05-06 Update: Codex 适配与 Social Share Module 1 合并

### 🔄 已完成工作 (2026-05-06)

**分享公开性约束补齐**:
- `TripDetailPage` 的私密路线分享入口已改为灰态可点，点击后弹窗确认是否转为公开。
- 用户确认后先持久化 `isPublic=true`，再跳转 `SharePage`。
- `SharePage` 已增加私密路线前端兜底，避免直接路由绕过限制。

**Codex 辅助文件适配**:
- 新增 `AGENTS.md` 作为 Codex 主入口，整理当前分支、架构、social-share 契约、构建命令和 memory 维护规则。
- 将 `CLAUDE.md` 调整为 Claude 兼容入口，指向 `AGENTS.md`，避免两套代理规则分叉。
- 更新 memory 文件，使其反映 `feature/social-share` 当前状态，而不是 4 月份 `incremental-dev-20260329` 状态。

**Social Share Module 1 主链路**:
- 合并远端多档有效期与自动撤销旧链接方案，merge commit: `def52e1`。
- 保留 EXIF 清洗、图片预检、错误码映射和显式阻止静默丢图。
- 缓存策略确定为 `cachedReq + cachedNodes`，不缓存清洗后的临时照片。
- 每次发布或切换有效期重新生成清洗临时图片，发布结束后清理。

**后端同步复用**:
- 用户级 Codex skill `team-project-backend-sync` 已创建，用于复用从 `172.18.35.215:~/backend` 拉取 backend 到当前 `frontendv1` 工作区的流程。

**验证状态**:
- `git diff --check` 已在 merge 阶段通过。
- `frontend/build.ps1 --mode module -p module=entry@default assembleHap` 已通过。

---

## 2026-05-07 Update: Replay Enhancement Phase 0

### ✅ 已完成工作 (2026-05-07)

**Replay 配置骨架**:
- 新增 `common/replay/` 目录，抽离 Replay 偏好、风格套件、BGM 目录和特效配置枚举。
- 新增 `ReplayPreferences`，统一管理 `replayStyleKitId`、`replayBgmId`、`replayFilterId`、`replayTransitionType` 和 `replayPreferencesVersion`。

**Replay 设置面板骨架**:
- 新增 `ReplaySettingsSheet` 组件，先提供 `Style` 和 `Music` 两个 Tab。
- 当前 Phase 0 仅实现选择与持久化，不改变现有默认视觉和实际音轨切换行为。

**TripReplayPage 接入**:
- 右上角新增齿轮设置入口，点击可打开 Replay 设置面板。
- 页面进入时初始化 Replay 默认偏好并同步当前选择状态。
- 背景音乐加载路径改为从 `ReplayMusicCatalog` 读取，当前仍指向现有单曲 `South-East-Traveling.mp3`。

**验证状态**:
- `git diff --check` 已通过。
- `frontend/build.ps1 --mode module -p module=entry@default assembleHap` 已通过。
- 构建输出包含仓库既有 ArkTS warnings，但无新增阻塞编译错误。

### ⏳ 后续任务

- Phase 1: 将真实曲库接入 `ReplayMusicCatalog`，支持多首 BGM 切换和播放器重载。
- Phase 2: 让 `ReplayStyleKit` 真正驱动照片卡片、进度条、控制栏和路线样式。
- 补齐素材合规记录 `references/documents/replay/assets/music-attribution.md`，在提交或分发前完成。

---

## 2026-05-07 Update: Replay Enhancement Phase 1

### ✅ 已完成工作 (2026-05-07)

**路线级本地 Replay 持久化**:
- `travels` 表新增本地 Replay 配置列：`replay_style_kit_id`、`replay_bgm_id`、`replay_filter_id`、`replay_transition_type`。
- `Trip` 模型和 `IDataService` 已支持读取与更新单条路线的 Replay 配置。
- 当前实现仅适配本地 RDB，不进入专门的云同步逻辑。

**多 BGM 接入**:
- `ReplayMusicCatalog` 已接入 5 首本地音乐素材，并映射中文名称和说明。
- `TripReplayPage` 中切换音乐后会即时重载播放器，不再只是 UI 选择。

**页面行为**:
- 进入某条路线的 Replay 页面时，会优先读取该路线的本地 Replay 配置。
- 在 Replay 设置面板中切换风格或音乐后，会写回当前路线本地配置。

**验证状态**:
- `git diff --check` 已通过。
- `frontend/build.ps1 --mode module -p module=entry@default assembleHap` 已通过。

### ⏳ 后续任务

- Phase 2: 将 `ReplayStyleKit` 真正应用到卡片、进度条、控制栏和地图样式。
- Phase 3: 低成本视觉增强（滤镜、玻璃覆盖层、波纹等）。
- 后续再按需要设计华为云数据库字段与同步映射，不在当前 Phase 1 范围内。
### ⏳ 后续任务

- 增加分享发布阶段提示。
- 实现 `cloud-only` 自动下载回源。
- 为 `SharePhotoHelper`、`SharePreflight`、`ShareService` 补测试。
- 按新 `AGENTS.md` 规则持续维护 memory。

---

## 2026-04-16 Update: 云同步 + UI 页面更新合并

### 🔄 已完成工作 (2026-04-16)

**P0 - 登录认证功能**:
- 实现华为账号认证 (HWID 登录/登出)
- 支持用户头像获取与展示
- AuthProvider 封装认证逻辑

**P0 - 云存储服务**:
- 照片上传到华为云对象存储 (OBS)
- 云存储 SDK 集成与权限配置
- 真机测试验证通过

**P0 - 云数据库同步**:
- TravelPinZone 云数据库访问封装
- Travel/MemoryNode 上行 upsert/delete
- sync_queue 消费器实现
- 支持手动/启动时触发同步

**P0 - UI 页面更新 (PR #105)**:
- TripEditPage 旅行编辑页面
- NodeListView 节点列表视图
- 瀑布式旅行列表展示
- 地图真实搜索选点流程

**修改文件**:
- common/auth/ 认证模块
- common/sync/ 同步模块
- RdbHelper.ets / TravelRepository.ets / MemoryNodeRepository.ets
- feature/map-travel/pages/TripEditPage.ets (新增)
- feature/map-travel/views/NodeListView.ets (新增)
- MapHomeView.ets / NodeDetailPage.ets / NodeEditPage.ets
- MainPage.ets / main_pages.json

**编译状态**: ✅ 远端合并验证通过

---

## 2026-04-12 Update: 旅行相册瀑布流页面开发

### 🔄 已完成工作 (2026-04-12)

**P0 - 新增并列相册页（双列瀑布流）**:

- 新增 `feature/map-travel/views/TripAlbumView.ets`，以双列瀑布流形式纵向展示旅行封面
- 封面逻辑采用“旅行第一个 node 的第一张图片”，无节点/无图片时自动回退占位卡片
- 点击任意旅行卡片复用既有路由协议进入 `TripDetailPage`
- 复用 `travelDataVersion` 监听机制，保证旅行数据变化后相册自动刷新

**P0 - MainPage 并列入口扩展**:

- 在 `pages/MainPage.ets` 底部 Tabs 中新增第 4 个并列页「相册」
- 保持既有三个 Tab（地图/旅行/我的）逻辑不变，仅新增并列入口

**修改文件**:
- `feature/map-travel/views/TripAlbumView.ets`
- `pages/MainPage.ets`
- `feature/map-travel/index.ets`
- `memory/02_change_log.md`
- `memory/03_task_backlog.md`

**编译状态**: ⚠️ 受当前会话环境限制未完成（DevEco 工具链路径缺失，需本机 DevEco 环境手动验证）

---

## 2026-04-10 Update: Map Kit 地点搜索替换

### 🔄 已完成工作 (2026-04-10)

**P0 - LocationPicker 真实地点搜索接入**:

- 将 `feature/map-travel/pages/LocationPickerPage.ets` 的硬编码地点匹配替换为 `@kit.MapKit.site.searchByText(...)`
- 保留经纬度直输能力，继续支持 `22.55,113.96` 这类输入直接选点
- 地图点击后增加 `site.reverseGeocode(...)`，优先展示真实 POI/地址，失败时回退为经纬度
- 保持 `AppStorage` 回填契约不变，`NodeEditPage.ets` 无需改动
- 增加搜索中、空结果与失败提示，避免用户误以为页面无响应
- 使用页面内轻量结果接口，降低 `site` 返回类型字段名差异导致的 ArkTS 编译风险

**P0 - 首页地图搜索接入**:

- 将 `feature/map-travel/views/MapHomeView.ets` 顶部静态搜索栏替换为真实 `TextInput`
- 先搜索本地记忆节点（标题 / 地点 / 标签），再合并 `@kit.MapKit.site.searchByText(...)` 的 POI 结果
- 搜索结果去重后以下拉列表展示，避免首页已有节点和 POI 重复堆叠
- 选中节点结果时联动地图相机并打开底部预览卡片；选中 POI 结果时仅移动地图
- 保留原有筛选面板、长按建点、Marker 预览等首页交互

**修改文件**:
- `feature/map-travel/pages/LocationPickerPage.ets`
- `feature/map-travel/views/MapHomeView.ets`
- `memory/02_change_log.md`
- `memory/03_task_backlog.md`

**编译状态**: ⚠️ 待用户手动验证（本次仅完成代码修复，未在会话内执行编译）

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
## 2026-05-07 Replay 澧炲箍 Phase 2

- [x] R2.1 `ReplayStyleKit` 宸ュ巶鍗囩骇涓虹湡瀹?style token锛屾敮鎸佸崱鐗囥€佹帶鍒舵爮銆佽鎯呭眰銆佽繘搴︽潯閰嶈壊
- [x] R2.2 `ReplayPhotoCard` 鎺ユ敹 style/filter 鍙傛暟锛岄殢 style kit 鏀瑰彉鍗＄墖鑳屾櫙銆佹枃瀛楀拰 tag
- [x] R2.3 `ReplayProgressBar` 鎺ユ敹 style 鍙傛暟锛岃繘搴︽潯鍜屾爣绛鹃厤鑹插彲閰嶇疆
- [x] R2.4 `TripReplayPage` 搴曢儴鎺у埗鏍忋€佸睆钂欍€佸崱鐗囨敼涓鸿鍙?style kit
- [~] R2.5 鍦板浘 polyline 鏍峰紡鍏堟帴鍏?width锛涢鑹插洜 MapKit overlay 娓呯悊鑳藉姏闄愬埗锛屼繚鐣欎负涓嬩竴娆¤繘鍏ョ敓鏁堢殑娓愯繘澧炲己
- [x] R2.6 `ReplaySettingsSheet` 鎵╁睍涓虹粺涓€璁剧疆鍏ュ彛锛孲tyle 閫夋嫨绔嬪嵆鐢熸晥
- [x] R2.7 `TripDetailPage` 鏂板鈥滃洖鏀鹃璁锯€濇憳瑕佸崱鐗囷紝鍏ュ彛鍓嶅彲鏌ョ湅褰撳墠椋庢牸/闊充箰/婊ら暅/杞満
## 2026-05-07 Replay 澧炲箍 Phase 3

- [x] R3.1 `ReplayEffectOptions` 鎵╁睍涓?none / film / warm / cool / mono 婊ら暅鐩綍锛岃矾绾跨骇鏈湴鎸佷箙鍖栧凡鎺ラ€?
- [x] R3.2 鐓х墖鍖哄煙婊ら暅浣跨敤鍥捐薄鍙犲姞灞傚疄鐜版垚鏈彲鎺х殑棰滆壊鍊惧悜
- [x] R3.3 璇︽儏灞傛敮鎸佲€滅幓鐠冣€濋鏍兼ā寮忥紙鍗婇€忔槑闈㈡澘闄嶇骇锛屼笉寮曞叆楂橀闄╃殑 blur API锛?
- [x] R3.4 鑺傜偣鍒拌揪鏃跺彲閫夋尝绾规晥鏋滃凡鍦?TripReplayPage 鎺ュ叆
- [x] R3.5 Replay 鍐呴〉鍜?TripDetailPage 鍧囨柊澧炵壒鏁堟憳瑕佸弽棣堬紝涓嶅啀鏄粯榛樼殑榛戠寮€鍏?
## 2026-05-07 Replay 澧炲箍 Phase 4

- [x] R4.1 杞満鏋氫妇鍜?UI 宸插湪 Phase 2/3 鍩虹涓婅繛閫氾紝鏀寔 fade / slide / scale 涓夌妯″紡
- [x] R4.2 `TripReplayPage` 鍗＄墖鍏ュ満/鍑哄満鍔ㄧ敾宸叉妽璞′负 opacity / scale / translate 鍙橀噺
- [x] R4.3 slide 杞満鍦ㄨ嚜鍔ㄦ挱鏀惧拰鎵嬪姩璺宠浆鍦烘櫙涓嬪潎鐢熸晥
- [x] R4.4 scale 杞満鍦ㄨ嚜鍔ㄦ挱鏀惧拰鎵嬪姩璺宠浆鍦烘櫙涓嬪潎鐢熸晥
- [x] R4.5 涓婁竴鑺傜偣 / 涓嬩竴鑺傜偣 / 杩涘害鏉¤烦杞凡瀵归綈鍒板悓涓€濂楄浆鍦洪€昏緫锛屼笉鍐嶇洿鎺ョ獊鍏鍒囨崲
