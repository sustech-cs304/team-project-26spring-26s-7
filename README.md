[![Review Assignment Due Date](https://classroom.github.com/assets/deadline-readme-button-22041afd0340ce965d47ae6ef1cefeee28c7c493a6346c4f15d667ab976d596c.svg)](https://classroom.github.com/a/py413vYq)

# 项目概览

**课程**: 南方科技大学 - 软件工程 (2026 春季)
**团队**: 团队项目 26 春季 - 第 7 组
**仓库**: `sustech-cs304/team-project-26spring-26s-7`

**项目**: 鸿蒙地理位置旅行日记应用 (HarmonyOS location-based travel journal app)

## 核心功能

- 在地图上将照片/回忆精确标记到地理位置
- 创建和回放动画旅行路线
- 一键跨平台分享（微信、微博）
- AI 驱动的社交媒体文案生成
- 支持多设备同步的离线优先架构

## 技术栈

### 前端 (HarmonyOS App)
- **框架**: ArkTS + ArkUI (声明式 UI)
- **位置**: HarmonyOS `LocationHub` API
- **媒体**: 系统照片选择器 (最小权限模型)
- **本地存储**: RDB (关系型数据库) + 文件系统

### 后端与 AI
- **架构**: 离线优先，最终一致性同步
- **本地 AI**: LLM 用于 OCR/摘要，ML 用于文本向量化
- **云端**: PostGIS 用于空间数据，对象存储用于媒体文件
- **同步**: 分布式同步服务器，支持冲突解决

### 安全与隐私
- 强制在上传时剥离 EXIF 数据
- 使用带 TTL 的 HMAC-SHA256 签名分享链接
- AI 内容审核，确保持久化内容安全

## 仓库结构

```
team-project-26spring-26s-7/
├── README.md          # 初步需求分析（5 个功能 + 非功能需求）
├── proposal-7.md      # GitHub Classroom 作业文件
├── structure/
│   ├── wbs_dictionary.md      # WBS 分解：5 名团队成员（FE: A/B, BE: C/D, QA: E）
│   ├── software_architecture.md # 系统架构图（三层：FE/BE/Cloud）
│   └── *.png          # 生成的架构图
```

## WBS 团队分工

| 成员 | 角色 | 任务 |
|--------|------|-------|
| A | UI/UX 负责人 | 视觉设计、原型、前端脚手架 |
| B | 交互负责人 | HarmonyOS FileSystem API、地图集成 |
| C | 基础设施负责人 | 服务器部署、本地 LLM 部署 |
| D | AI/后端负责人 | 远程 LLM API、应用逻辑 |
| E | 合规负责人 | 应用商店合规性、安全审计 |

## 架构层次

1. **前端** (HarmonyOS App): 地图 UI、轨迹回放、媒体选择器、分享模块
2. **本地后端** (离线优先): 隐私过滤器 (EXIF 移除)、RDB、同步管理器、本地 ML/LLM
3. **云端** (分布式服务): 同步服务器、PostGIS、OSS、Web 门户、AI 网关

## 开发规范

- **Git 流程**: 主分支受保护，变更需通过 PR
- **文档**: 所有文档遵循结构化 Markdown，使用清晰的标题层级
- **语言**: 中英双语；中文与英文/数字之间保持一个空格（盘古之白）
- **提交风格**: 遵循 Conventional Commits (feat:, fix:, docs:, 等)

## 关键文件参考

- `README.md`: 5 个核心功能需求，非功能需求（性能、安全、可靠性）
- `structure/wbs_dictionary.md`: 团队任务分解与职责
- `structure/software_architecture.md`: 三层架构与数据流

---

## 项目结构图说明

`structure/` 目录下存放了本项目的相关图表文件：

- **wbs_diagram.png** - WBS 工作分解结构图，展示项目整体架构及 5 位成员（A/B/C/D/E）的任务分配与协作关系
- **software_architecture.png** - 软件细节架构流程图，展示三层架构（Front End / Local Back End / Cloud）的数据流与组件交互
- **software_structure.drawio.png** - 软件总体结构示意图（DrawIO 源文件对应的导出图片）

上述 PNG 图片均由 Mermaid 代码生成，开发者可直接修改对应的 `.md` 源文件（如 `wbs_dictionary.md`、`software_architecture.md`）中的 Mermaid 代码来更新流程图，然后使用以下命令重新生成：

```bash
mmdc -i structure/wbs_dictionary.md -o structure/wbs_diagram.png -w 2400
mmdc -i structure/software_architecture.md -o structure/software_architecture.png -w 3200
```
