🤖 Claude Code 指令：全自动 C4 架构生成工作流
0. 任务目标
利用项目源码和 dependency-cruiser 工具，为当前鸿蒙项目生成三个层级的架构图（Mermaid 格式），并确保每一层图表都能清晰地放入一张图片中。

1. 预执行检查 (Pre-check)
请首先检查环境，如果缺少工具请自行安装：

检查 node_modules 中是否有 dependency-cruiser。

确认 oh-package.json5 或 package.json 的项目根目录。

2. 执行任务：Level 2 - 容器图 (Container / Module Layer)
指令：

"这是最关键的一步。请执行以下命令来分析项目的物理模块结构：
npx depcruise . --exclude "(node_modules|build|ohos|ohos_test|dist)" --output-type mermaid --depth 2

根据扫描结果，请提炼出一个 C4 Level 2 Mermaid Container Diagram：

将 entry (HAP) 标记为主要容器。

识别并聚合 features 下的各个模块 (HSP/HAR)。

识别并聚合 common 或 core 下的基础库。

标注各模块间的主要数据流向。

优化建议：如果模块超过 8 个，请尝试将功能相近的模块放入同一个 System_Boundary 中以保证清晰度。"

这一步作为暂停流程，返回结果给用户，收集用户反馈。

3. 执行任务：Level 1 - 系统上下文图 (System Context)
指令：

"分析项目 README 和核心代码（如 AppStorage 初始化或 Network 模块），识别：

主要用户角色（如：科研人员、旅行者）。

当前系统核心功能。

外部依赖系统（如：华为帐号、阿里云 OSS、后端 API、地图服务）。
请输出一个 C4 Level 1 Mermaid Context Diagram，使用 C4Context 语法。"

4. 执行任务：Level 3 - 组件图 (Component Layer)
指令：

"请针对项目中的核心业务模块（例如负责 AI 处理或地图逻辑的模块），执行深度扫描：
npx depcruise <核心模块路径> --include-only "^src" --output-type mermaid --depth 3

基于此扫描结果，生成 C4 Level 3 Mermaid Component Diagram：

展示该模块内部的 Page/View、ViewModel、Repository 和 Service 的关系。

解释其遵循的设计模式（如 MVVM）。

隐藏非业务相关的琐碎文件（如常量定义、辅助工具类），仅保留核心逻辑组件。"

5. 输出要求与格式
对于每一张生成的 Mermaid 代码，请满足以下要求：

配色规范：外部系统用灰色，核心应用用蓝色，数据存储用绿色。

布局优化：使用 direction TB 或 direction LR 寻找最适合屏幕显示的比例。

自然语言解读：在每张图下方提供：

设计动机：为什么要这样分层？

隐藏假设：图中没画出来但实际存在的约束（如：所有网络请求必须经过拦截器）。

工具链建议：如果我想把这些代码转为 SVG，请提供具体的 mmdc 命令。