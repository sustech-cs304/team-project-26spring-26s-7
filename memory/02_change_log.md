# Change Log

**Last Updated**: 2026-04-23

---

## Format
```
[YYYY-MM-DD-HH-MM-SS] - [Action] - [Location] - [Description] - [Git Commit]
```

---

## 2026-04-08 (feature/ai AI 功能接口开发)

### 新增 AI 功能模块

**分支**: feature/ai (基于 incremental-dev-20260329)

- [2026-04-08-20-44-00] - CREATE - common/api/ - API 层目录创建
- [2026-04-08-20-44-10] - CREATE - common/api/ApiEndpoints.ets - API 端点常量定义
- [2026-04-08-20-44-20] - CREATE - common/api/HttpClient.ets - HTTP 客户端封装 (GET/POST)
- [2026-04-08-20-44-30] - CREATE - common/api/AiGatewayClient.ets - AI Gateway 客户端 (TODO: 后端接口实现)
- [2026-04-08-20-44-40] - CREATE - common/api/index.ets - API 层统一导出

### 新增 AI 能力层

- [2026-04-08-20-45-00] - CREATE - common/ai/ - AI 能力层目录创建
- [2026-04-08-20-45-10] - CREATE - common/ai/PhotoMetadata.ets - 照片元数据类型定义 (PhotoMetadata, JourneyMetadata, AiCopyRequest, AiCopyResponse)
- [2026-04-08-20-45-20] - CREATE - common/ai/LocalImageTagger.ets - 本地图片标签提取器 (TODO: 视觉 Kit 队友实现)
- [2026-04-08-20-45-30] - CREATE - common/ai/MetadataAggregator.ets - 元数据聚合器 (支持 MemoryNode/Trip 聚合)
- [2026-04-08-20-45-40] - CREATE - common/ai/index.ets - AI 层统一导出

### 扩展数据库层

- [2026-04-08-20-46-00] - UPDATE - RdbHelper.ets - 数据库版本升级 v1→v2
- [2026-04-08-20-46-10] - CREATE - photo_metadata 表 - 照片元数据存储 (photo_path 主键, 各类标签字段)
- [2026-04-08-20-46-20] - CREATE - common/data/PhotoMetadataRepository.ets - 照片元数据仓库 (CRUD 操作)
- [2026-04-08-20-46-30] - UPDATE - common/data/index.ets - 添加 PhotoMetadataRepository 导出

### 更新导出索引

- [2026-04-08-20-47-00] - UPDATE - common/index.ets - 添加 API Layer 和 AI Layer 导出
- [2026-04-08-20-47-10] - UPDATE - common/index.ets - 添加 PhotoMetadataRepository 导出

### 修改 AI 页面调用流程

- [2026-04-08-20-48-00] - UPDATE - AiCopyPage.ets - 导入 MetadataAggregator 和 AiGatewayClient
- [2026-04-08-20-48-10] - UPDATE - AiCopyPage.ets - 添加 nodeId/tripId 路由参数
- [2026-04-08-20-48-20] - UPDATE - AiCopyPage.ets - handleGenerate() 改为异步调用真实 API 流程
- [2026-04-08-20-48-30] - UPDATE - AiCopyPage.ets - 添加备选文案展示 UI
- [2026-04-08-20-48-40] - UPDATE - AiCopyPage.ets - 添加 aboutToAppear() 解析路由参数
- [2026-04-08-20-49-00] - BUILD - 编译验证通过 (仅警告，无错误)

### TODO 占位说明

**视觉套件队友需要实现**:
- `LocalImageTagger.extractMetadata()` - 调用鸿蒙视觉 Kit 提取图片标签

**后端开发同事需要实现**:
- `/api/v1/ai/generate` - AI 文案生成接口
- `/api/v1/ai/moderate` - 内容审核接口
- 认证方式配置 (Bearer Token / Session)

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

### 合并内容

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

- [2026-04-03-03-13-38] - BUILD - 编译验证通过 - BUILD SUCCESSFUL in 18s 929ms
- [2026-04-03] - FIX - types.ets - 为 ReplayNode 类添加 @Observed 装饰器，支持状态管理框架观察
- [2026-04-03] - FIX - ReplayPhotoCard.ets - 将 node 从 @State 改为 @Prop，支持接收父组件传入的新对象引用
- [2026-04-03] - FIX - TripReplayPage.ets - 添加 forceRefreshCard() 方法，通过先隐藏再显示强制刷新卡片状态
- [2026-04-03] - FIX - TripReplayPage.ets - moveToNode() 动画完成后自动显示卡片（setTimeout 延迟）
- [2026-04-03] - FIX - TripReplayPage.ets - jumpToNode() 人为拖动进度条时立即显示卡片
- [2026-04-03] - FIX - types.ets - 修复 photoUri 类型为 ResourceStr（内建类型，无需导入）
- [2026-04-03] - 问题修复 - 地点变换时图文不切换：三个节点都显示第一个节点的图文数据
- [2026-04-03] - 问题修复 - 拖动进度条时图文不显示：jumpToNode 后 isCardVisible 未设置为 true

### 根因分析

**问题 1：地点变换时图文不切换**
- 根因：ReplayPhotoCard 使用 @State node 装饰节点数据，无法响应对象引用切换
- 解决：@State → @Prop，并为 ReplayNode 添加 @Observed 装饰器

**问题 2：拖动进度条时图文不显示**
- 根因：jumpToNode 调用 moveToNode 后，isCardVisible=false，但未在拖动后恢复
- 解决：jumpToNode 末尾显式设置 isCardVisible=true

---

## 2026-04-02 (动态旅程回放功能开发)

- [2026-04-02-09-09-18] - BUILD - 编译验证通过 - BUILD SUCCESSFUL in 16s 967ms
- [2026-04-02-09-19-46] - BUILD - 编译验证通过 - BUILD SUCCESSFUL in 15s 950ms
- [2026-04-02-09-27-51] - BUILD - 编译验证通过 - BUILD SUCCESSFUL in 14s 193ms
- [2026-04-02-09-40-03] - BUILD - 编译验证通过 - BUILD SUCCESSFUL in 13s 936ms
- [2026-04-02-09-43-20] - BUILD - 编译验证通过 - BUILD SUCCESSFUL in 13s 936ms
- [2026-04-02-09-44-52] - BUILD - 编译验证通过 - BUILD SUCCESSFUL in 14s 973ms
- [2026-04-02-09-56-32] - BUILD - 编译验证通过 - BUILD SUCCESSFUL in 14s 973ms
- [2026-04-02] - GIT - branch - 创建 feature/trip-replay 分支（基于 incremental-dev-20260329）
- [2026-04-02] - CREATE - references/task/P02_动态旅程回放功能设计.md - 完整设计文档（用户故事、架构、数据模型、UAT）
- [2026-04-02] - CREATE - references/photo/ - 复制 6 张照片素材（pexels-*.jpg）
- [2026-04-02] - RENAME - resources/base/media/ - 照片重命名为 photo_1.jpg ~ photo_6.jpg
- [2026-04-02] - UPDATE - common/service/types.ets - 添加 ReplayNode、ReplayRoute、Position 类（非 interface）
- [2026-04-02] - UPDATE - common/service/types.ets - 添加 RouteGenerator 接口
- [2026-04-02] - UPDATE - common/index.ets - 导出 ReplayNode、ReplayRoute、Position 类
- [2026-04-02] - CREATE - feature/map-travel/components/ReplayPhotoCard.ets - 照片卡片组件（现代简约风格）
- [2026-04-02] - CREATE - feature/map-travel/components/ReplayProgressBar.ets - 离散步进进度条
- [2026-04-02] - CREATE - feature/map-travel/components/PhotoCardOverlay.ets - 底部半屏照片展开覆盖层
- [2026-04-02] - REWRITE - feature/map-travel/pages/TripReplayPage.ets - 完整重写动画播放逻辑
- [2026-04-02] - FIX - TripReplayPage.ets - 照片路径从 $rawfile 改为 $r('app.media.xxx')
- [2026-04-02] - FIX - ReplayProgressBar.ets - @State 改为 @Prop，支持外部传入进度值
- [2026-04-02] - FIX - TripReplayPage.ets - 退出按钮从 '✕' 改为 '←'，加深背景遮罩
- [2026-04-02] - FIX - TripReplayPage.ets - 修复退出按钮容器遮挡点击事件（100% 尺寸改为 40x40）
- [2026-04-02] - GIT - 79df842 - feat: 修复动态旅程回放功能编译错误
- [2026-04-02] - GIT - b425452 - fix: 修复 TripReplayPage 照片资源路径
- [2026-04-02] - GIT - a026056 - fix: 修复照片显示和退出按钮层级问题
- [2026-04-02] - GIT - 566ba14 - fix: 修复退出按钮显示问题（回退）
- [2026-04-02] - GIT - 61c7710 - fix: 修复照片资源引用和退出按钮显示
- [2026-04-02] - GIT - 11689b8 - fix: 修复退出按钮容器遮挡点击事件
- [2026-04-02] - GIT - 87040b8 - feat: 优化退出按钮样式和进度条联动

---

## 2026-03-30

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
- [2026-04-18-23-12-23] - ANALYZE - backend/backend_ai.py - 分析后端 LLM 调用代码，准备实现前端 ArkTS 客户端
- [2026-04-18-23-58-50] - CREATE - common/api/MultipartFormData.ets - Multipart/form-data 构建器（支持文本字段和文件字段）
- [2026-04-18-23-59-58] - CREATE - common/api/VisionLLMClient.ets - 视觉 LLM 客户端（调用 Qwen-VL 图像分析 API）
- [2026-04-19-00-02-04] - UPDATE - common/api/index.ets - 添加 MultipartFormData 和 VisionLLMClient 导出
- [2026-04-19-00-02-04] - UPDATE - common/index.ets - 添加 Vision LLM 相关导出到公共层
- [2026-04-19-03-10-41] - CREATE - feature/ai-copy/components/VisionLLMTest.ets - 视觉 LLM 测试组件（用于测试图像分析功能）
- [2026-04-19-03-11-25] - UPDATE - feature/ai-copy/index.ets - 添加 VisionLLMTest 组件导出
- [2026-04-19-15-41-42] - UPDATE - feature/ai-copy/components/VisionLLMTest.ets - 完善图片选择功能，使用 PhotoPickerUtil 和 getUIContext()
- [2026-04-23-13-51-00] - FIX - common/api/MultipartFormData.ets - 修复 ArkTS 编译错误：BusinessError 改为 Error、TextEncoder 改为 util.TextEncoder
- [2026-04-23-13-51-10] - FIX - common/api/VisionLLMClient.ets - 修复对象字面量类型声明错误，提取为 QwenApiResponse 等接口
- [2026-04-23-13-51-20] - UPDATE - common/utils/Constants.ets - 添加 AppDimens.FONT_XS (10) 尺寸常量
- [2026-04-23-13-51-30] - FIX - feature/ai-copy/pages/VisionLLMPage.ets - 移除错误的 @kit.ArkUI common 导入和未使用的 context 状态
- [2026-04-23-13-51-40] - UPDATE - feature/ai-copy/pages/AiCopyPage.ets - 重写：集成图片选择 + generateCopyFromImage()，替代纯元数据 mock 方案
- [2026-04-23-13-51-45] - UPDATE - common/index.ets - 添加 ImageCopyRequest 导出
- [2026-04-23-13-51-50] - BUILD - 编译验证通过 - BUILD SUCCESSFUL in 12s 388ms