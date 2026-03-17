# Preliminary Requirement Analysis
经过讨论，第七小组最终选择鸿蒙应用开发赛道。以下是本次项目开发的初步需求分析。

## 1. Functional Requirements

以下是本次项目拟开发系统的5个核心功能特性。

### 1. 打造专属的时空地图
将你的照片、故事和心情直接“钉”在它们发生的精确地理位置上。把一张空白的世界地图，逐渐点亮成一个只属于你的、基于地理位置的沉浸式生活日记，让每一次打卡都变得立体可见。

### 2. 亲手编排并动态重温旅途
你可以自由挑选、组合特定的记忆节点，将其归档为一次专属旅程。系统会智能梳理这些节点，并为你渲染出一条连贯的旅行轨迹。点击播放，地图便会沿着你精心编排的路线平滑穿梭，以电影般的动态视觉效果，带你沉浸式重温这段独一无二的故事。

### 3. 跨平台一键路线分享
一键即可生成精美的旅行路线专属网页链接，并轻松分享至微信、微博等各大社交平台。你的朋友无需下载和注册任何应用，直接通过网络浏览器就能流畅观看你的完整旅程，并留下评论互动。

### 4. AI 智能生成社交文案
当你不知道该写什么时，只需选中你想分享的照片和打卡地点，内置的智能 AI 助手就能根据图片的视觉氛围和地理位置特征，瞬间生成多套引人入胜、风格各异的社交网络文案，让你随时随地完美发帖。

### 5. 多设备无缝漫游与协同
你的所有地图节点、旅行路线和草稿都会在手机、平板和电脑网页端之间实时自动同步。在旅途中使用手机 APP 便捷记录瞬间，回家后在电脑大屏浏览器上无缝接力，继续精修你的万字游记。

## 2. Non-Functional Requirements

### 1. 性能需求
* **地图渲染帧率：** 地图上节点或者渲染路线过多时需要选择部分渲染来保证性能和帧率。
* **媒体加载延迟：** 所有节点的图片必须快速加载。
* **AI 响应市场 (AI Response TTFB)：** 调用大模型生成文案时需要保证响应速度。


### 2. 安全与隐私需求
* **强制元数据清洗：** 系统在接收用户上传的原始图片时，必须在网关或文件处理服务层强制剥离全部 Exif 数据（包含设备型号、绝对经纬度、拍摄时间等），或者就把图片保存在本地。
* **防越权共享：** 对外分享的一键链接必须采用强加密签名（如 HMAC-SHA256），且包含有效期（TTL）。禁止使用可遍历的自增 ID（如 `/share/1234`）作为路由，防止爬虫批量抓取用户轨迹。
* **AI生成内容安全合规：** 所有通过 AI 助手生成的社交文案，在持久化到数据库之前，必须经过敏感词和违规内容的文本风控过滤。

### 3. 可靠性与可用性需求
* **离线优先架构 (Offline-First)：** 移动端应用必须能在完全断网的模式下正常工作。用户可以继续添加节点、编辑草稿，所有修改必须优先写入本地存储（SQLite/IndexedDB）。
* **最终一致性同步 (Eventual Consistency)：** 在网络恢复后，多端数据同步必须使用后台队列重试机制，并基于时间戳或版本号实现冲突解决策略，保证同步成功率达到 **99.9%**。

### 4. 资源消耗限制
* **功耗控制 (Battery Consumption)：** 处于后台运行状态时，必须停止一切非必要的 GPS 轮询和 WebSocket 心跳维持，后台耗电量每小时不得超过总电量的 **1%**。
* **流量降级 (Bandwidth Degradation)：** 在非 Wi-Fi 环境下，系统必须默认停止原图和视频的自动预加载，转而仅请求低分辨率占位图，严格控制用户的蜂窝网络流量消耗。

## 3.Technical requirements:

### 1. 前端与系统技术栈
* **核心框架：** 基于 **ArkTS** 的 **ArkUI** 声明式开发框架。
* **地图服务：** 需要进一步调研。
* **本地持久化：** 需要进一步调研。
* **跨端协同：** 需要进一步调研。

### 2. 后端与 AI 基础设施
* **后端框架：** 需要进一步调研。
* **通信机制：** 需要进一步调研。
* **数据库：** 需要进一步调研。


### 3. 媒体与云服务
* **对象存储：** 需要进一步调研。
* **AI 能力：** 需要进一步调研。

## 4.Data requirements

### 1. 数据类型与获取方式
* **地理空间数据：** 通过鸿蒙系统 `LocationHub` 获取实时 GPS 坐标，需经过用户显式授权。
* **媒体资源：** 通过系统级照片选择器（Photo Picker）访问用户图片和视频，遵循“最小权限原则”，不申请全量相册权限。
* **AI 上下文数据：** 提取图片的视觉标签和地理位置名称，作为 Prompt 输入大模型以生成文案。

### 2. 数据处理与隐私
* **预处理：** 所有上传图片在服务端强制擦除 EXIF 敏感信息，并自动生成多尺寸缩略图以优化加载。
* **存储策略：** 热数据（当前行程）存储于本地关系型数据库 (RDB)；冷数据（历史行程）归档于云端 PostGIS 空间数据库。

## 架构图
graph TD
    %% 定义颜色与样式
    classDef need fill:#262057,stroke:#fff,stroke-width:2px,color:#fff,rx:10px,ry:10px;
    classDef epic fill:#D60F5D,stroke:#fff,stroke-width:2px,color:#fff,rx:10px,ry:10px;
    classDef story fill:#0DA2B3,stroke:#fff,stroke-width:2px,color:#fff,rx:10px,ry:10px;
    classDef task fill:#7D7D7D,stroke:#fff,stroke-width:2px,color:#fff,rx:4px,ry:4px;
    classDef criteria fill:#9BD18A,stroke:#fff,stroke-width:2px,color:#fff,rx:4px,ry:4px;

    %% 节点定义 (基于你的 Proposal 需求分析)
    UN["<b>User Need</b><br/>As a user, I want to structurally record, organize, and share my life<br/>and travel memories based on geographical locations using a HarmonyOS app"]:::need

    E1["<b>Epic 1: Core Map & Memory</b><br/>Manage location nodes, dynamic<br/>trajectories, and data synchronization"]:::epic
    E2["<b>Epic 2: Social & AI Features</b><br/>Generate AI copy and share<br/>travel routes cross-platform"]:::epic

    US1["<b>User story (Map Check-in)</b><br/>As a regular user, I want to add<br/>memory nodes at specific GPS<br/>coordinates on the map"]:::story
    US2["<b>User story (Trajectory)</b><br/>As a traveler, I want to combine<br/>multiple nodes into a route and<br/>play it dynamically"]:::story
    US3["<b>User story (Sync)</b><br/>As a multi-device user, I want<br/>my data to sync automatically<br/>between phone and PC"]:::story
    
    US4["<b>User story (AI Copy)</b><br/>As a social media sharer, I want<br/>the system to automatically generate<br/>social media copy"]:::story
    US5["<b>User story (Sharing)</b><br/>As a content creator, I want to<br/>generate a web link for my travel<br/>route with one click"]:::story

    T1["Tasks<br/>Fetch GPS & Photo Picker"]:::task
    T2["Tasks<br/>Render map animation"]:::task
    T3["Tasks<br/>Cloud queue & retry sync"]:::task
    T4["Tasks<br/>Invoke LLM API"]:::task
    T5["Generate secure<br/>route URL"]:::task
    T6["Develop read-only<br/>H5 page"]:::task

    AC1["Acceptance criteria<br/>(Strip Exif metadata)"]:::criteria
    AC2["Acceptance criteria<br/>(Clustering & Frame rate)"]:::criteria
    AC3["Acceptance criteria<br/>(99.9% sync success)"]:::criteria
    AC4["Acceptance criteria<br/>(Content risk filter)"]:::criteria
    
    AC5["<b>It's done when the user can:</b><br/>1. Get AI-generated copy based on image & location features.<br/>2. Generate a secure external link (HMAC-SHA256, TTL).<br/>3. View the shared read-only H5 route on an external browser."]:::criteria

    %% 层级连接
    UN --> E1
    UN --> E2
    
    %% 模拟图中左侧直接从User Need连到User Story的线
    UN -.- US1 

    E1 --> US1
    E1 --> US2
    E1 --> US3

    E2 --> US4
    E2 --> US5

    US1 --> T1
    US1 --> AC1
    
    US2 --> T2
    US2 --> AC2
    
    US3 --> T3
    US3 --> AC3
    
    US4 --> T4
    US4 --> T5
    US4 --> AC4
    
    US5 --> T6
    
    %% 将右侧的 User Story 连到共同的 Acceptance Criteria
    US4 --> AC5
    US5 --> AC5
