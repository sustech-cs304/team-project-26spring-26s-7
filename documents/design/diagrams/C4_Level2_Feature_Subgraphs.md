# C4 Level 2 - Feature 子图系列

**生成日期**: 2026-04-20
**用途**: 将架构图分解为5个Feature子图，便于文档引用

---

## 1. map-travel (地图旅行)

```mermaid
flowchart TB
    %% 样式定义
    classDef feature fill:#ff9800,stroke:#e65100,stroke-width:2px,color:#fff
    classDef common fill:#4caf50,stroke:#2e7d32,stroke-width:2px,color:#fff
    classDef repo fill:#9c27b0,stroke:#6a1b9a,stroke-width:2px,color:#fff
    classDef component fill:#f5f5f5,stroke:#333,stroke-width:1px,color:#000

    %% map-travel 模块
    subgraph MapTravelModule["map-travel (地图旅行)"]
        direction TB
        MapManager["MapManager<br/>地图渲染+Marker管理"]:::component
        NodeManager["NodeManager<br/>节点CRUD逻辑"]:::component
        PhotoUploader["PhotoUploader<br/>照片上传"]:::component
    end

    %% 依赖的公共能力
    subgraph CommonLayer["依赖的公共能力"]
        direction TB

        subgraph RepositoryModule["repository (数据仓库)"]
            IDataService["IDataService<br/>数据服务接口"]:::repo
            RdbDataService["RdbDataService<br/>RDB本地实现"]:::repo
            MemoryNodeRepo["MemoryNodeRepo<br/>节点仓库"]:::repo
        end

        subgraph LocationModule["location (地图定位)"]
            MapService["MapService<br/>地点搜索"]:::common
            LocationService["LocationService<br/>定位服务"]:::common
        end

        subgraph AuthModule["auth (云存储)"]
            CloudStorageService["CloudStorageService<br/>华为云OSS上传"]:::common
        end

        subgraph UtilsModule["utils (工具类)"]
            PhotoPickerUtil["PhotoPickerUtil<br/>照片选择+沙箱"]:::common
        end
    end

    %% 依赖关系
    MapManager -.->|"地图定位"| LocationModule
    NodeManager -.->|"数据CRUD"| RepositoryModule
    PhotoUploader -.->|"照片上传"| CloudStorageService
    PhotoUploader -.->|"照片选择"| PhotoPickerUtil

    %% 内部关系
    IDataService -->|"implements"| RdbDataService
    RdbDataService -->|"uses"| MemoryNodeRepo

    %% 布局
    linkStyle default stroke:#666,stroke-width:1.5px
```

---

## 2. replay (轨迹回放)

```mermaid
flowchart TB
    %% 样式定义
    classDef feature fill:#ff9800,stroke:#e65100,stroke-width:2px,color:#fff
    classDef common fill:#4caf50,stroke:#2e7d32,stroke-width:2px,color:#fff
    classDef repo fill:#9c27b0,stroke:#6a1b9a,stroke-width:2px,color:#fff
    classDef component fill:#f5f5f5,stroke:#333,stroke-width:1px,color:#000

    %% replay 模块
    subgraph ReplayModule["replay (轨迹回放)"]
        direction TB
        TimelineController["TimelineController<br/>时间线播放控制"]:::component
        PhotoCardRenderer["PhotoCardRenderer<br/>照片卡片渲染"]:::component
        AudioPlayer["AudioPlayer<br/>背景音乐"]:::component
        CameraAnimator["CameraAnimator<br/>相机视角变换"]:::component
    end

    %% 依赖的公共能力
    subgraph CommonLayer["依赖的公共能力"]
        direction TB

        subgraph RepositoryModule["repository (数据仓库)"]
            IDataService["IDataService<br/>数据服务接口"]:::repo
            TravelRepo["TravelRepo<br/>旅行仓库"]:::repo
        end

        subgraph MediaModule["media (媒体服务)"]
            AudioService["AudioService<br/>音频播放"]:::common
        end

        subgraph LocationModule["location (地图定位)"]
            MapService["MapService<br/>地图服务"]:::common
        end
    end

    %% 依赖关系
    TimelineController -.->|"数据读取"| RepositoryModule
    AudioPlayer -.->|"音乐播放"| MediaModule
    CameraAnimator -.->|"相机动画"| LocationModule

    %% 内部关系
    IDataService -->|"uses"| TravelRepo

    %% 布局
    linkStyle default stroke:#666,stroke-width:1.5px
```

---

## 3. ai-copy (AI文案生成)

```mermaid
flowchart TB
    %% 样式定义
    classDef feature fill:#ff9800,stroke:#e65100,stroke-width:2px,color:#fff
    classDef common fill:#4caf50,stroke:#2e7d32,stroke-width:2px,color:#fff
    classDef repo fill:#9c27b0,stroke:#6a1b9a,stroke-width:2px,color:#fff
    classDef component fill:#f5f5f5,stroke:#333,stroke-width:1px,color:#000

    %% ai-copy 模块
    subgraph AiCopyModule["ai-copy (AI文案生成)"]
        direction TB
        LocalImageTagger["LocalImageTagger<br/>本地图像标签提取"]:::component
        MetadataAggregator["MetadataAggregator<br/>旅程元数据聚合"]:::component
        AiCopyGenerator["AiCopyGenerator<br/>文案生成+API调用"]:::component
    end

    %% 依赖的公共能力
    subgraph CommonLayer["依赖的公共能力"]
        direction TB

        subgraph MlModule["ml (机器学习)"]
            ImageTagger["ImageTagger<br/>图像标签提取"]:::common
        end

        subgraph RepositoryModule["repository (数据仓库)"]
            IDataService["IDataService<br/>数据服务接口"]:::repo
            TravelRepo["TravelRepo<br/>旅行仓库"]:::repo
        end

        subgraph ApiModule["api (网络服务)"]
            AiGatewayClient["AiGatewayClient<br/>AI网关客户端"]:::common
        end
    end

    %% 依赖关系
    LocalImageTagger -.->|"图像分析"| MlModule
    MetadataAggregator -.->|"元数据聚合"| RepositoryModule
    AiCopyGenerator -.->|"API调用"| ApiModule

    %% 内部关系
    IDataService -->|"uses"| TravelRepo

    %% 布局
    linkStyle default stroke:#666,stroke-width:1.5px
```

---

## 4. social-share (社交分享)

```mermaid
flowchart TB
    %% 样式定义
    classDef feature fill:#ff9800,stroke:#e65100,stroke-width:2px,color:#fff
    classDef common fill:#4caf50,stroke:#2e7d32,stroke-width:2px,color:#fff
    classDef repo fill:#9c27b0,stroke:#6a1b9a,stroke-width:2px,color:#fff
    classDef component fill:#f5f5f5,stroke:#333,stroke-width:1px,color:#000

    %% social-share 模块
    subgraph SocialShareModule["social-share (社交分享)"]
        direction TB
        ShareLinkGenerator["ShareLinkGenerator<br/>分享链接生成"]:::component
        QRCodeRenderer["QRCodeRenderer<br/>二维码渲染"]:::component
        ShareValidator["ShareValidator<br/>链接验证"]:::component
    end

    %% 依赖的公共能力
    subgraph CommonLayer["依赖的公共能力"]
        direction TB

        subgraph SecurityModule["security (安全组件)"]
            ShareLinkSigner["ShareLinkSigner<br/>HMAC签名"]:::common
            ExifStripper["ExifStripper<br/>EXIF剥离"]:::common
        end

        subgraph RepositoryModule["repository (数据仓库)"]
            IDataService["IDataService<br/>数据服务接口"]:::repo
            TravelRepo["TravelRepo<br/>旅行仓库"]:::repo
        end

        subgraph ApiModule["api (网络服务)"]
            HttpClient["HttpClient<br/>HTTP请求封装"]:::common
        end
    end

    %% 依赖关系
    ShareLinkGenerator -.->|"链接签名"| SecurityModule
    ShareLinkGenerator -.->|"旅行数据"| RepositoryModule
    ShareValidator -.->|"链接验证"| ApiModule

    %% 内部关系
    IDataService -->|"uses"| TravelRepo

    %% 布局
    linkStyle default stroke:#666,stroke-width:1.5px
```

---

## 5. cross-device (跨设备同步)

```mermaid
flowchart TB
    %% 样式定义
    classDef feature fill:#ff9800,stroke:#e65100,stroke-width:2px,color:#fff
    classDef common fill:#4caf50,stroke:#2e7d32,stroke-width:2px,color:#fff
    classDef repo fill:#9c27b0,stroke:#6a1b9a,stroke-width:2px,color:#fff
    classDef component fill:#f5f5f5,stroke:#333,stroke-width:1px,color:#000

    %% cross-device 模块
    subgraph CrossDeviceModule["cross-device (跨设备同步)"]
        direction TB
        CloudSyncAdapter["CloudSyncAdapter<br/>华为云同步适配"]:::component
        DeviceAdapter["DeviceAdapter<br/>页面/功能自适应"]:::component
        ConflictResolver["ConflictResolver<br/>同步冲突解决"]:::component
    end

    %% 依赖的公共能力
    subgraph CommonLayer["依赖的公共能力"]
        direction TB

        subgraph AuthModule["auth (云同步)"]
            AuthService["AuthService<br/>华为账号认证"]:::common
            CloudSyncService["CloudSyncService<br/>华为云空间同步"]:::common
        end

        subgraph RepositoryModule["repository (数据仓库)"]
            IDataService["IDataService<br/>数据服务接口"]:::repo
            RdbDataService["RdbDataService<br/>RDB本地实现"]:::repo
        end
    end

    %% 依赖关系
    CloudSyncAdapter -.->|"云同步"| AuthModule
    CloudSyncAdapter -.->|"数据同步"| RepositoryModule
    ConflictResolver -.->|"冲突检测"| RepositoryModule

    %% 内部关系
    AuthService -->|"登录后"| CloudSyncService
    IDataService -->|"implements"| RdbDataService

    %% 布局
    linkStyle default stroke:#666,stroke-width:1.5px
```

---

## 工具链

```bash
# 生成所有子图
mmdc -i C4_Level2_Feature_Subgraphs.md -o C4_Level2_Feature_map-travel.svg -w 800 -b white
mmdc -i C4_Level2_Feature_Subgraphs.md -o C4_Level2_Feature_replay.svg -w 800 -b white
mmdc -i C4_Level2_Feature_Subgraphs.md -o C4_Level2_Feature_ai-copy.svg -w 800 -b white
mmdc -i C4_Level2_Feature_Subgraphs.md -o C4_Level2_Feature_social-share.svg -w 800 -b white
mmdc -i C4_Level2_Feature_Subgraphs.md -o C4_Level2_Feature_cross-device.svg -w 800 -b white
```