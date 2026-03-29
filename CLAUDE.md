# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Course**: Southern University of Science and Technology - Software Engineering (2026 Spring)
**Team**: Team Project 26 Spring - Group 7
**Repository**: `sustech-cs304/team-project-26spring-26s-7`

**Project**: HarmonyOS location-based travel journal app (鸿蒙地理位置旅行日记应用)

Core features:
- Pin photos/memories to precise geographic locations on a map
- Create and replay animated travel routes
- One-click cross-platform sharing (WeChat, Weibo)
- AI-powered social media caption generation
- Multi-device sync with offline-first architecture



## Repository Structure

```
team-project-26spring-26s-7/
├── README.md          # Preliminary requirement analysis (5 functional + non-functional requirements)
├── proposal-7.md      # GitHub Classroom assignment file
├── structure/
│   ├── wbs_dictionary.md      # WBS breakdown: 5 team members (FE: A/B, BE: C/D, QA: E)
│   ├── software_architecture.md # System architecture diagram (3-tier: FE/BE/Cloud)
│   └── *.png          # Generated architecture diagrams
```

## Development Notes

- **Git Flow**: Main branch is protected; PRs for changes
- **Documentation**: All docs must follow structured Markdown with clear headers
- **Language**: Chinese/English bilingual; add space between CJK and Latin characters (盘古之白)
- **Commit Style**: Conventional Commits (feat:, fix:, docs:, etc.)

## TravelPin 项目上下文 (关键)

**每次新对话开始时，必须先读取以下文件了解项目进度：**

1. `./memory/01_project_state.md` - 当前架构状态（全量读取）
2. `./memory/02_change_log.md` - 变更历史（**仅读取最新 10 行**）


**当前分支**: frontend

---

## Change Log RAG 检索策略

**原则**: change_log 会随着项目增长变长，不应每次都全量读取。采用"最新状态 + 按需检索"的方式。

### 默认行为
```bash
# 仅获取最新变更（最新 10 行）
tail -10 memory/02_change_log.md
```

### 按需检索命令

当工作中遇到问题需要查找相关修改记录时，使用以下命令：

```bash
# 1. 按文件路径搜索 - 查找特定文件的修改历史
grep -n "feature/map-travel" memory/02_change_log.md
grep -n "common/api" memory/02_change_log.md

# 2. 按操作类型搜索 - 查找特定类型的变更
grep -n "CREATE" memory/02_change_log.md    # 查找所有创建操作
grep -n "UPDATE" memory/02_change_log.md    # 查找所有更新操作
grep -n "FIX" memory/02_change_log.md       # 查找所有修复操作

# 3. 按模块/功能搜索
grep -n "auth" memory/02_change_log.md      # 查找认证相关
grep -n "RDB\|database" memory/02_change_log.md  # 查找数据库相关
grep -n "AI\|copy" memory/02_change_log.md  # 查找 AI 相关

# 4. 按日期搜索
grep -n "2026-03-22" memory/02_change_log.md  # 查找特定日期

# 5. 组合搜索 - 查找特定文件的 CREATE 操作
grep -n "CREATE.*common/auth" memory/02_change_log.md

# 6. 查看变更上下文（匹配行前后各 3 行）
grep -B3 -A3 "MapTravelComponent" memory/02_change_log.md

# 7. 获取最近的模块创建记录
grep -n "### \[.*\] - CREATE" memory/02_change_log.md | tail -5
```

### 检索场景示例

| 场景 | 命令 |
|------|------|
| 调试 MapTravelComponent 问题 | `grep -B5 -A5 "MapTravelComponent" memory/02_change_log.md` |
| 查找 common 目录最近修改 | `grep -n "common/" memory/02_change_log.md \| tail -10` |
| 查找某功能是谁创建的 | `grep -B10 "feature/ai-copy" memory/02_change_log.md \| grep "CREATE"` |
| 查找所有占位文件创建记录 | `grep -n "stub\|placeholder" memory/02_change_log.md -i` |

---

## Git 版本控制

```bash
# 查看最近提交
git log --oneline -10

# 查看特定文件的提交历史
git log --oneline -- common/api/HttpClient.ets

# 查看某次提交的详细变更
git show <commit-hash>
```

---

## Memory 更新协作原则

**核心原则**: 用户目前不会主动更新 memory，所有 memory 维护工作由 AI 负责评估和执行。

### 自动更新规则

| 触发场景 | AI 行为 | 是否需要用户提醒 |
|---------|--------|-----------------|
| 创建/修改/删除文件 | 自动更新 `change_log.md` | ❌ 否 |
| 完成一个任务并汇报 | 自动更新 `task_backlog.md` (状态→🔄) | ❌ 否 |
| 用户确认任务完成 | 更新 `task_backlog.md` (状态→✅) | ✅ 是 |
| 架构决策变化 | 更新 `project_state.md` | ✅ 是 |
| 团队分工确定 | 更新 `task_backlog.md` 负责人 | ✅ 是 |

### 协作流程图

```
┌─────────────────────────────────────────────────────────────────┐
│  类型                        │  谁负责更新 Memory                │
├─────────────────────────────────────────────────────────────────┤
│  AI 创建/修改文件              │  AI 自动更新 change_log            │
│  AI 完成一个任务并汇报         │  AI 更新 backlog（状态→🔄）        │
│  用户确认任务完成               │  用户提醒 AI 更新 backlog（→✅）      │
│  架构决策变化                 │  用户提醒 AI 更新 project_state        │
│  团队分工确定                 │  用户提醒 AI 更新 backlog 负责人        │
└─────────────────────────────────────────────────────────────────┘
```

### AI 评估责任

由于用户不会主动提醒更新 memory，AI 需要：
1. **自行判断**何时完成了需要记录的任务
2. **主动更新** backlog 中对应任务的状态
3. **在 change_log 中记录**所有文件级别的变更
4. **在遇到架构疑问时**主动询问用户而非假设

---

## 架构决策记录

**双后端架构** (2026-03-22 确认):
- 图片/媒体 → 华为云存储 (不出华为生态)
- 元数据 → 自建服务器 (AI 文案生成)
- 原始照片永不上传到自建服务器

**职责边界**:
- 本仓库 (`base/`): 纯 HarmonyOS 前端
- 自建服务器：AI Gateway API、内容审核、分享验证
- Web 门户：独立仓库


## MCP 使用提醒
在遇到 arkts 语言报错或者不确定如何书写时，请积极调用 arkts-assistant MCP 来辅助开发。

---

## ArkTS 编译验证工作流

**使用场景**: 修改 ArkTS 代码后，在 DevEco Studio Previewer 中验证编译是否成功

### 编译命令 (成功验证)

**完整清理并编译** (推荐，确保缓存干净):
```bash
cd frontend
rm -rf .hvigor intermediates build .preview
"C:\Apps\DevEco Studio\tools\node\node.exe" "C:\Apps\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default -p product=default -p pageType=page -p compileResInc=true -p previewMode=true -p buildRoot=.preview PreviewBuild
```

**快速编译** (缓存未损坏时):
```bash
cd frontend
"C:\Apps\DevEco Studio\tools\node\node.exe" "C:\Apps\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default -p product=default -p pageType=page -p compileResInc=true -p previewMode=true -p buildRoot=.preview PreviewBuild
```

**清理命令** (遇到缓存问题时使用):
```bash
cd frontend
rm -rf .hvigor intermediates build .preview
```

### 三层架构导入路径规范

**当前架构** (2026-03-29 重构完成):
```
entry/src/main/ets/
├── common/                 # 公共层 (utils, service/types)
├── feature/
│   ├── map-travel/         # 地图旅行功能 (pages, views)
│   ├── profile/            # 个人中心 (views)
│   └── social-share/       # 社交分享 (pages)
└── pages/                  # Product 层页面 (Index, Login, Main)
```

**导入路径规则**:
| 位置 | 导入 common | 示例 |
|------|-----------|------|
| `pages/*.ets` | `import ... from '../common'` | MainPage.ets |
| `feature/*/views/*.ets` | `import ... from '../../../common'` | MapHomeView.ets |
| `feature/*/pages/*.ets` | `import ... from '../../../common'` | NodeEditPage.ets |

**路由配置**: `entry/src/main/resources/base/profile/main_pages.json`
- feature 层页面路径：`feature/map-travel/pages/NodeEditPage`

### 错误排查流程

```
1. 运行编译命令 → 收集报错
     ↓
2. 分析错误类型
   ├── ArkTS Compiler Error → 使用 arkts-assistant MCP 查询正确语法
   ├── Module not found → 检查导入路径 (使用 '../../../common')
   ├── Page does not exist → 检查 main_pages.json 路由配置
   └── Type mismatch → 使用 arkts-assistant 查询类型定义
     ↓
3. 清理缓存 → 重新编译
     ↓
4. 编译成功 → 在 DevEco Studio 中打开 Previewer 验证
```

### 常用错误处理

| 错误类型 | 处理方法 |
|---------|---------|
| `Cannot find module` | 使用 `'../../../common'` 相对路径导入 |
| `Cannot find name` | 检查导入语句是否包含该符号 |
| `Page does not exist` | 更新 `main_pages.json` 为 feature 层路径 |
| `Type mismatch` | 使用 `mcp__arkts-assistant__find_docs` 查询正确类型 |
| `Cannot find name 'RouterUrls'` | 确保从 `../../../common` 导入了 `RouterUrls` |

### arkts-assistant MCP 使用示例

```bash
# 查询特定 API 用法
mcp__arkts-assistant__find_docs({ query: "router.pushUrl 用法" })

# 查询组件语法
mcp__arkts-assistant__find_docs({ query: "MapComponent 组件" })

# 查询装饰器
mcp__arkts-assistant__find_docs({ query: "@State @Link 装饰器" })
```

---

## 终极任务 (Ultimate Goal)

**目标**: 实现 `D:\Mydata\1University\3Junior\Software_Engineering\project\base` 项目中的完整架构和功能

**参考架构**: `base/` 项目目录结构

```
base/entry/src/main/ets/
├── common/                 # 公共能力层
│   ├── utils/              # 工具类
│   ├── api/                # API 客户端
│   ├── data/               # 数据模型
│   ├── auth/               # 认证模块
│   └── security/           # 安全模块
├── feature/                # 基础特性层
│   ├── map-travel/         # 地图旅行 (MapTravelComponent)
│   ├── route-editor/       # 路线编辑
│   ├── ai-copy/            # AI 文案生成
│   └── social-share/       # 社交分享
└── product/                # 产品定制层
    └── pages/              # 6 个核心 Pages
```

**当前进度** (2026-03-29):
- ✅ Phase 1: common 层创建 (utils/Constants, service/types)
- ✅ Phase 2: feature 层目录创建 (map-travel, profile, social-share)
- ✅ Phase 3: 导入路径更新
- ✅ Phase 4: 编译验证通过

**下一步**:
1. 对比 `base/` 和 `frontend/` 项目结构，识别缺失模块
2. 逐步迁移 `base/` 中的功能模块到 `frontend/`
3. 每完成一个模块，确保编译通过

**开发策略**: 小步快跑，增量迭代，每一步都可验证