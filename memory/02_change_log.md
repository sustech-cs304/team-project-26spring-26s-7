# Change Log

**Last Updated**: 2026-04-12

---

## Format
```
[YYYY-MM-DD-HH-MM-SS] - [Action] - [Location] - [Description] - [Git Commit]
```

---

## 2026-04-12 (旅行相册瀑布流页面)

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
