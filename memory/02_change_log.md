# Change Log

**Last Updated**: 2026-05-19

## 2026-05-19

- [2026-05-19] - REWRITE - `git reset --soft f287775^` - Removed the requested commit suffix from local history while keeping all code changes in the working tree / index.

---

## 2026-05-06

- [2026-05-06] - FIX - `feature/map-travel/pages/TripDetailPage.ets` - 私密路线分享入口改为灰态可点，点击后弹窗确认转公开；确认后先更新 `isPublic` 再跳转分享页
- [2026-05-06] - FIX - `feature/social-share/pages/SharePage.ets` - 增加私密路线前端兜底，阻止直接进入分享页时绕过公开限制

---

## 2026-04-16 (云同步 + 认证功能合并 / UI 页面更新)

### 合并 feature/cloud → incremental-dev-20260329 (PR #105 前置合并)

**合并点**: `caf00f8`

- [2026-04-16-05-28-06] - MERGE - feature/cloud → incremental-dev-20260329 - 完成登录认证与云同步功能集成 - caf00f8

**主要功能**:
1. **华为账号认证** - 支持 HWID 登录/登出、用户头像获取
2. **云存储服务** - 照片/数据上传到华为云对象存储 (OBS)
3. **云数据库同步** - TravelPinZone 云数据库，支持 Travel/MemoryNode 上行同步
4. **同步队列机制** - sync_queue 记录本地变更，支持手动/启动时触发上行
5. **网络连接监测** - 网络状态变化时 UI 提醒
6. **调试日志** - 关键操作日志输出，便于问题定位

**新增文件**:
- `common/auth/` - 认证模块 (AuthProvider, CloudStorageService 等)
- `common/sync/CloudSyncService.ets` - 云数据库访问封装
- `common/sync/SyncManager.ets` - 同步队列消费器
- `common/sync/CloudTravel.ets` - Travel 云对象类型
- `common/sync/CloudMemoryNode.ets` - MemoryNode 云对象类型

**修改文件**:
- `RdbHelper.ets` - 扩展 owner_uid/cloud_id/sync_status/deleted_at/version 字段
- `TravelRepository.ets` - 增加 owner_uid 过滤、同步字段映射
- `MemoryNodeRepository.ets` - 增加 photo_manifest 与软删除语义
- `ProfileView.ets` - 显示真实待同步数量，"立即同步"按钮接入 SyncManager

**测试状态**: 登录 + 云同步完成，基本测试通过 (commit 415e818)

---

### 合并 feature/new_page → incremental-dev-20260329 (PR #105)

**合并点**: `3ce3b95`

- [2026-04-16-05-28-06] - MERGE - feature/new_page → incremental-dev-20260329 - 新增 UI 页面与地图搜索功能 - 3ce3b95

**主要功能**:
1. **TripEditPage** - 旅行编辑页面 (488 行新增)
2. **NodeListView** - 节点列表视图 (312 行新增)
3. **瀑布式旅行列表** - 双列瀑布流展示旅行封面 (e5e1aa1)
4. **地图真实搜索选点** - 接入 MapKit 地点搜索 API (7c96e80)
5. **搜索目的地标记** - 新增 search_destination_marker.png 资源

**修改文件**:
- `TripEditPage.ets` - 新增旅行编辑页面
- `NodeListView.ets` - 新增节点列表视图
- `NodeDetailPage.ets` - 加载 UI 优化
- `NodeEditPage.ets` - 旅行选择器 UI 更新
- `MapHomeView.ets` - 地图搜索功能增强
- `MainPage.ets` - 页面导航更新
- `main_pages.json` - 路由配置更新

---

### feature1 分支更新合并

**提交范围**: `bb8dfd3` → `20291d2`

- [2026-04-14-14-29-35] - FEAT - feature1 - 加了部分小功能界面，以及两个地图搜索 bug - 20291d2
- [2026-04-14] - FEAT - feature1 - 添加瀑布式旅行列表 - e5e1aa1
- [2026-04-14] - FEAT - feature1 - 支持地图真实搜索选点流程 - 7c96e80

**涉及变更**: 21 个文件，1640 行新增，600 行删除

---

---

## Format
```
[YYYY-MM-DD-HH-MM-SS] - [Action] - [Location] - [Description] - [Git Commit]
```

---

## 2026-04-12 (旅行相册瀑布流页面)
### 2026-04-12 (登录与云同步架构文档更新)

- [2026-04-12-02-01-53] - UPDATE - frontend/docs/sync-architecture.md - 重写登录与云同步架构文档，补充自动增量同步、手动全量纠偏、云数据库/云存储职责、photoManifest 规则与测试清单 - uncommitted

- [2026-04-09-01-52-32] - UPDATE - frontend/entry/src/main/ets/common/auth/CloudStorageService.ets - 对齐 sample：云存储初始化前先 signOut，再用 hwid 重新 signIn 并记录会话重建日志，修复上传 403 的候选根因 - uncommitted
- [2026-04-09-01-52-32] - BUILD - frontend/.preview - PreviewBuild 编译验证通过，BUILD SUCCESSFUL in 15 s 673 ms - uncommitted
- [2026-04-09-13-34-15] - UPDATE - frontend/entry/src/main/ets/common/auth/CloudStorageService.ets - 上传前将 filesDir 照片复制到 cacheDir，并按云存储 SDK 要求传递 cache 相对路径，修复真机上传 403 - uncommitted
- [2026-04-09-13-34-15] - BUILD - frontend/.preview - PreviewBuild 编译验证通过，BUILD SUCCESSFUL in 13 s 760 ms - uncommitted
- [2026-04-09-13-40-31] - UPDATE - frontend/entry/src/main/ets/common/auth/CloudStorageService.ets - 增加 AuthProvider token 诊断日志，确认上传前凭据可获取，辅助排查真机 403 - uncommitted
- [2026-04-09-13-40-31] - BUILD - frontend/.preview - PreviewBuild 编译验证通过，BUILD SUCCESSFUL in 8 s 572 ms - uncommitted
- [2026-04-09-13-41-00] - VERIFY - 华为云存储真机上传 - 真机验证通过，文件成功写入 users/1916859267856523328/travels/1/nodes/1/ - uncommitted
- [2026-04-09-14-38-02] - UPDATE - frontend/entry/src/main/ets/common/data/RdbHelper.ets - 为 travels/memory_nodes 扩展 owner_uid/cloud_id/sync_status/deleted_at/version 等同步字段，并补充 sync_queue 读写接口 - uncommitted
- [2026-04-09-14-38-02] - UPDATE - frontend/entry/src/main/ets/common/data/TravelRepository.ets - 增加 owner_uid 过滤、同步字段映射与旅行软删除语义 - uncommitted
- [2026-04-09-14-38-02] - UPDATE - frontend/entry/src/main/ets/common/data/MemoryNodeRepository.ets - 增加节点同步字段映射、photo_manifest 与节点软删除语义 - uncommitted
- [2026-04-09-14-38-02] - UPDATE - frontend/entry/src/main/ets/common/service/RdbDataService.ets - 本地 CRUD 后写入 sync_queue，并让 Profile 同步状态读取真实待同步数量 - uncommitted
- [2026-04-09-14-38-02] - UPDATE - frontend/entry/src/main/ets/feature/profile/views/ProfileView.ets - 用真实 sync_queue 数量替换占位同步状态展示 - uncommitted
- [2026-04-09-14-38-02] - BUILD - frontend/.preview - PreviewBuild 编译验证通过，BUILD SUCCESSFUL in 8 s 278 ms - uncommitted
- [2026-04-09-14-39-02] - CREATE - frontend/entry/src/main/resources/rawfile/schema.json - 引入 TravelPinZone 云数据库 schema 文件，准备客户端接入 - uncommitted
- [2026-04-09-14-39-02] - CREATE - frontend/entry/src/main/ets/common/sync/CloudTravel.ets - 新增 Travel 云数据库对象类型类 - uncommitted
- [2026-04-09-14-39-02] - CREATE - frontend/entry/src/main/ets/common/sync/CloudMemoryNode.ets - 新增 MemoryNode 云数据库对象类型类 - uncommitted
- [2026-04-09-14-39-02] - CREATE - frontend/entry/src/main/ets/common/sync/CloudSyncService.ets - 新增 TravelPinZone 云数据库访问封装，支持 Travel/MemoryNode 上行 upsert/delete - uncommitted
- [2026-04-09-14-39-02] - CREATE - frontend/entry/src/main/ets/common/sync/SyncManager.ets - 新增 sync_queue 消费器，支持手动/启动时触发上行同步 - uncommitted
- [2026-04-09-14-39-02] - UPDATE - frontend/entry/src/main/ets/common/index.ets - 导出 CloudSyncService 与 SyncManager - uncommitted
- [2026-04-09-14-39-02] - UPDATE - frontend/entry/src/main/ets/entryability/EntryAbility.ets - 云存储恢复成功后自动触发 SyncManager 上行同步 - uncommitted
- [2026-04-09-14-39-02] - UPDATE - frontend/entry/src/main/ets/feature/profile/views/ProfileView.ets - “立即同步”按钮接入 SyncManager.triggerNow() - uncommitted
- [2026-04-09-14-39-02] - BUILD - frontend/.preview - PreviewBuild 编译验证通过，BUILD SUCCESSFUL in 9 s 234 ms - uncommitted

---

## 2026-04-08 (feature/photo 合并到 incremental-dev-20260329)

### 合并 feature/photo → incremental-dev-20260329

- [2026-04-08-15-55-09] - BACKUP - 本地分支 - 创建备份分支 backup-feature-photo-20260408155509, backup-incremental-dev-20260408155509
- [2026-04-08-16-00-00] - FETCH - origin/incremental-dev-20260329 - 拉取远端最新提交 (2 个新提交: 7096512, bb8dfd3)
- [2026-04-08-16-05-00] - MERGE - feature/photo → incremental-dev-20260329 - 合并照片选择功能
- [2026-04-08-16-10-00] - RESOLVE - RdbDataService.ets - 手动解决冲突：合并错误检查 + 照片清理逻辑
- [2026-04-08-16-15-00] - RESOLVE - NodeEditPage.ets - 手动解决冲突：合并旅行选择器 + PhotoSelector 组件
- [2026-04-08-16-20-00] - BUILD - 编译验证通过 - BUILD SUCCESSFUL in 2 min 46 s
- [2026-04-08-16-25-00] - GIT - c515563 - Merge branch 'feature/photo' into incremental-dev-20260329: 照片功能集成

**新增文件**:
- PhotoPickerUtil.ets - 沙箱照片选择与存储工具
- PhotoSelector.ets - 照片选择网格组件

**修改文件**:
- RdbDataService.ets - 添加照片自动清理逻辑 (updateNode/deleteNode)
- NodeEditPage.ets - 集成 PhotoSelector 组件，保留旅行选择器功能
- NodeDetailPage.ets - 照片轮播显示
- ReplayPhotoCard.ets - 多张照片轮播支持
- PhotoCardOverlay.ets - 多张照片轮播支持

### 远端分支清理建议

| 分支 | 状态 | 建议 |
|------|------|------|
| origin/frontend | 孤立分支，无共同祖先 | 可删除 |
| origin/前端设计测试2026/3/20 | 已完全合并到 incremental | 可删除 |
| origin/feature/photo | 已合并到 incremental | 可删除 |

---

## 2026-04-05 (照片选择与沙箱存储功能)

### Phase 6: NodeDetailPage 照片轮播

- [2026-04-05-15-20-00] - FIX - NodeDetailPage.ets - 照片区域从占位符改为 Swiper 组件实际展示照片
- [2026-04-05-15-25-00] - FIX - NodeDetailPage.ets - 修复 SwiperIndicator 类型错误，改为 Indicator.dot()
- [2026-04-05-15-25-05] - BUILD - assembleHap 编译验证通过

### Phase 7: Replay 照片策略优化

- [2026-04-05-15-35-00] - UPDATE - types.ets - ReplayNode.photoUri 改为 photos: string[]，支持多张照片
- [2026-04-05-15-35-10] - UPDATE - TripReplayPage.ets - 移除 resolvePhotoUri 方法，直接传递照片数组
- [2026-04-05-15-35-20] - UPDATE - ReplayPhotoCard.ets - 支持 Swiper 多张照片轮播，无照片显示占位符
- [2026-04-05-15-35-30] - UPDATE - PhotoCardOverlay.ets - 支持 Swiper 多张照片轮播，显示照片数量
- [2026-04-05-15-35-40] - BUILD - assembleHap 编译验证通过

### Phase 1: PhotoPickerUtil 工具类

- [2026-04-05-14-30-10] - CREATE - common/utils/PhotoPickerUtil.ets - 照片选择与沙箱存储工具类
- [2026-04-05-14-30-15] - UPDATE - common/index.ets - 添加 PhotoPickerUtil 导出

### Phase 2: PhotoSelector UI 组件

- [2026-04-05-14-31-00] - CREATE - feature/map-travel/components/PhotoSelector.ets - 照片选择器组件（网格展示、添加/删除按钮、最多 9 张）

### Phase 3: NodeEditPage 集成

- [2026-04-05-14-32-30] - UPDATE - NodeEditPage.ets - 导入 PhotoSelector 组件
- [2026-04-05-14-32-45] - UPDATE - NodeEditPage.ets - 替换照片选择区域为 PhotoSelector 组件
- [2026-04-05-14-32-50] - UPDATE - NodeEditPage.ets - 删除 handlePickPhoto() 占位方法

### Phase 4: Replay 照片展示

- [2026-04-05-14-33-00] - VERIFY - TripReplayPage.resolvePhotoUri() - 确认已支持从 photos[] 获取照片

### Phase 5: 照片清理

- [2026-04-05-14-34-00] - UPDATE - RdbDataService.ets - 导入 PhotoPickerUtil
- [2026-04-05-14-34-10] - UPDATE - RdbDataService.updateNode() - 更新时清理被移除的照片
- [2026-04-05-14-34-20] - UPDATE - RdbDataService.deleteNode() - 删除节点时清理所有关联照片

---

## 2026-04-04 (分支合并与功能修复)

### 合并 feature/trip-replay → incremental-dev-20260329

- [2026-04-04-14-38-21] - MERGE - feature/trip-replay → incremental-dev-20260329 - 合并旅程回放功能，适配数据库接口 (d4602bb)
- [2026-04-04] - UPDATE - TripReplayPage.ets - 使用 getDataService() 从数据库加载 MemoryNode
- [2026-04-04] - CREATE - convertToReplayRoute() - 新增转换方法 MemoryNode → ReplayNode
- [2026-04-04] - PRESERVE - ReplayPhotoCard.ets - 保留照片卡片组件
- [2026-04-04] - PRESERVE - ReplayProgressBar.ets - 保留进度条组件
- [2026-04-04] - PRESERVE - PhotoCardOverlay.ets - 保留照片展开覆盖层
- [2026-04-04] - CREATE - resources/base/media/photo_1~6.jpg - 新增 6 张占位图片资源
- [2026-04-04] - RESOLVE - feature/map-travel/index.ets - 解决合并冲突，合并两分支导出
- [2026-04-04] - RESOLVE - TripReplayPage.ets - 完全重写，结合数据库+UI组件

### 签名证书路径修复

- [2026-04-04-15-12-00] - FIX - build-profile.json5 - 证书路径从绝对路径改为相对路径 (8b5a775)
- [2026-04-04] - UPDATE - storeFile: "../certificates/1.p12" - 团队协作友好配置
- [2026-04-04] - UPDATE - profile: "../certificates/testDebug.p7b"
- [2026-04-04] - UPDATE - certpath: "../certificates/test.cer"

### 地图选点功能恢复（合并丢失修复）

- [2026-04-04-15-40-00] - FIX - LocationPickerPage.ets - 恢复丢失的地图选点页面 (3b0251d)
- [2026-04-04] - CREATE - LocationPickerPage.ets - 从 PR #102 (058d85b) 恢复完整文件
- [2026-04-04] - UPDATE - Constants.ets - 添加 RouterUrls.LOCATION_PICKER 路由常量
- [2026-04-04] - UPDATE - NodeEditPage.ets - 添加 onPageShow() 接收选点返回数据
- [2026-04-04] - UPDATE - NodeEditPage.ets - "重新选点 >"按钮绑定 onClick 事件
- [2026-04-04] - UPDATE - NodeEditPage.ets - latitude/longitude 改为 @State 状态变量
- [2026-04-04] - UPDATE - main_pages.json - 添加 LocationPickerPage 路由配置
- [2026-04-04] - UPDATE - feature/map-travel/index.ets - 导出 LocationPickerPage
- [2026-04-04-15-40-37] - BUILD - 编译验证通过 - BUILD SUCCESSFUL in 12 s 376 ms

### 合并丢失根因分析

**问题：合并后地图选点按钮点击无反馈**
- 根因：合并 feature/trip-replay 时，PR #102 (地图选点功能) 的关键代码被覆盖丢失
- 丢失文件：LocationPickerPage.ets 整个文件
- 丢失常量：RouterUrls.LOCATION_PICKER
- 丢失方法：NodeEditPage.onPageShow() 和 onClick 事件绑定
- 解决：从 git 历史 (058d85b) 恢复所有丢失内容

---

## 2026-04-03 (动态旅程回放功能 bug 修复)

- [2026-04-12-21-25-53] - CREATE - feature/map-travel/views/TripAlbumView.ets - 新增旅行相册 Tab 视图，双列瀑布流展示旅行封面（首节点首图），点击跳转 TripDetailPage
- [2026-04-12-21-25-53] - UPDATE - pages/MainPage.ets - 底部 Tabs 新增第 4 个并列 Tab「相册」，接入 TripAlbumView
- [2026-04-12-21-25-53] - UPDATE - feature/map-travel/index.ets - 导出 TripAlbumView 供页面层引用
- [2026-04-12-21-25-53] - BUILD - 编译验证未执行 - 当前环境缺少 DevEco 依赖路径（C:\Apps 与 D:\software 均不存在对应 node.exe）

---

## 2026-04-10 (Map Kit 地点搜索替换)

- [2026-04-10-12-04-00] - UPDATE - feature/map-travel/pages/LocationPickerPage.ets - 用 @kit.MapKit.site.searchByText 替换硬编码地点搜索，保留坐标输入选点
- [2026-04-10-12-04-00] - UPDATE - feature/map-travel/pages/LocationPickerPage.ets - 新增 site.reverseGeocode 地图点选地址解析，失败时回退经纬度标签
- [2026-04-10-12-04-00] - UPDATE - feature/map-travel/pages/LocationPickerPage.ets - 增加搜索中/空结果提示与搜索失败 toast，并用轻量接口规避 site 返回类型编译不确定性
- [2026-04-10-12-30-00] - UPDATE - feature/map-travel/views/MapHomeView.ets - 将首页静态搜索栏改为可输入搜索框，支持本地记忆节点标题/地点/标签搜索
- [2026-04-10-12-30-00] - UPDATE - feature/map-travel/views/MapHomeView.ets - 接入 @kit.MapKit.site.searchByText 合并 POI 结果，去重后展示首页搜索列表
- [2026-04-10-12-30-00] - UPDATE - feature/map-travel/views/MapHomeView.ets - 选中首页搜索结果后联动地图相机，节点结果同步打开底部预览卡片
- [2026-04-10-12-36-00] - UPDATE - feature/map-travel/views/MapHomeView.ets - 在首页搜索栏右侧补回“新增”按钮，保留从地图主页直达 NodeEditPage 的入口
- [2026-04-10-12-45-00] - UPDATE - common/service/types.ets - 为 RouterParam 增加 poiName，支持从首页搜索结果直接带地址进入 NodeEditPage
- [2026-04-10-12-45-00] - UPDATE - feature/map-travel/pages/NodeEditPage.ets - 新建节点时优先读取路由传入的 poiName，避免仅显示经纬度
- [2026-04-10-12-45-00] - UPDATE - feature/map-travel/views/MapHomeView.ets - 选中首页搜索结果后保留选中态，隐藏误报空结果提示，并提供“作为地址新建”入口
- [2026-04-10-12-52-00] - UPDATE - feature/map-travel/views/MapHomeView.ets - 精简搜索栏右侧按钮，仅保留“用该地址新建记忆”，移除冗余新增入口
- [2026-04-10-13-00-00] - UPDATE - feature/map-travel/views/MapHomeView.ets - 选中首页搜索结果后立即在地图上打点，高亮当前待新建地址位置

### 2026-04-12 (登录与云同步架构文档更新)

- [2026-04-12-02-01-53] - UPDATE - frontend/docs/sync-architecture.md - 重写登录与云同步架构文档，补充自动增量同步、手动全量纠偏、云数据库/云存储职责、photoManifest 规则与测试清单 - uncommitted

- [2026-04-09-01-52-32] - UPDATE - frontend/entry/src/main/ets/common/auth/CloudStorageService.ets - 对齐 sample：云存储初始化前先 signOut，再用 hwid 重新 signIn 并记录会话重建日志，修复上传 403 的候选根因 - uncommitted
- [2026-04-09-01-52-32] - BUILD - frontend/.preview - PreviewBuild 编译验证通过，BUILD SUCCESSFUL in 15 s 673 ms - uncommitted
- [2026-04-09-13-34-15] - UPDATE - frontend/entry/src/main/ets/common/auth/CloudStorageService.ets - 上传前将 filesDir 照片复制到 cacheDir，并按云存储 SDK 要求传递 cache 相对路径，修复真机上传 403 - uncommitted
- [2026-04-09-13-34-15] - BUILD - frontend/.preview - PreviewBuild 编译验证通过，BUILD SUCCESSFUL in 13 s 760 ms - uncommitted
- [2026-04-09-13-40-31] - UPDATE - frontend/entry/src/main/ets/common/auth/CloudStorageService.ets - 增加 AuthProvider token 诊断日志，确认上传前凭据可获取，辅助排查真机 403 - uncommitted
- [2026-04-09-13-40-31] - BUILD - frontend/.preview - PreviewBuild 编译验证通过，BUILD SUCCESSFUL in 8 s 572 ms - uncommitted
- [2026-04-09-13-41-00] - VERIFY - 华为云存储真机上传 - 真机验证通过，文件成功写入 users/1916859267856523328/travels/1/nodes/1/ - uncommitted
- [2026-04-09-14-38-02] - UPDATE - frontend/entry/src/main/ets/common/data/RdbHelper.ets - 为 travels/memory_nodes 扩展 owner_uid/cloud_id/sync_status/deleted_at/version 等同步字段，并补充 sync_queue 读写接口 - uncommitted
- [2026-04-09-14-38-02] - UPDATE - frontend/entry/src/main/ets/common/data/TravelRepository.ets - 增加 owner_uid 过滤、同步字段映射与旅行软删除语义 - uncommitted
- [2026-04-09-14-38-02] - UPDATE - frontend/entry/src/main/ets/common/data/MemoryNodeRepository.ets - 增加节点同步字段映射、photo_manifest 与节点软删除语义 - uncommitted
- [2026-04-09-14-38-02] - UPDATE - frontend/entry/src/main/ets/common/service/RdbDataService.ets - 本地 CRUD 后写入 sync_queue，并让 Profile 同步状态读取真实待同步数量 - uncommitted
- [2026-04-09-14-38-02] - UPDATE - frontend/entry/src/main/ets/feature/profile/views/ProfileView.ets - 用真实 sync_queue 数量替换占位同步状态展示 - uncommitted
- [2026-04-09-14-38-02] - BUILD - frontend/.preview - PreviewBuild 编译验证通过，BUILD SUCCESSFUL in 8 s 278 ms - uncommitted
- [2026-04-09-14-39-02] - CREATE - frontend/entry/src/main/resources/rawfile/schema.json - 引入 TravelPinZone 云数据库 schema 文件，准备客户端接入 - uncommitted
- [2026-04-09-14-39-02] - CREATE - frontend/entry/src/main/ets/common/sync/CloudTravel.ets - 新增 Travel 云数据库对象类型类 - uncommitted
- [2026-04-09-14-39-02] - CREATE - frontend/entry/src/main/ets/common/sync/CloudMemoryNode.ets - 新增 MemoryNode 云数据库对象类型类 - uncommitted
- [2026-04-09-14-39-02] - CREATE - frontend/entry/src/main/ets/common/sync/CloudSyncService.ets - 新增 TravelPinZone 云数据库访问封装，支持 Travel/MemoryNode 上行 upsert/delete - uncommitted
- [2026-04-09-14-39-02] - CREATE - frontend/entry/src/main/ets/common/sync/SyncManager.ets - 新增 sync_queue 消费器，支持手动/启动时触发上行同步 - uncommitted
- [2026-04-09-14-39-02] - UPDATE - frontend/entry/src/main/ets/common/index.ets - 导出 CloudSyncService 与 SyncManager - uncommitted
- [2026-04-09-14-39-02] - UPDATE - frontend/entry/src/main/ets/entryability/EntryAbility.ets - 云存储恢复成功后自动触发 SyncManager 上行同步 - uncommitted
- [2026-04-09-14-39-02] - UPDATE - frontend/entry/src/main/ets/feature/profile/views/ProfileView.ets - “立即同步”按钮接入 SyncManager.triggerNow() - uncommitted
- [2026-04-09-14-39-02] - BUILD - frontend/.preview - PreviewBuild 编译验证通过，BUILD SUCCESSFUL in 9 s 234 ms - uncommitted

---

## 2026-04-08 (feature/photo 合并到 incremental-dev-20260329)

### 合并 feature/photo → incremental-dev-20260329

- [2026-04-08-15-55-09] - BACKUP - 本地分支 - 创建备份分支 backup-feature-photo-20260408155509, backup-incremental-dev-20260408155509
- [2026-04-08-16-00-00] - FETCH - origin/incremental-dev-20260329 - 拉取远端最新提交 (2 个新提交: 7096512, bb8dfd3)
- [2026-04-08-16-05-00] - MERGE - feature/photo → incremental-dev-20260329 - 合并照片选择功能
- [2026-04-08-16-10-00] - RESOLVE - RdbDataService.ets - 手动解决冲突：合并错误检查 + 照片清理逻辑
- [2026-04-08-16-15-00] - RESOLVE - NodeEditPage.ets - 手动解决冲突：合并旅行选择器 + PhotoSelector 组件
- [2026-04-08-16-20-00] - BUILD - 编译验证通过 - BUILD SUCCESSFUL in 2 min 46 s
- [2026-04-08-16-25-00] - GIT - c515563 - Merge branch 'feature/photo' into incremental-dev-20260329: 照片功能集成

**新增文件**:
- PhotoPickerUtil.ets - 沙箱照片选择与存储工具
- PhotoSelector.ets - 照片选择网格组件

**修改文件**:
- RdbDataService.ets - 添加照片自动清理逻辑 (updateNode/deleteNode)
- NodeEditPage.ets - 集成 PhotoSelector 组件，保留旅行选择器功能
- NodeDetailPage.ets - 照片轮播显示
- ReplayPhotoCard.ets - 多张照片轮播支持
- PhotoCardOverlay.ets - 多张照片轮播支持

### 远端分支清理建议

| 分支 | 状态 | 建议 |
|------|------|------|
| origin/frontend | 孤立分支，无共同祖先 | 可删除 |
| origin/前端设计测试2026/3/20 | 已完全合并到 incremental | 可删除 |
| origin/feature/photo | 已合并到 incremental | 可删除 |

---

## 2026-04-05 (照片选择与沙箱存储功能)

### Phase 6: NodeDetailPage 照片轮播

- [2026-04-05-15-20-00] - FIX - NodeDetailPage.ets - 照片区域从占位符改为 Swiper 组件实际展示照片
- [2026-04-05-15-25-00] - FIX - NodeDetailPage.ets - 修复 SwiperIndicator 类型错误，改为 Indicator.dot()
- [2026-04-05-15-25-05] - BUILD - assembleHap 编译验证通过

### Phase 7: Replay 照片策略优化

- [2026-04-05-15-35-00] - UPDATE - types.ets - ReplayNode.photoUri 改为 photos: string[]，支持多张照片
- [2026-04-05-15-35-10] - UPDATE - TripReplayPage.ets - 移除 resolvePhotoUri 方法，直接传递照片数组
- [2026-04-05-15-35-20] - UPDATE - ReplayPhotoCard.ets - 支持 Swiper 多张照片轮播，无照片显示占位符
- [2026-04-05-15-35-30] - UPDATE - PhotoCardOverlay.ets - 支持 Swiper 多张照片轮播，显示照片数量
- [2026-04-05-15-35-40] - BUILD - assembleHap 编译验证通过
- [2026-03-29] - CREATE - memory/01_project_state.md - 初始化项目状态文件（增量开发模式）
- [2026-03-29] - CREATE - memory/03_task_backlog.md - 初始化任务清单
- [2026-03-29] - CREATE - memory/02_change_log.md - 初始化变更日志
- [2026-03-29] - GIT - branches - 创建新分支 incremental-dev-20260329（增量开发）
- [2026-03-29] - ANALYSIS - A/B 分析完成 - 输出项目结构对比报告和任务优先级分析
- [2026-03-29] - TASK - backlog 更新 - 添加 Phase 1/Phase 2/Phase 3 整合计划
- [2026-03-29] - CREATE - common/index.ets - 统一导出入口文件 (AppColors, AppDimens, RouterUrls, 数据模型)
- [2026-03-29] - CREATE - common/utils/Constants.ets - 工具类常量 (AppColors, AppDimens, RouterUrls)
- [2026-03-29] - CREATE - common/service/types.ets - 数据模型类型定义 (MemoryNode, Trip, SyncStatus 等)
- [2026-03-29] - CREATE - common/oh-package.json5 - common 模块包配置
- [2026-03-29] - CREATE - feature/map-travel/ - 地图旅行功能目录 (pages/, views/)
- [2026-03-29] - CREATE - feature/profile/ - 个人中心功能目录
- [2026-03-29] - CREATE - feature/social-share/ - 社交分享功能目录
- [2026-03-29] - MOVE - NodeEditPage, NodeDetailPage, TripDetailPage, TripReplayPage → feature/map-travel/pages/
- [2026-03-29] - MOVE - MapHomeView, TripListView → feature/map-travel/views/
- [2026-03-29] - CREATE - feature/ai-copy/ - AI 文案生成功能模块目录
- [2026-03-29] - CREATE - feature/ai-copy/components/AiCopyGenerator.ets - AI 文案生成器组件
- [2026-03-29] - CREATE - feature/ai-copy/pages/AiCopyPage.ets - AI 文案页面 (5 种风格、3 种长度、提示词输入)
- [2026-03-29] - CREATE - feature/ai-copy/index.ets - AI 文案模块统一导出
- [2026-03-29] - UPDATE - main_pages.json - 添加 feature/ai-copy/pages/AiCopyPage 路由
- [2026-03-29] - UPDATE - RouterUrls - 添加 AI_COPY 路由常量
- [2026-03-29] - UPDATE - NodeEditPage.ets - 添加"AI 助手"按钮，点击跳转到 AiCopyPage
- [2026-03-29] - BUILD - 编译验证通过 (BUILD SUCCESSFUL)
- [2026-03-29] - FIX - AiCopyGenerator.ets - 修复 ArkTS 类型错误 (添加 TravelData 接口)
- [2026-03-29] - FIX - AiCopyPage.ets - 修复 ArkTS 类型错误 (添加 StyleOption 接口，router 导入，columnsTemplate 类型)
- [2026-03-29] - BUILD - 二次编译验证通过 (所有错误已修复)
- [2026-03-29] - MOVE - ProfileView → feature/profile/views/
- [2026-03-29] - MOVE - SharePage → feature/social-share/pages/
- [2026-03-29] - UPDATE - pages/Index.ets - 修复导入路径：'../common/Constants' → '../common'
- [2026-03-29] - UPDATE - views/MapHomeView.ets - 添加 RouterUrls 到导入语句
- [2026-03-29] - UPDATE - main_pages.json - 路由配置更新为 feature 层路径 (NodeEditPage 等)
- [2026-03-29] - UPDATE - feature 层 8 个文件 - 统一导入路径为'../../../common'
- [2026-03-29] - FIX - 编译错误修复 - 解决 RouterUrls 未定义、页面路径找不到等问题
- [2026-03-29] - BUILD - 编译验证成功 - BUILD SUCCESSFUL in 16s 673ms (7d1132a)
- [2026-03-29] - UPDATE - CLAUDE.md - 添加 ArkTS 编译验证工作流、缓存清理指令、终极任务
- [2026-03-29] - UPDATE - memory/01_project_state.md - 记录三层架构完成状态
- [2026-03-29] - GIT - commit 0749f15 - docs: 更新三层架构重构文档和 Memory 记录
- [2026-03-29] - CREATE - common/data/RdbHelper.ets - 数据库助手占位文件（STUB）
- [2026-03-29] - CREATE - common/data/TravelRepository.ets - 旅行数据仓库占位文件（STUB）
- [2026-03-29] - CREATE - common/data/MemoryNodeRepository.ets - 节点数据仓库占位文件（STUB）
- [2026-03-29] - CREATE - common/data/index.ets - Data Layer 统一导出
- [2026-03-29] - CREATE - common/service/IDataService.ets - 数据服务接口定义
- [2026-03-29] - CREATE - common/service/MockDataService.ets - Mock 数据服务实现
- [2026-03-29] - CREATE - common/service/DataServiceStub.ets - 数据库占位服务（空数据）
- [2026-03-29] - CREATE - common/ServiceConfig.ets - 数据源配置开关
- [2026-03-29] - CREATE - common/utils/Logger.ets - 简易日志工具类
- [2026-03-29] - UPDATE - common/index.ets - 添加 Data/Service Layer 导出
- [2026-03-29] - UPDATE - common/service/types.ets - 修复 Trip 和 MemoryNode 类型定义
- [2026-03-29] - UPDATE - TripListView.ets - 简化为硬编码数据（数据层完成前）
- [2026-03-29-18-18-27] - BUILD - 编译验证通过 - BUILD SUCCESSFUL in 17s 590ms
- [2026-03-29-18-18-00] - UPDATE - ProfileView.ets - 用户信息卡片添加"编辑"按钮入口
- [2026-03-29-18-17-55] - UPDATE - main_pages.json - 添加 ProfileEditPage 路由配置
- [2026-03-29-18-17-50] - UPDATE - Constants.ets - 添加 PROFILE_EDIT 路由常量
- [2026-03-29-18-17-45] - CREATE - feature/profile/pages/ProfileEditPage.ets - 编辑资料页面（昵称、头像、个性签名）
- [2026-03-29-17-58-00] - UPDATE - main_pages.json - 移除 ShareSelectPage 路由配置
- [2026-03-29-17-57-55] - UPDATE - social-share/index.ets - 移除 ShareSelectPage 导出
- [2026-03-29-17-57-50] - REMOVE - feature/social-share/pages/ShareSelectPage.ets - 移除分享选择页面（无触发入口）
- [2026-03-29-17-55-22] - BUILD - 编译验证通过 - BUILD SUCCESSFUL in 18s 420ms
- [2026-03-29-17-31-00] - UPDATE - main_pages.json - 添加 ShareSelectPage 路由配置
- [2026-03-29-17-30-55] - UPDATE - social-share/index.ets - 添加 ShareSelectPage 和 QRCodeShare 导出
- [2026-03-29-17-30-50] - UPDATE - SharePage.ets - 删除 AI 辅助文案区，保留分享链接、文案编辑、分享平台选择
- [2026-03-29-17-30-45] - CREATE - feature/social-share/components/QRCodeShare.ets - 二维码分享组件（含 generateShareLink 占位方法）
- [2026-03-29-17-30-40] - CREATE - feature/social-share/pages/ShareSelectPage.ets - 分享选择页面（列出所有路线供选择）
- [2026-03-29-17-16-00] - BUILD - 编译验证成功 - BUILD SUCCESSFUL in 16s 129ms
- [2026-03-30] - CREATE - common/utils/PhotoPickerUtil.ets - 照片选择工具类（封装 photoAccessHelper.PhotoViewPicker）
- [2026-03-30] - CREATE - feature/map-travel/components/PhotoSelector.ets - 照片选择器组件（网格展示、删除按钮、最多 9 张）
- [2026-03-30] - UPDATE - common/index.ets - 添加 PhotoPickerUtil 导出
- [2026-03-30] - UPDATE - feature/map-travel/index.ets - 添加 PhotoSelector 组件导出
- [2026-03-30] - UPDATE - NodeEditPage.ets - 集成 PhotoSelector 组件，移除 handlePickPhoto() 占位方法
- [2026-03-30] - CREATE - frontend/local.properties - 构建配置（SDK 路径，本地文件不提交）
- [2026-03-30] - FIX - PhotoSelector.ets - 修复 ArkTS 语法错误（RelativeStack→Stack, FlexSpaceOptions 类型）
- [2026-03-30] - FIX - PhotoPickerUtil.ets - 修复 throw 语句类型错误（ArkTS 要求 Error 类型）
- [2026-03-30] - BUILD - 编译验证通过 - BUILD SUCCESSFUL in 7s 903ms

---

## 2026-04-09 (架构文档同步)

- [2026-04-09-12-34-30] - UPDATE - references/software_architecture.md - 架构文档同步实际状态（修正 Product/Feature/Common 层差异，更新三层架构）
- [2026-04-09-12-34-35] - UPDATE - references/architecture_current.png - 重新生成架构图 PNG（4307x1143, 187KB）
- [2026-04-09-12-45-00] - UPDATE - README.md - 添加 references/ 目录详细导览（软件架构、用户故事、功能设计、示例代码、工具文档、安全规范）

---

## 2026-04-09 (测试体系建立)

- [2026-04-09-14-30-00] - CREATE - memory/04_test_checklist.md - 测试清单文件初始化
- [2026-04-09-14-50-00] - UPDATE - memory/04_test_checklist.md - 重构测试清单，增加 P0/P1/P2 优先级体系，聚焦 Feature 集成测试（29 个测试用例：P0=13, P1=10, P2=6）
- [2026-04-09-14-50-30] - UPDATE - CLAUDE.md - 添加测试监督机制章节（测试通过标记规则、AI 监督责任、通过率追踪）

---

## 2026-05-06 (Codex 适配与 social-share 状态同步)

- [2026-05-06-00-27-58] - CREATE - AGENTS.md - 新增 Codex 主入口，记录当前项目结构、social-share 上传流程、构建验证和 memory 维护规则
- [2026-05-06-00-27-58] - UPDATE - CLAUDE.md - 改为 Claude 兼容入口，指向 AGENTS.md，保留 ArkTS MCP 提醒
- [2026-05-06-00-27-58] - UPDATE - memory/01_project_state.md - 更新当前分支为 feature/social-share，记录 merge commit def52e1、social-share 模块 1 状态和 backend 契约
- [2026-05-06-00-27-58] - UPDATE - memory/03_task_backlog.md - 增加 Codex 适配与 social-share 模块 1 合并记录，更新后续任务
- [2026-05-06-00-27-58] - UPDATE - memory/04_test_checklist.md - 增加 social-share 图片打包发布流程 P0 测试项

---

## 2026-05-07 (Replay 增广 Phase 0)

- [2026-05-07-15-35-00] - CREATE - common/replay/ReplayPreferences.ets - 新增 Replay 偏好 key、默认值和版本刷新封装
- [2026-05-07-15-35-00] - CREATE - common/replay/ReplayStyleKit.ets - 新增 Replay 风格套件枚举与基础目录（Minimal White / Dark Night / Vintage Film）
- [2026-05-07-15-35-00] - CREATE - common/replay/ReplayMusicCatalog.ets - 新增 Replay BGM 目录，先接入当前内置单曲 `South-East-Traveling.mp3`
- [2026-05-07-15-35-00] - CREATE - common/replay/ReplayEffectOptions.ets - 新增滤镜、转场和特效默认配置骨架
- [2026-05-07-15-35-00] - CREATE - feature/map-travel/components/ReplaySettingsSheet.ets - 新增 Replay 设置面板骨架，支持 Style / Music 两个 Tab
- [2026-05-07-15-35-00] - UPDATE - common/index.ets - 导出 Replay 配置模型与目录
- [2026-05-07-15-35-00] - UPDATE - feature/map-travel/index.ets - 导出 ReplaySettingsSheet 组件
- [2026-05-07-15-35-00] - UPDATE - feature/map-travel/pages/TripReplayPage.ets - 接入 Replay 偏好初始化、右上角设置入口和设置面板显示；默认播放行为保持不变
- [2026-05-07-15-35-00] - BUILD - frontend/build.ps1 --mode module -p module=entry@default assembleHap 通过（存在既有 ArkTS warnings，无新增阻塞错误）

---

## 2026-05-07 (Replay 增广 Phase 1 - 本地 RDB 持久化 + 多 BGM)

- [2026-05-07-17-10-00] - UPDATE - common/service/types.ets - 新增 `ReplayTripPreferences`，并将路线级 Replay 配置字段并入 `Trip`
- [2026-05-07-17-10-00] - UPDATE - common/service/IDataService.ets - 扩展 `CreateTravelInput` / `UpdateTravelInput` 的 Replay 字段，新增 `getTripReplayPreferences` 与 `updateTripReplayPreferences`
- [2026-05-07-17-10-00] - UPDATE - common/data/RdbHelper.ets - 为 `travels` 表新增本地 Replay 配置列及迁移 SQL
- [2026-05-07-17-10-00] - UPDATE - common/data/TravelRepository.ets - 读写 `replay_style_kit_id / replay_bgm_id / replay_filter_id / replay_transition_type`
- [2026-05-07-17-10-00] - UPDATE - common/service/RdbDataService.ets - 新增本地路线级 Replay 配置查询与更新逻辑，跳过专门的云同步适配
- [2026-05-07-17-10-00] - UPDATE - common/service/MockDataService.ets, DataServiceStub.ets - 对齐新的 Replay 路线配置接口
- [2026-05-07-17-10-00] - UPDATE - common/replay/ReplayMusicCatalog.ets - 接入 5 首本地音乐素材并映射中文名称
- [2026-05-07-17-10-00] - UPDATE - feature/map-travel/pages/TripReplayPage.ets - 进入页面时从当前路线读取本地 Replay 配置；切换音乐时即时重载播放器；切换风格/音乐时写回当前路线
- [2026-05-07-17-10-00] - UPDATE - feature/map-travel/components/ReplaySettingsSheet.ets - 更新音乐页说明文案为“已接入即时切歌 + 本地数据库持久化”
- [2026-05-07-17-10-00] - BUILD - frontend/build.ps1 --mode module -p module=entry@default assembleHap 通过（存在既有 ArkTS warnings，无新增阻塞错误）
---

## 2026-05-07 (Replay 澧炲箍 Phase 2 - Style Kit 鍙傛暟鍖?+ 璺嚎棰勮鎽樿)

- [2026-05-07-21-25-00] - UPDATE - common/replay/ReplayStyleKit.ets - 灏?3 濂?Replay 椋庢牸浠庨€夐」鐩綍鎵╁睍涓哄彲鐩存帴渚涚粍浠朵娇鐢ㄧ殑瑙嗚 token
- [2026-05-07-21-25-00] - UPDATE - feature/map-travel/components/ReplayPhotoCard.ets, ReplayProgressBar.ets, PhotoCardOverlay.ets - 鍗＄墖銆佽繘搴︽潯鍜岃鎯呭眰鏀逛负璇诲彇 style kit锛屽幓鎺夌‖缂栫爜鐧藉簳钃濊壊
- [2026-05-07-21-25-00] - UPDATE - feature/map-travel/pages/TripReplayPage.ets - 鎺ュ叆褰撳墠 style kit 鐘舵€侊紝搴曢儴鎺у埗鏍忋€佸崱鐗囥€佸睆钂欑粺涓€璇诲彇 Replay 椋庢牸
- [2026-05-07-21-25-00] - UPDATE - feature/map-travel/components/ReplaySettingsSheet.ets - Style Tab 绔嬪嵆鐢熸晥锛屽苟鎵╁睍涓哄悗缁?Effects / Transition 鍏ュ彛
- [2026-05-07-21-25-00] - UPDATE - feature/map-travel/pages/TripDetailPage.ets - 鏂板鈥滃洖鏀鹃璁锯€濇憳瑕佸崱鐗囷紝杩涘叆 Replay 鍓嶅彲鏌ョ湅椋庢牸銆侀煶涔愩€佹护闀溿€佽浆鍦?
- [2026-05-07-21-25-00] - BUILD - frontend/build.ps1 --mode module -p module=entry@default assembleHap 閫氳繃锛堝瓨鍦ㄦ棦鏈?ArkTS warnings锛屾棤鏂板闃诲閿欒锛?
## 2026-05-07 (Replay 澧炲箍 Phase 3 - Effects 鍙鍖栧弽棣?)

- [2026-05-07-21-45-00] - UPDATE - feature/map-travel/pages/TripReplayPage.ets - 鏂板褰撳墠婊ら暅 / 娉㈢汗 / 鐜荤拑璇︽儏灞傜殑灞忓箷鍐呯姸鎬佹爣绛撅紝姣忔璁剧疆鏇存敼鍚庡彲鐩存帴鍙嶉
- [2026-05-07-21-45-00] - UPDATE - feature/map-travel/pages/TripDetailPage.ets - 鈥滃洖鏀鹃璁锯€濆崱鐗囨柊澧炵壒鏁堟憳瑕侊紝鍙湪杩涘叆 Replay 鍓嶇湅鍒版槸鍚﹀紑鍚妭鐐规尝绾规垨鐜荤拑璇︽儏灞?
- [2026-05-07-21-45-00] - BUILD - frontend/build.ps1 --mode module -p module=entry@default assembleHap 閫氳繃锛堝瓨鍦ㄦ棦鏈?ArkTS warnings锛屾棤鏂板闃诲閿欒锛?
## 2026-05-07 (Replay 澧炲箍 Phase 4 - 鎵嬪姩璺宠浆杞満瀵归綈)

- [2026-05-07-22-05-00] - UPDATE - feature/map-travel/pages/TripReplayPage.ets - 灏嗕笂涓€鑺傜偣 / 涓嬩竴鑺傜偣 / 杩涘害鏉¤烦杞殑鍗＄墖鍒囨崲绾冲叆鍚岀竴濂?fade/slide/scale 杞満锛岄伩鍏嶆墜鍔ㄥ垏鎹㈡椂鐨勭獊鍏?
- [2026-05-07-22-05-00] - UPDATE - feature/map-travel/pages/TripReplayPage.ets - 鍦ㄥ洖鏀鹃〉鍙充笂瑙掔姸鎬佹爣绛句腑澧炲姞褰撳墠杞満妯″紡锛屼究浜庢墜鍔ㄥ洖褰掑拰鐗规晥鑱斿姩楠岃瘉
- [2026-05-07-22-05-00] - BUILD - frontend/build.ps1 --mode module -p module=entry@default assembleHap 閫氳繃锛堝瓨鍦ㄦ棦鏈?ArkTS warnings锛屾棤鏂板闃诲閿欒锛?
## 2026-05-19 (ArkTS compile fix)

- [2026-05-19-00-00-00] - UPDATE - `frontend/entry/src/main/ets/feature/map-travel/views/TripListView.ets` - Replaced the misspelled `TransitionEffect.OPPHONENT` reference with `TransitionEffect.OPACITY`.
- [2026-05-19-00-00-00] - UPDATE - `frontend/entry/src/main/ets/feature/ai-copy/pages/AiCopyPage.ets` - Restored the `LengthMetrics` import from `@kit.ArkUI` and used `LengthMetrics.vp(8)` for Flex spacing.
- [2026-05-19-00-00-00] - BUILD - `frontend/build.ps1 --mode module -p module=entry@default assembleHap` succeeded after the fix; only pre-existing warnings remain.

---

## 2026-06-02 (Repository licensing clarification)

- [2026-06-02-00-00-00] - CREATE - `LICENSE` - Added a proprietary repository license for public-viewing / non-commercial evaluation without granting an open source license.
- [2026-06-02-00-00-00] - CREATE - `THIRD_PARTY_NOTICES.md` - Added a template for tracking third-party software, assets, attribution, and redistribution status.
- [2026-06-02-00-00-00] - UPDATE - `README.md` - Replaced the incorrect MIT statement with a proprietary license summary and links to `LICENSE` and `THIRD_PARTY_NOTICES.md`.
- [2026-06-02-00-00-00] - UPDATE - `memory/01_project_state.md` - Recorded the durable repository licensing change for future agents.
- [2026-06-02-00-00-00] - UPDATE - `THIRD_PARTY_NOTICES.md` - Replaced the placeholder template with an initial inventory covering OHPM packages, npm tooling, HarmonyOS sample references, replay music, and image assets requiring source verification.

---

## 2026-06-02 (Backend CI pytest security bump)

- [2026-06-02-00-00-00] - UPDATE - `backend/ci/ci-requirements.txt` - Bumped `pytest` from `8.3.3` to `9.0.3` to address Dependabot alert `GHSA-6w46-j5rx-g56g` / `CVE-2025-71176`.
- [2026-06-02-00-00-00] - UPDATE - `backend/share-service/requirements.txt` - Raised the test dependency bound from `pytest>=8.0,<9.0` to `pytest>=9.0.3,<10.0` so the Jenkins backend venv does not conflict with the CI tooling pin.
