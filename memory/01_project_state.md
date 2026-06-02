# Project State

**Last Updated**: 2026-06-02
**Project**: TravelPin - HarmonyOS Travel Journal App
**Repository**: D:\Mydata\1University\3Junior\Software_Engineering\project\frontendv1\team-project-26spring-26s-7
**Current Branch**: incremental-dev-20260423
**Main Branch**: main

**2026-06-02 Durable Notes**:
- The repository licensing metadata was aligned for public visibility: a root `LICENSE` file now declares a proprietary "all rights reserved" style license for TravelPin instead of MIT.
- `README.md` now points to the proprietary license and a new `THIRD_PARTY_NOTICES.md` template for tracking redistributed third-party components and assets.

**2026-05-19 Durable Notes**:
- The local branch history was soft-reset back to `ac53184` so the requested commits are no longer in local history, while the code changes remain in the working tree / index.
- The requested commit hashes were `730bf8d4838a9cc6c0b0f7b8d851c26e9b1baa87`, `172ee5dae8188f38d5f0b2bfbc4c95dafb0c09c9`, `6e241db4fd213938dfe2572581d3ee65f6be2e60`, `6b64868c3b9ae25a189f4b9b7e7720bc835d416c`, and `f28777531147ec66e4559637b53bd2c2849542df`.

**2026-05-06 Durable Notes**:
- Trip sharing now requires `Trip.isPublic === true`. Private trips show a greyed share button on `TripDetailPage`; tapping it prompts the user to switch the trip to public before routing to `SharePage`.
- `SharePage` now blocks direct entry for private trips as a frontend guardrail.

---

## 1. 分支架构 (2026-05-06 更新)

```
origin/main ──────────────────────────────────────────────►
    │
    ├── origin/incremental-dev-20260329 ◄───────────────── 【当前开发主线】
    │       │                                              领先 main 46 个提交
    │       ├── origin/feature/photo ─────► 已合并 ✓
    │       ├── origin/feature/trip-replay ─► 已合并 ✓
    │       ├── origin/feature1 ──────────► 已合并 ✓
    │       ├── origin/feature/cloud ─────► 已合并 ✓ (登录 + 云同步)
    │       └── origin/feature/new_page ──► 已合并 ✓ (UI 页面更新)
    │
    ├── origin/frontend ─────────────────► 孤立分支 (可删除)
    │
    └── origin/前端设计测试2026/3/20 ────► 已合并 (可删除)

当前开发重点:
- `feature/social-share`: 社交分享模块开发主线。
- 本地已合并远端多档有效期与自动撤销旧链接提交，merge commit: `def52e1`。
- 合并后本地分支相对 `origin/feature/social-share` ahead 2。

历史说明:
- `incremental-dev-20260329` 曾作为 4 月份长期开发主线，已不再代表当前会话工作分支。
- `main` 仍作为稳定分支。
```

---

## 2. 当前架构状态 (2026-05-06 更新)

**三层架构**: 已完成 (2026-03-29)
**云同步架构**: 已完成 (2026-04-16)
**UI 页面更新**: 已完成 (2026-04-16)

```
entry/src/main/ets/
├── common/                 # 公共层
│   ├── index.ets           # 统一导出入口
│   ├── utils/              # 工具类
│   │   ├── Constants.ets   # AppColors, AppDimens, RouterUrls
│   │   ├── PhotoPickerUtil.ets  # 照片选择工具
│   │   └── Logger.ets      # 日志工具
│   ├── data/               # 数据层
│   │   ├── RdbHelper.ets           # SQLite CRUD (含同步字段)
│   │   ├── TravelRepository.ets    # 旅行数据 Repository
│   │   └── MemoryNodeRepository.ets # 节点数据 Repository
│   ├── service/            # 服务层
│   │   ├── IDataService.ets
│   │   ├── RdbDataService.ets
│   │   ├── MockDataService.ets
│   │   └── types.ets       # 数据模型
│   ├── auth/               # 认证模块 (2026-04-16)
│   │   ├── AuthProvider.ets
│   │   └── CloudStorageService.ets
│   └── sync/               # 云同步模块 (2026-04-16)
│       ├── CloudSyncService.ets    # 云数据库访问
│       ├── SyncManager.ets         # 同步队列消费器
│       ├── CloudTravel.ets         # Travel 云对象
│       └── CloudMemoryNode.ets     # MemoryNode 云对象
├── feature/
│   ├── map-travel/         # 地图旅行功能
│   │   ├── pages/          # NodeEdit, NodeDetail, TripDetail, TripReplay, LocationPicker, TripEdit (新增)
│   │   ├── views/          # MapHomeView, TripListView, NodeListView (新增)
│   │   ├── components/     # PhotoSelector, ReplayPhotoCard, ReplayProgressBar, PhotoCardOverlay
│   │   └── index.ets
│   ├── profile/            # 个人中心功能
│   ├── social-share/       # 社交分享功能
│   └── ai-copy/            # AI 文案生成功能
└── pages/                  # Product 层页面
    ├── Index.ets
    ├── LoginPage.ets
    └── MainPage.ets
```

**路由配置**: `entry/src/main/resources/base/profile/main_pages.json`
- 已配置 11 个页面路由（新增 LocationPickerPage）

**编译状态**: ✅ `frontend/build.ps1 --mode module -p module=entry@default assembleHap` 通过 (2026-05-06)

**Agent 辅助文件状态**:
- `AGENTS.md` 是 Codex 主入口。
- `CLAUDE.md` 保留为 Claude 兼容入口，并指向 `AGENTS.md`。
- `memory/` 继续作为跨会话项目状态记录。
- 用户级 Codex skill `team-project-backend-sync` 已创建，用于复用当前项目 backend 同步流程。

---

## 3. 功能模块状态 (2026-04-04 更新)

| 功能模块 | 页面/组件 | 状态 | 说明 |
|---------|----------|------|------|
| **数据库层** | RdbHelper, TravelRepository, MemoryNodeRepository | ✅ 完整 | SQLite CRUD 实现 (含同步字段) |
| **服务层** | IDataService, RdbDataService, MockDataService | ✅ 完整 | 数据服务接口与实现 |
| **地图旅行** | MapHomeView, NodeEditPage, NodeDetailPage | ✅ 完整 | 地图展示、节点编辑/详情 |
| **地图选点** | LocationPickerPage | ✅ 完整 | 地图点击选点、AppStorage 传值 |
| **旅行路线** | TripListView, TripDetailPage | ✅ 完整 | 列表、详情 |
| **旅行编辑** | TripEditPage | ✅ 完整 | 旅行编辑页面 (2026-04-16 新增) |
| **节点列表** | NodeListView | ✅ 完整 | 节点列表视图 (2026-04-16 新增) |
| **动态旅程回放** | TripReplayPage, ReplayPhotoCard, ReplayProgressBar, PhotoCardOverlay | ✅ 完整 | 已适配数据库，动画回放完整 |
| **AI 文案** | AiCopyPage, AiCopyGenerator | ✅ 完整 | 5 种风格、3 种长度 |
| **社交分享** | SharePage, ShareService, SharePhotoHelper, SharePreflight | 🔄 模块 1 基本打通 | EXIF 清洗、预检、错误映射、多档有效期、切档撤销旧链接；待 cloud-only 自动回源与测试补充 |
| **个人中心** | ProfileView, ProfileEditPage | ✅ 完整 | 用户信息、设置、编辑资料 |
| **照片选择** | PhotoSelector, PhotoPickerUtil | ✅ 完整 | 系统相册选择、沙箱存储、网格展示、删除、自动清理 |
| **认证** | AuthProvider, LoginPage | ✅ 完整 | 华为账号 SDK 集成 (2026-04-16) |
| **云同步** | CloudSyncService, SyncManager | ✅ 完整 | 云数据库 + 云存储 + 同步队列 (2026-04-16) |

**已删除**:
- `ShareSelectPage.ets` - 无触发入口，已移除

---

## 4. Social Share Module 1 状态 (2026-05-06)

**当前 merge commit**: `def52e1`

**已完成**:
- 前端从 RDB 读取 trip + nodes，并构造 `SharePublishRequest`。
- 图片发布前通过 `SharePhotoHelper.prepareSharePhotos()` 生成 EXIF 清洗后的临时 JPEG。
- 遇到 `cloud-only`、本地照片缺失、清洗失败时通过 `SharePreflight` 阻止发布，不再静默丢图。
- 预检覆盖节点数、图片数量、单图体积、总请求体体积、有效期范围。
- 前端错误文案已统一映射前端预检错误与后端错误码。
- 远端多档有效期已合并：5 分钟测试、1 天、7 天、30 天。
- 切换有效期时通过 `ReplaceLink` 自动撤销上一条链接。

**关键设计决策**:
- 缓存源数据 `cachedReq + cachedNodes`。
- 不跨发布缓存清洗后的 `SharePhoto[]`，因为临时文件会在每次发布后清理。
- 每次 publish 或切换有效期都重新从源节点生成清洗临时图片。
- `finally` 中清理本次生成的临时图片。

**后端契约**:
- 最新 backend 支持 `expiryMinutes` 优先于 `expiryHours`。
- 最新 backend 支持 `replaceShortCode/replaceExpiry/replaceSig`。
- 最新 backend `PublishOk` 返回 `sig`，前端不再需要解析 URL。

**后续任务**:
- 增加分享发布阶段提示。
- 实现 `cloud-only` 自动下载回源策略。
- 为 `SharePhotoHelper`、`SharePreflight`、`ShareService` 补测试。

---

## 5. 近期合并记录 (2026-04-16)

### 合并 feature/cloud → incremental-dev-20260329 (2026-04-16)

**合并点**: `caf00f8`

**主要功能**:
- 华为账号认证 (HWID 登录/登出)
- 云存储服务 (照片上传到华为云 OBS)
- 云数据库同步 (TravelPinZone)
- 同步队列机制 (sync_queue)
- 网络连接监测与 UI 提醒

**新增文件**:
- `common/auth/AuthProvider.ets`
- `common/auth/CloudStorageService.ets`
- `common/sync/CloudSyncService.ets`
- `common/sync/SyncManager.ets`
- `common/sync/CloudTravel.ets`
- `common/sync/CloudMemoryNode.ets`

**修改文件**:
- `RdbHelper.ets` - 扩展同步字段 (owner_uid, cloud_id, sync_status, deleted_at, version)
- `TravelRepository.ets` - 增加 owner_uid 过滤、同步字段映射
- `MemoryNodeRepository.ets` - 增加 photo_manifest 与软删除语义
- `ProfileView.ets` - 显示真实待同步数量，接入 SyncManager

**测试状态**: 登录 + 云同步完成，基本测试通过

---

### 合并 feature/new_page → incremental-dev-20260329 (2026-04-16)

**合并点**: `3ce3b95` (PR #105)

**主要功能**:
- TripEditPage 旅行编辑页面
- NodeListView 节点列表视图
- 瀑布式旅行列表展示
- 地图真实搜索选点流程 (MapKit)

**新增文件**:
- `feature/map-travel/pages/TripEditPage.ets` (488 行)
- `feature/map-travel/views/NodeListView.ets` (312 行)

**修改文件**:
- `NodeDetailPage.ets` - 加载 UI 优化
- `NodeEditPage.ets` - 旅行选择器 UI 更新
- `MapHomeView.ets` - 地图搜索功能增强
- `MainPage.ets` - 页面导航更新
- `main_pages.json` - 路由配置更新

**资源文件**:
- `search_destination_marker.png` - 搜索目的地标记

---

### 合并 feature/trip-replay → incremental-dev-20260329 (2026-04-04)

**合并内容**:
- TripReplayPage 适配数据库接口 (getDataService)
- 新增 convertToReplayRoute() 转换方法
- 保留 ReplayPhotoCard、ReplayProgressBar、PhotoCardOverlay 组件
- 新增 6 张占位图片资源 (photo_1~6.jpg)
- 修复签名证书路径配置

**合并冲突解决**:
- feature/map-travel/index.ets - 合并两分支导出
- TripReplayPage.ets - 完全重写，结合数据库+UI组件

### 合并丢失修复

**问题描述**: 合并后地图选点按钮点击无反馈
**根因**: PR #102 (地图选点功能) 的代码被合并覆盖丢失

**恢复内容**:
- LocationPickerPage.ets - 从 058d85b 提交恢复
- RouterUrls.LOCATION_PICKER 常量
- NodeEditPage.onPageShow() 方法
- onClick 事件绑定
- main_pages.json 路由配置

---

## 5. Git Commits (最近)

**当前 HEAD**: `d1bfbac` (等待 git fetch 后更新到 `3ce3b95`)

### 远端最新提交 (origin/incremental-dev-20260329):
- `3ce3b95` - Merge PR #105 (feature/new_page)
- `2307ee0` - Merge branch 'incremental-dev-20260329' into feature/new_page
- `abf278f` - feat: add cloud sync and page updates
- `20291d2` - 加了部分小功能界面，以及两个地图搜索 bug
- `e5e1aa1` - 添加瀑布式旅行列表
- `7c96e80` - feat: 支持地图真实搜索选点流程
- `caf00f8` - Merge branch 'feature/cloud'
- `df622f2` - Delete .mcp.json
- `565bdaa` - Add Huawei profile auth and sync details
- `63d72ab` - Support user avatar in auth and profile view
- `415e818` - 登录 + 云同步完成，基本测试通过

### 本地提交:
- `d1bfbac` - chore: 从 git 追踪中移除 .codex_npm_cache 目录和 .mcp.json
- `0e82f33` - docs: 建立测试体系，添加 P0/P1/P2 优先级测试清单
- `c515563` - Merge branch 'feature/photo'
- `7096512` - Merge pull request #104 from sustech-cs304/feature1
## 2026-05-19 Update

- ArkTS compile blockers were fixed in the current working tree:
  - `TripListView.ets` now uses `TransitionEffect.OPACITY`.
  - `AiCopyPage.ets` now imports `LengthMetrics` from `@kit.ArkUI` and uses `LengthMetrics.vp(8)` for Flex spacing.
- `frontend/build.ps1 --mode module -p module=entry@default assembleHap` succeeds again; remaining diagnostics are pre-existing warnings.
