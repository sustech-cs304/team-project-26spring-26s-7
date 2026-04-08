[![Review Assignment Due Date](https://classroom.github.com/assets/deadline-readme-button-22041afd0340ce965d47ae6ef1cefeee28c7c493a6346c4f15d667ab976d596c.svg)](https://classroom.github.com/a/py413vYq)

## 分支架构

```
origin/main ────────────────────────────────────────────────► 生产分支
    │
    └── origin/incremental-dev-20260329 ◄─────────────────── 【当前开发主线】
            │                                                领先 main 46 commits
            ├── feature/photo ──────────────► 已合并 ✓
            ├── feature/trip-replay ────────► 已合并 ✓
            └── feature1 ───────────────────► 已合并 ✓
```

**分支策略**: `main` → `incremental-dev` (长期开发) → `feature/*` (功能分支)

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
