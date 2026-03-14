```mermaid
graph TD
    %% 全局样式定义
    classDef frontend fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef backend fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef spec fill:#f3e5f5,stroke:#4a148c,stroke-width:2px;
    classDef project fill:#f1f8e9,stroke:#33691e,stroke-width:4px,font-weight:bold;

    Project[软件工程项目: 核心架构开发]:::project

    %% 前端维度
    subgraph FE [前端开发组 - Front End]
        A[组员 A: UI/UX 负责人]:::frontend
        B[组员 B: 系统交互负责人]:::frontend
    end

    %% 后端维度
    subgraph BE [后端开发组 - Back End]
        C[组员 C: 基础设施负责人]:::backend
        D[组员 D: AI 业务逻辑负责人]:::backend
    end

    %% 规范与安全维度
    subgraph QA [合规与安全 - Standards & Security]
        E[组员 E: 规范与安全负责人]:::spec
    end

    %% 任务挂载
    Project --> FE
    Project --> BE
    Project --> QA

    %% A的任务
    A --> A1[UI 视觉设计与原型]
    A --> A2[前端页面初始框架搭建]
    
    %% B的任务
    B --> B1[HarmonyOS 本地文件系统 API 适配]
    B --> B2[前端地图组件集成与存储优化]

    %% C的任务
    C --> C1[服务器环境部署与维护]
    C --> C2[本地大模型部署与性能压测]

    %% D的任务
    D --> D1[远端大模型 API 嵌入工作流]
    D --> D2[基于 LLM 的应用功能逻辑实现]

    %% E的任务
    E --> E1[华为应用市场上架合规性研究]
    E --> E2[全链路软件安全设计与审计]

    %% 协作关系
    A -.->|UI 规范| B
    C -.->|接口支持| D
    E -.->|安全红线| Project