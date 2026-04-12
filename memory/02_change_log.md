# Change Log

**Last Updated**: 2026-04-10

---

## Format
```
[YYYY-MM-DD-HH-MM-SS] - [Action] - [Location] - [Description] - [Git Commit]
```

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