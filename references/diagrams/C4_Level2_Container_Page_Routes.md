# Page Routes - 页面路由图

**生成日期**: 2026-04-18  
**数据来源**: 
- `main_pages.json` (路由配置)
- `router.pushUrl()` 实际调用代码

---

## 注册页面列表

根据 `main_pages.json`，共注册 **14 个页面**：

| 序号 | 路由路径 | 页面名称 |
|-----|---------|---------|
| 1 | `pages/Index` | Index (启动页) |
| 2 | `pages/LoginPage` | LoginPage (登录页) |
| 3 | `pages/MainPage` | MainPage (主页) |
| 4 | `feature/map-travel/pages/NodeEditPage` | NodeEditPage (节点编辑) |
| 5 | `feature/map-travel/pages/NodeDetailPage` | NodeDetailPage (节点详情) |
| 6 | `feature/map-travel/pages/TripEditPage` | TripEditPage (旅行编辑) |
| 7 | `feature/map-travel/pages/TripDetailPage` | TripDetailPage (旅行详情) |
| 8 | `feature/map-travel/pages/TripReplayPage` | TripReplayPage (轨迹回放) |
| 9 | `feature/map-travel/pages/LocationPickerPage` | LocationPickerPage (地图选点) |
| 10 | `feature/social-share/pages/SharePage` | SharePage (分享页面) |
| 11 | `feature/ai-copy/pages/AiCopyPage` | AiCopyPage (AI文案) |
| 12 | `feature/profile/pages/ProfileEditPage` | ProfileEditPage (编辑资料) |

---

## Mermaid 路由图（基于实际代码）

```mermaid
flowchart TB
    %% 样式定义
    classDef entry fill:#1168bd,stroke:#0b4a8a,stroke-width:2px,color:#fff
    classDef main fill:#ff9800,stroke:#e65100,stroke-width:2px,color:#fff
    classDef feature fill:#4caf50,stroke:#2e7d32,stroke-width:2px,color:#fff
    classDef utility fill:#607d8b,stroke:#455a64,stroke-width:1px,color:#fff

    %% 入口流程
    Index["Index<br/>启动页"]:::entry
    LoginPage["LoginPage<br/>登录页"]:::entry
    MainPage["MainPage<br/>主页(4个Tab)"]:::entry

    %% MainPage 的 4 个 Tab (View层，不是Page)
    subgraph MainTabs["MainPage 的 4 个 Tab (View)"]
        MapHomeView["MapHomeView<br/>地图主页"]:::main
        TripListView["TripListView<br/>旅行列表"]:::main
        NodeListView["NodeListView<br/>节点列表"]:::main
        ProfileView["ProfileView<br/>个人中心"]:::main
    end

    %% 核心页面 (map-travel)
    NodeEdit["NodeEditPage<br/>节点编辑"]:::feature
    NodeDetail["NodeDetailPage<br/>节点详情"]:::feature
    TripEdit["TripEditPage<br/>旅行编辑"]:::feature
    TripDetail["TripDetailPage<br/>旅行详情"]:::feature
    TripReplay["TripReplayPage<br/>轨迹回放"]:::feature
    LocationPicker["LocationPickerPage<br/>地图选点"]:::utility

    %% 功能页面 (其他模块)
    AiCopy["AiCopyPage<br/>AI文案"]:::feature
    SharePage["SharePage<br/>分享页面"]:::feature
    ProfileEdit["ProfileEditPage<br/>编辑资料"]:::feature
    TripAlbumView["TripAlbumView<br/>相册视图"]:::main

    %% ==================== 入口路由 ====================
    Index -->|"自动路由"| LoginPage
    Index -->|"已登录"| MainPage
    LoginPage -->|"登录成功"| MainPage

    %% ==================== MainPage Tab 路由 ====================
    MainPage -->|"Tab1"| MapHomeView
    MainPage -->|"Tab2"| TripListView
    MainPage -->|"Tab3"| NodeListView
    MainPage -->|"Tab4"| ProfileView

    %% ==================== MapHomeView 路由 ====================
    MapHomeView -->|"点击Marker"| NodeDetail
    MapHomeView -->|"点击预览卡片"| NodeDetail
    MapHomeView -->|"搜索结果选点"| NodeEdit
    MapHomeView -->|"长按地图"| NodeEdit
    MapHomeView -->|"点击相机图标"| NodeEdit

    %% ==================== TripListView 路由（修正）====================
    TripListView -->|"点击旅行卡片"| TripDetail
    TripListView -->|"新建旅行"| TripEdit

    %% ==================== TripDetailPage 路由 ====================
    TripDetail -->|"点击节点"| NodeDetail
    TripDetail -->|"回放按钮"| TripReplay
    TripDetail -->|"分享按钮"| SharePage
    TripDetail -->|"新建节点"| NodeEdit
    TripDetail -->|"编辑旅行"| TripEdit

    %% ==================== NodeListView 路由 ====================
    NodeListView -->|"点击节点"| NodeDetail
    NodeListView -->|"编辑按钮"| NodeEdit

    %% ==================== NodeDetailPage 路由 ====================
    NodeDetail -->|"编辑按钮"| NodeEdit
    NodeDetail -->|"点击旅行名"| TripDetail

    %% ==================== NodeEditPage 路由 ====================
    NodeEdit -->|"AI文案按钮"| AiCopy
    NodeEdit -->|"选择位置"| LocationPicker
    NodeEdit -->|"上传图片"| TripAlbumView

    %% ==================== TripEditPage 路由 ====================
    TripEdit -->|"点击节点"| NodeDetail
    TripEdit -->|"新建节点"| NodeEdit

    %% ==================== ProfileView 路由 ====================
    ProfileView -->|"编辑按钮"| ProfileEdit

    %% 布局优化
    linkStyle default stroke:#666,stroke-width:1.5px
```

---

## 路由统计表

| 源页面 | 可跳转目标数量 | 目标页面 |
|-------|--------------|---------|
| **Index** | 2 | LoginPage, MainPage |
| **LoginPage** | 1 | MainPage |
| **MainPage** | 4 | MapHomeView, TripListView, NodeListView, ProfileView |
| **MapHomeView** | 2 | NodeDetail, NodeEdit |
| **TripListView** | 2 | TripDetail, TripEdit |
| **TripDetailPage** | 5 | NodeDetail, TripReplay, SharePage, NodeEdit, TripEdit |
| **NodeListView** | 2 | NodeDetail, NodeEdit |
| **NodeDetailPage** | 2 | NodeEdit, TripDetail |
| **NodeEditPage** | 3 | AiCopyPage, LocationPickerPage, TripAlbumView |
| **TripEditPage** | 2 | NodeDetail, NodeEdit |
| **ProfileView** | 1 | ProfileEditPage |

---

## 代码证据

### Index.ets
```typescript
// 自动路由到 LoginPage 或 MainPage
if (isLoggedIn) {
  router.replaceUrl({ url: RouterUrls.MAIN })
} else {
  router.replaceUrl({ url: RouterUrls.LOGIN })
}
```

### MapHomeView.ets
```typescript
// Line 348: 点击搜索结果
router.pushUrl({ url: RouterUrls.NODE_EDIT, params: { ... } })

// Line 517: 长按地图
router.pushUrl({ url: RouterUrls.NODE_EDIT, params: { ... } })

// Line 744: 点击相机图标
router.pushUrl({ url: RouterUrls.NODE_EDIT })

// Line 810: 点击 Marker
router.pushUrl({ url: RouterUrls.NODE_DETAIL, params: { nodeId } })
```

### TripDetailPage.ets
```typescript
// Line 430: 点击节点
router.pushUrl({ url: RouterUrls.NODE_DETAIL, params: { nodeId } })

// Line 498: 回放按钮
router.pushUrl({ url: RouterUrls.TRIP_REPLAY, params: { tripId } })

// Line 510: 分享按钮
router.pushUrl({ url: RouterUrls.SHARE, params: { tripId } })

// Line 598: 新建节点
router.pushUrl({ url: RouterUrls.NODE_EDIT, params: { tripId } })

// Line 611: 编辑旅行
router.pushUrl({ url: RouterUrls.TRIP_EDIT, params: { tripId } })
```

---

## 工具链

```bash
mmdc -i Page_Routes.md -o Page_Routes.svg -w 1800 -b white
```