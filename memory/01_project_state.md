# Project State

**Last Updated**: 2026-04-16 (云同步 + UI 页面更新合并)
**Project**: TravelPin - HarmonyOS Travel Journal App
**Repository**: D:\Mydata\1University\3Junior\Software_Engineering\frontendv1\team-project-26spring-26s-7
**Current Branch**: incremental-dev-20260329
**Main Branch**: main

---

## 1. 分支架构 (2026-04-16 更新)

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

分支说明:
- main: 生产分支，保持稳定
- incremental-dev-20260329: 长期开发分支，功能完成后合并回 main
- feature/*: 功能分支，完成后合并到 incremental
```

---

## 2. 当前架构状态 (2026-04-16 更新)

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

**编译状态**: ✅ BUILD SUCCESSFUL (2026-04-05 验证)

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
| **社交分享** | SharePage, QRCodeShare | ✅ 完整 | 分享链接、平台选择、二维码占位 |
| **个人中心** | ProfileView, ProfileEditPage | ✅ 完整 | 用户信息、设置、编辑资料 |
| **照片选择** | PhotoSelector, PhotoPickerUtil | ✅ 完整 | 系统相册选择、沙箱存储、网格展示、删除、自动清理 |
| **认证** | AuthProvider, LoginPage | ✅ 完整 | 华为账号 SDK 集成 (2026-04-16) |
| **云同步** | CloudSyncService, SyncManager | ✅ 完整 | 云数据库 + 云存储 + 同步队列 (2026-04-16) |

**已删除**:
- `ShareSelectPage.ets` - 无触发入口，已移除

---

## 4. 近期合并记录 (2026-04-16)

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
