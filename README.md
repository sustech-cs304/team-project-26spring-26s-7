[![Review Assignment Due Date](https://classroom.github.com/assets/deadline-readme-button-22041afd0340ce965d47ae6ef1cefeee28c7c493a6346c4f15d667ab976d596c.svg)](https://classroom.github.com/a/py413vYq)

# TravelPin - 鸿蒙地理位置旅行日记

**课程**: 南方科技大学 - 软件工程 (2026 春季)  
**团队**: Team Project 26 Spring - Group 7

---

## 项目简介

一款鸿蒙 (HarmonyOS) 地理位置旅行日记应用，支持：
- 📍 在地图上精确定位照片与回忆
- 🎬 创建并回放动画旅行路线
- 🔗 一键跨平台分享 (微信、微博)
- ✨ AI 驱动的社交媒体文案生成
- ☁️ 多设备同步与离线优先架构

---

## 分支架构

```
origin/main ────────────────────────────────────────────────► 生产分支
    │
    └── origin/incremental-dev-20260329 ◄─────────────────── 【当前开发主线】
            │                                                领先 main 46 commits
            ├── feature/photo ──────────────► 已合并 ✓
            ├── feature/trip-replay ────────► 已合并 ✓
            ├── feature1 ───────────────────► 已合并 ✓
            ├── feature/cloud ──────────────► 工作中 -
            └── feature/ai ─────────────────► 工作中 -
```

**分支策略**: `main` → `incremental-dev` (长期开发) → `feature/*` (功能分支)

---

## 📁 参考文档导览 (`references/`)

`references/` 目录包含项目开发过程中的所有参考文档、示例代码和设计规范。

```
references/
├── software_architecture.md    # 📐 软件架构文档
├── architecture_current.png    # 架构图 (PNG)
├── user_story_map.md           # 📋 用户故事地图
├── task/                       # 📝 功能设计文档
├── demos/                      # 💻 示例代码参考
├── tools/                      # 🔧 开发工具文档
└── security/                   # 🔒 安全规范文档
```

---

### 📐 软件架构 (`software_architecture.md`)

**用途**: 了解项目整体架构设计

**内容概要**:
- 三层架构设计：Product → Feature → Common
- Mermaid 架构图 (可渲染)
- 各层模块职责说明
- 已实现/待实现模块清单
- 路由配置表

**适用场景**:
- 新成员了解项目结构
- 代码审查时查阅模块边界
- 规划新功能时确定放置位置

---

### 📋 用户故事地图 (`user_story_map.md`)

**用途**: 理解产品需求分解

**内容概要**:
- 用户核心需求 (User Need)
- 两个史诗 (Epic): 核心地图功能 / 社交与 AI 功能
- 5 个用户故事 (User Stories)
- 任务分解与验收标准

**适用场景**:
- 理解产品愿景和用户价值
- 任务拆分和迭代规划
- 验收测试设计

---

### 📝 功能设计文档 (`task/`)

**用途**: 各功能模块的详细设计

| 文件 | 功能 | 说明 |
|------|------|------|
| `P02_动态旅程回放功能设计.md` | 旅程回放 | 完整设计方案 (用户故事、架构、UAT) |
| `rdb-data-requirements.md` | 数据库层 | RDB 数据服务需求与接口设计 |
| `F1_local_storage_assignment.md` | 本地存储 | 存储架构与数据流设计 |
| `database-in-replay.md` | 回放数据 | 回放功能中的数据库使用 |
| `replayData.md` | 回放数据模型 | ReplayNode/ReplayRoute 类型定义 |

**适用场景**:
- 开发某功能前阅读对应设计文档
- 理解数据模型和接口定义
- UAT 验收测试

---

### 💻 示例代码 (`demos/`)

**用途**: 鸿蒙开发技术参考

```
demos/
├── API/                    # 网络请求相关
│   ├── videotrimmer/       # ⭐ 文件上传下载完整示例
│   ├── networkstatusobserver/  # 网络状态监听
│   └── HttpRequest/        # 简单 HTTP 请求
├── photopickandsave/       # 照片选择与沙箱存储
├── photo/                  # 照片处理相关
├── addressrecognize/       # 地址识别
├── operaterdbintaskpool/   # RDB 数据库操作
└── sharebutton/            # 分享按钮组件
```

**重点推荐**:
- `demos/API/videotrimmer/` - 完整的文件上传下载流程
- `demos/photopickandsave/` - 照片选择与本地存储
- `demos/operaterdbintaskpool/` - 数据库异步操作

**适用场景**:
- 遇到技术问题时查找参考实现
- 学习鸿蒙 API 用法
- 复用代码模式

---

### 🔧 开发工具文档 (`tools/`)

**用途**: 开发环境配置与问题排查

| 文件 | 说明 |
|------|------|
| `arkts-repair-workflow.md` | ArkTS 编译错误自动化修复工作流 |
| `hvigor-deveco-sdk-home-fix.md` | Hvigor 构建工具 SDK 路径问题修复 |

**适用场景**:
- DevEco Studio 编译报错时查阅
- 配置开发环境
- CI/CD 构建问题排查

---

### 🔒 安全规范 (`security/`)

**用途**: 鸿蒙开发安全规范

| 文件 | 说明 |
|------|------|
| `HarmonyOS_Next_Security_Rules.pdf` | HarmonyOS Next 安全规则 (官方文档) |
| `HarmonyOS_Instruction.txt` | 安全开发指引 |

**适用场景**:
- 代码安全审查
- 权限申请设计
- 数据隐私保护

---

## 快速开始

### 环境要求

- DevEco Studio 4.0+
- HarmonyOS SDK (API 10+)
- Node.js 14+

### 构建运行

```bash
# 克隆仓库
git clone https://github.com/sustech-cs304/team-project-26spring-26s-7.git
cd team-project-26spring-26s-7

# 切换到开发分支
git checkout incremental-dev-20260329

# 在 DevEco Studio 中打开 frontend/ 目录
```

---

## 项目结构

```
frontend/entry/src/main/ets/
├── common/                 # 公共能力层
│   ├── utils/              # 工具类 (Logger, Constants, PhotoPickerUtil)
│   ├── service/            # 服务层 (IDataService, RdbDataService)
│   └── data/               # 数据层 (RdbHelper, Repositories)
├── feature/                # 基础特性层
│   ├── map-travel/         # 地图旅行 (Pages, Views, Components)
│   ├── profile/            # 个人中心
│   ├── social-share/       # 社交分享
│   └── ai-copy/            # AI 文案生成
└── pages/                  # 产品层页面 (Index, LoginPage, MainPage)
```

---

## 团队成员

| 角色 | 成员 |
|------|------|
| Frontend A | - |
| Frontend B | - |
| Backend C | - |
| Backend D | - |
| QA E | - |

---

## 许可证

MIT License