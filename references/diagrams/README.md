# TravelPin C4 架构图索引

**生成日期**: 2026-04-16  
**项目**: TravelPin - 鸿蒙地理位置旅行日记应用

---

## 📐 架构图列表

C4 模型是一种分层架构描述方法，包含四个层级：**Context** → **Container** → **Component** → **Code**。本项目生成了前三个层级的架构图。

| 层级 | 名称 | 文件 | 说明 |
|------|------|------|------|
| **L1** | System Context (系统上下文图) | [C4_Level1_SystemContext.md](./C4_Level1_SystemContext.md) | 识别用户角色、外部依赖系统 |
| **L2** | Container (容器图) | [C4_Level2_Container.md](./C4_Level2_Container.md) | 展示 HAP/HSP/HAR 模块划分 |
| **L3** | Component (组件图) | [C4_Level3_Component.md](./C4_Level3_Component.md) | 深入 map-travel 模块内部 |

---

## 🎯 使用指南

### 场景 1: 新成员了解项目
→ 先阅读 **Level 1 系统上下文图**，了解系统在生态系统中的位置

### 场景 2: 模块边界讨论
→ 查看 **Level 2 容器图**，明确各 HSP/HAR 模块的职责

### 场景 3: 代码审查/重构
→ 参考 **Level 3 组件图**，理解 MVVM 模式和数据流

---

## 📊 架构图总览

### Level 1 - 系统上下文图

```
用户 → TravelPin App → [华为账号，华为云 OSS, 自建服务器 API]
                          ↓
                    [微信，微博] (分享平台)
```

**关键点**:
- 明确系统边界（应用内部 vs 外部依赖）
- 识别数据流向（原始照片→华为云，元数据→自建服务器）
- 安全机制（OAuth 2.0, HMAC 签名）

---

### Level 2 - 容器图

```
entry (HAP)
├── Product Layer: Index, LoginPage, MainPage
├── Feature Layer: map-travel, profile, social-share, ai-copy (HSP)
└── Common Layer: utils, service, data, auth (HAR)
```

**关键点**:
- 三层架构：Product → Feature → Common
- 模块类型：HAP (主包) / HSP (共享包) / HAR (静态库)
- 数据流：Views → IDataService → RdbDataService → Repositories

---

### Level 3 - 组件图 (map-travel 模块)

```
MapHomeView (View)
├── @State: mapNodes, searchResults, previewVisible
├── @StorageLink: travelDataVersion
└── 依赖：IDataService, MapController, PhotoPickerUtil
```

**关键点**:
- MVVM 模式：View (ArkUI) + ViewModel (@State/@Watch) + Model (MemoryNode)
- 响应式设计：数据变化自动触发 UI 刷新
- 核心方法：loadNodes(), syncMarkers(), handleSearchInputChange()

---

## 🔧 如何渲染 Mermaid 图表

### 方法 1: 在线渲染
将 `.md` 文件中的 Mermaid 代码块复制到 [Mermaid Live Editor](https://mermaid.live/)

### 方法 2: 本地 CLI 工具
```bash
# 安装
npm install -g @mermaid-js/mermaid-cli

# 转换为 SVG
mmdc -i C4_Level1_SystemContext.md -o C4_Level1_SystemContext.svg

# 转换为 PNG (更高分辨率)
mmdc -i C4_Level2_Container.md -o C4_Level2_Container.png -w 1600
```

### 方法 3: VS Code 插件
安装 `Markdown Preview Mermaid Support` 插件，直接在 VS Code 中预览

---

## 📝 设计决策记录

### 为什么使用手动构建而非工具扫描？

**原因**: `dependency-cruiser` 对 ArkTS 语法支持有限
- `.ets` 文件扩展名不被识别
- HarmonyOS 系统模块 (`@kit.ArkUI`) 无法解析
- 需要配置文件才能正确处理

**解决方案**: 基于代码结构和架构文档手动构建，能更准确地表达业务语义

### 配色规范

| 类型 | 颜色 | 十六进制 |
|------|------|---------|
| Product 层 (Entry) | 蓝色 | `#1168bd` |
| Feature 层 (HSP) | 橙色 | `#ff9800` |
| Common 层 (HAR) | 绿色 | `#4caf50` |
| Service 层 | 紫色 | `#9c27b0` |
| 数据存储 | 灰蓝色 | `#607d8b` |
| 外部系统 | 灰色 | `#888888` |

---

## 📚 相关文档

- [软件架构文档](../software_architecture.md) - 详细的三层架构设计
- [用户故事地图](../user_story_map.md) - 需求分解与任务映射
- [功能设计文档](../task/) - 各模块详细设计方案

---

**最后更新**: 2026-04-16
