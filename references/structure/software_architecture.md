```mermaid
graph TD
    %% 样式定义
    classDef frontend fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef offline fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef cloud fill:#f1f8e9,stroke:#33691e,stroke-width:2px;
    classDef security fill:#ffebee,stroke:#c62828,stroke-width:2px;
    classDef storage fill:#eceff1,stroke:#455a64,stroke-dasharray: 5 5;

    %% --- Front End (ArkUI 声明式交互层) ---
    subgraph FrontEnd [Front End - HarmonyOS App]
        MapUI[地图主界面: 轨迹渲染与交互]:::frontend
        Playback[轨迹回放引擎: 插值动画控制器]:::frontend
        MediaPicker[系统照片选择器: 最小权限访问]:::frontend
        ShareModule[分享模块: HMAC 签名链接生成]:::frontend
    end

    %% --- Local Back End (离线优先逻辑层) ---
    subgraph LocalBackEnd [Local Back End - Offline First]
        direction TB
        Privacy[隐私拦截器: EXIF 数据强制脱敏]:::security
        
        subgraph DataStack [核心数据栈]
            LocalRDB[(本地 RDB: 关系型数据库)]:::storage
            FileSys[(本地文件系统: 媒体与缓存)]:::storage
            SyncManager[同步管理器: 队列与冲突解决]:::offline
        end

        subgraph LocalAI [本地处理能力]
            ML_Vector[轻量 ML: 地点分类与向量化]:::offline
            Local_LLM[本地 LLM: OCR 与内容摘要]:::offline
        end
    end

    %% --- Cloud & Connectivity (云端服务与跨端同步) ---
    subgraph Cloud [Cloud - Distributed Services]
        SyncServer[分布式同步服务器: 最终一致性]:::cloud
        CloudDB[(云端 PostGIS: 空间数据归档)]:::cloud
        OSS[对象存储: 缩略图与媒体分发]:::cloud
        WebPortal[Web 分享门户: 只读轻量渲染]:::cloud
        AIGateway[AI 网关: 社交文案生成与风控]:::cloud
    end

    %% --- 数据流关系 (Data Flow) ---

    %% 1. 数据采集与脱敏
    MediaPicker --> Privacy --> LocalRDB
    Privacy --"抹除地理标签后存储"--> FileSys

    %% 2. 离线工作与同步
    LocalRDB <--> SyncManager
    SyncManager --"增量更新/跨端漫游"--> SyncServer
    SyncServer <--> CloudDB

    %% 3. 轨迹渲染逻辑
    LocalRDB --"节点坐标"--> Playback
    Playback --"动画帧"--> MapUI

    %% 4. AI 处理链路
    FileSys --> Local_LLM
    Local_LLM --"视觉标签"--> AIGateway
    AIGateway --"安全文案"--> MapUI

    %% 5. 跨平台分享
    ShareModule --"签名凭证"--> WebPortal
    CloudDB --"空间数据"--> WebPortal