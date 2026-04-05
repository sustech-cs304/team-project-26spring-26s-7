# Project State

**Last Updated**: 2026-04-05 (照片选择与沙箱存储功能完成)
**Project**: TravelPin - HarmonyOS Travel Journal App
**Repository**: D:\Mydata\1University\3Junior\Software_Engineering\frontendv1\team-project-26spring-26s-7
**Current Branch**: feature/photo
**Base Branch**: incremental-dev-20260329

---

## 1. 开发策略 (2026-03-29 更新)

**目标架构**: `D:\Mydata\1University\3Junior\Software_Engineering\project\base`

**增量开发方法**:
1. 以当前能正常编译运行的 `frontend/` demo 为基础
2. 逐步将 `base/` 项目中的架构和功能模块迁移整合进来
3. 每一步确保可编译运行，避免一次性大改导致复杂问题
4. 小步快跑，每一步都可验证

**分支策略**:
- `frontend` - 当前稳定分支（保持不变）
- `incremental-dev-20260329` - 增量开发分支（当前工作，已合并 feature/trip-replay）
- `feature/trip-replay` - 旅程回放功能分支（已合并，可删除）

---

## 2. 当前架构状态 (2026-04-04 更新)

**三层架构**: 已完成 (2026-03-29)

```
entry/src/main/ets/
├── common/                 # 公共层
│   ├── index.ets           # 统一导出入口
│   ├── utils/Constants.ets # 工具类 (AppColors, AppDimens, RouterUrls)
│   ├── utils/PhotoPickerUtil.ets  # 照片选择工具
│   ├── utils/Logger.ets    # 日志工具
│   ├── data/               # 数据层 (RdbHelper, TravelRepository, MemoryNodeRepository)
│   ├── service/            # 服务层 (IDataService, MockDataService, RdbDataService)
│   └── service/types.ets   # 数据模型 (MemoryNode, Trip, ReplayNode, ReplayRoute)
├── feature/
│   ├── map-travel/         # 地图旅行功能
│   │   ├── pages/          # 页面 (NodeEdit, NodeDetail, TripDetail, TripReplay, LocationPicker)
│   │   ├── views/          # 视图组件 (MapHomeView, TripListView)
│   │   ├── components/     # 组件 (PhotoSelector, ReplayPhotoCard, ReplayProgressBar, PhotoCardOverlay)
│   │   └── index.ets
│   ├── profile/            # 个人中心功能
│   │   ├── views/ProfileView.ets
│   │   ├── pages/ProfileEditPage.ets
│   │   └── index.ets
│   ├── social-share/       # 社交分享功能
│   │   ├── pages/SharePage.ets
│   │   ├── components/QRCodeShare.ets
│   │   └── index.ets
│   └── ai-copy/            # AI 文案生成功能
│       ├── pages/AiCopyPage.ets
│       ├── components/AiCopyGenerator.ets
│       └── index.ets
└── pages/                  # Product 层页面
    ├── Index.ets           # 启动页
    ├── LoginPage.ets       # 登录页
    └── MainPage.ets        # 主页 (导入 feature 层组件)
```

**路由配置**: `entry/src/main/resources/base/profile/main_pages.json`
- 已配置 11 个页面路由（新增 LocationPickerPage）

**编译状态**: ✅ BUILD SUCCESSFUL (2026-04-05 验证)

---

## 3. 功能模块状态 (2026-04-04 更新)

| 功能模块 | 页面/组件 | 状态 | 说明 |
|---------|----------|------|------|
| **数据库层** | RdbHelper, TravelRepository, MemoryNodeRepository | ✅ 完整 | SQLite CRUD 实现 |
| **服务层** | IDataService, RdbDataService, MockDataService | ✅ 完整 | 数据服务接口与实现 |
| **地图旅行** | MapHomeView, NodeEditPage, NodeDetailPage | ✅ 完整 | 地图展示、节点编辑/详情 |
| **地图选点** | LocationPickerPage | ✅ 完整 | 地图点击选点、AppStorage 传值 |
| **旅行路线** | TripListView, TripDetailPage | ✅ 完整 | 列表、详情 |
| **动态旅程回放** | TripReplayPage, ReplayPhotoCard, ReplayProgressBar, PhotoCardOverlay | ✅ 完整 | 已适配数据库，动画回放完整 |
| **AI 文案** | AiCopyPage, AiCopyGenerator | ✅ 完整 | 5 种风格、3 种长度 |
| **社交分享** | SharePage, QRCodeShare | ✅ 完整 | 分享链接、平台选择、二维码占位 |
| **个人中心** | ProfileView, ProfileEditPage | ✅ 完整 | 用户信息、设置、编辑资料 |
| **照片选择** | PhotoSelector, PhotoPickerUtil | ✅ 完整 | 系统相册选择、沙箱存储、网格展示、删除、自动清理 |
| **认证** | LoginPage | ⚠️ 占位 | 华为账号 SDK 待集成 |

**已删除**:
- `ShareSelectPage.ets` - 无触发入口，已移除

---

## 4. 近期合并记录 (2026-04-04)

### 合并 feature/trip-replay → incremental-dev-20260329

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

- 3b0251d: fix: 恢复合并丢失的地图选点功能
- 8b5a775: fix: 使用相对路径配置签名证书
- d4602bb: Merge branch 'feature/trip-replay' into incremental-dev-20260329
- 8f4e361: docs: 添加回放数据设计文档
- 90c9eb9: Merge pull request #103 from 1notsleepy/RDB
