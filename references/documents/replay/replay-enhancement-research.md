# Replay Feature 增广方案调研

> 调研日期: 2026-05-07
> 分支: `incremental-dev-20260423`

## 概述

本文档从**用户偏好与个性化设计**和**沉浸感视觉效果**两个维度，调研 Replay 功能的增广方案。技术可行性基于当前项目架构和 HarmonyOS NEXT 生态（参考 `hos_ref_cases` 开源案例集）。

---

## 1. 用户偏好与个性化设计

### 1.1 BGM 选择系统

**现状**: `TripReplayPage.ets:120-143` 硬编码单曲 `South-East-Traveling.mp3`，仅支持开/关切换。

**方案**: 内置多首无版权纯音乐，按风格标签分类，用户可在回放页切换，偏好持久化存储。

| 标签 | 风格描述 | 适用场景 |
|------|---------|---------|
| `清晨` | 轻钢琴 + 环境音，类似 iOS 闹钟"早起" | 自然风光类旅程 |
| `城市漫步` | LoFi 鼓点 + 电钢琴，类似 Apple "城市" | 城市打卡类旅程 |
| `夜晚` | 舒缓爵士，低音提琴主导 | 夜间/夜景类旅程 |
| `活力` | 轻快尤克里里/吉他 | 运动、户外类旅程 |
| `静谧` | 纯环境音 + 极简旋律 | 文艺/博物馆类旅程 |

**技术实现**: 已有 `AVPlayer` 基础设施，仅需:

- 在 `rawfile/` 下放置 5-6 首 `.mp3` 文件（推荐从 Pixabay Music / Uppbeat 获取无版权素材）
- BGM 偏好存入 `AppStorage` / 本地持久化（与现有 `appColorMode` 同一模式）
- UI：右上角音乐按钮从"开/关"改为"展开选曲面板"（长按切换曲目，短按开/关）

#### UI 入口设计

**入口**: `TripReplayPage` 右上角音乐图标（现有按钮改造）

**交互流程**:

```
TripReplayPage (回放中)
  │
  ├── 短按音乐按钮 (♫)     → 暂停/恢复当前 BGM（保留现有行为）
  │
  └── 长按音乐按钮 (0.5s)  → 展开 BGM 选择底部弹出面板
                                │
                                ├── 当前播放曲目标题 + 播放进度条
                                ├── 曲目列表 (Scroll)
                                │   ├── [♫] 清晨 · 轻钢琴      ← 标签 + 简短描述
                                │   ├── [♫] 城市漫步 · LoFi    ← 带内联播放预览按钮 (▶)
                                │   ├── [♫] 夜晚 · 舒缓爵士
                                │   ├── [♫] 活力 · 尤克里里
                                │   └── [♫] 静谧 · 环境音
                                ├── 音量滑块
                                └── [关闭] 按钮
```

**面板规格**: `bindSheet` 半屏弹出，高度约 55%，圆角 20px，暗色背景 (`#1A1A2E`)，曲目行高 56px，选中曲目有高亮边框 (`#1890FF`)。

**持久化**: 用户选择的 BGM ID 存入 `AppStorage` key `replayBgmId`，下次进入自动选择。

> **版权提醒**: 推荐从 **Pixabay Music**（CC0）、**Uppbeat**（免费版权）、**Freesound** 获取素材。LoFi 类可搜索 "lofi study royalty-free"。

---

### 1.2 风格套件 (Style Kit) 系统

**核心概念**: 一个全局 `ReplayStyleKit` 参数控制所有 replay 组件的视觉呈现。切换套件 = 一键换肤，套件内组件强相关，套件间视觉效果差异显著。

**套件参与的组件**:

```
StyleKit (全局参数)
  ├── ReplayPhotoCard   → 相框颜色 / 圆角 / 阴影
  ├── Map Polyline      → 连接线颜色 / 粗细 / 虚实
  ├── Map Markers       → 节点标记图标 / 颜色 / 大小
  ├── ReplayProgressBar → 进度条配色 / 滑块样式
  ├── Control Bar       → 底部控制栏背景 / 按钮颜色
  └── Typography        → 字体搭配 (补充)
```

**六套差异化风格套件设计**:

#### A. `极简白` (Minimal White) — 默认

```
卡片: 白色背景 + 12px 圆角 + 轻阴影
连接线: 细 (2px) 实线, #999999
节点标记: 小圆点, #333333
进度条: 灰色轨道 + 黑色选中
控制栏: 纯白背景
```

#### B. `暗夜黑` (Dark Night)

```
卡片: #1A1A1A 背景 + 8px 圆角 + 蓝色辉光阴影
连接线: 粗 (6px) #00D4FF 霓虹蓝, 可加发光效果
节点标记: 发光圆环, #00D4FF
进度条: 暗色轨道 + 霓虹蓝选中
控制栏: #0D0D0D 背景 + 细白边线
```

#### C. `复古胶片` (Vintage Film)

```
卡片: #F5E6D3 暖色背景 + 胶片齿孔边框装饰, 直角
连接线: 虚线 (dash pattern), #8B7355
节点标记: 电影场记板图标, #D4A574
进度条: 棕色轨道 + 金色选中
控制栏: 米色背景 + 顶部黑色细线 (类胶片)
```

#### D. `自然森系` (Forest)

```
卡片: #F0F7F0 淡绿背景 + 16px 大圆角 + 叶片装饰
连接线: 中粗 (4px) #4CAF50, geodesic
节点标记: 叶片/树图标, #2E7D32
进度条: 浅绿轨道 + 深绿选中
控制栏: 白底 + 底部绿线
```

#### E. `海洋蓝调` (Ocean)

```
卡片: 蓝白渐变背景 + 波浪形底部裁切
连接线: 中粗 (4px) #2196F3, 半透明
节点标记: 水滴图标, #1565C0
进度条: 蓝色轨道 + 深蓝选中
控制栏: 浅蓝背景 + 玻璃模糊效果 (backgroundBlurStyle)
```

#### F. `日落暖橙` (Sunset Warm)

```
卡片: 暖橙→粉红渐变背景 + 柔和圆角
连接线: 粗 (5px) 暖橙 #FF7043
节点标记: 太阳/星星图标, #E64A19
进度条: 橙色轨道 + 红橙选中
控制栏: 暖灰背景
```

**实现方案**:

```typescript
// 新增 common/service/ReplayStyleKit.ets
export enum StyleKitId {
  MINIMAL_WHITE = 'minimal_white',
  DARK_NIGHT = 'dark_night',
  VINTAGE_FILM = 'vintage_film',
  FOREST = 'forest',
  OCEAN = 'ocean',
  SUNSET = 'sunset',
}

export class ReplayStyleKit {
  // -- 卡片 --
  cardBg: string
  cardRadius: number
  cardShadow: ShadowOptions

  // -- 地图连接线 --
  polylineColor: string
  polylineWidth: number
  polylinePattern: string // 'solid' | 'dashed' | 'dotted'

  // -- 节点标记 --
  markerColor: string
  markerSize: number
  markerIcon: Resource

  // -- 进度条 --
  trackColor: string
  selectedColor: string
  blockColor: string

  // -- 控制栏 --
  controlBg: string
  controlTextColor: string

  // 预设工厂方法
  static minimalWhite(): ReplayStyleKit { ... }
  static darkNight(): ReplayStyleKit { ... }
  // ...
}
```

在 `TripReplayPage` 的 `aboutToAppear` 中从持久化存储加载用户偏好，在 StyleKit 选择面板中切换。

> **补充组件**: 控制栏按钮图标风格（线框 vs. 填充）、Walking Icon 移动动画图标（`figure_walk` vs. 自定义图标）也可纳入套件。

#### UI 入口设计

**入口 A — 回放页内快捷切换**（推荐主要入口）:

`TripReplayPage` 顶部区域新增齿轮图标 ⚙️，位于音乐按钮左侧：

```
TripReplayPage Top Bar:
┌──────────────────────────────────────────┐
│  [← 返回]              [⚙️ 设置] [♫ 音乐] │
└──────────────────────────────────────────┘
```

点击齿轮 → 打开 `ReplaySettingsSheet`（底部弹出面板），**"风格"为默认激活 Tab**：

```
┌─────────────────────────────────────────┐
│         回放设置                    [✕]  │
├─────────────────────────────────────────┤
│  [风格]    [音乐]    [特效]    [转场]     │  ← Tab 栏
├─────────────────────────────────────────┤
│                                         │
│  选择风格套件                            │
│                                         │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐   │
│  │ 极简 │ │ 暗夜 │ │ 复古 │ │ 森系 │   │  ← 横向 Scroll
│  │ 白   │ │ 黑   │ │ 胶片 │ │      │   │    卡片式选择器
│  │ 👆   │ │      │ │      │ │      │   │    当前选中 ↑
│  └──────┘ └──────┘ └──────┘ └──────┘   │
│  ┌──────┐ ┌──────┐                      │
│  │ 海洋 │ │ 日落 │         ← 可滑动     │
│  │ 蓝调 │ │ 暖橙 │                      │
│  └──────┘ └──────┘                      │
│                                         │
│  预览区域（实时预览当前套件效果）          │
│  ┌─────────────────────────────────┐    │
│  │  [模拟卡片样式] [连接线颜色]     │    │
│  │  [节点标记] [进度条预览]        │    │
│  └─────────────────────────────────┘    │
│                                         │
│              [应用此风格]                │
└─────────────────────────────────────────┘
```

**套件卡片设计**: 每个套件用 80×100 的预览卡片表示，卡片背景为该套件的主色调，带有微型卡片线框/连接线示意图。选中套件有 2px 主题色描边 + "✓" 角标。

**应用机制**: 选中新套件后即时生效（通过 `animateTo` 0.3s 过渡），无需额外确认。套件 ID 持久化到 `AppStorage` key `replayStyleKitId`。

**入口 B — 详情页预设置**（次要入口）:

`TripDetailPage` 中"播放路线"按钮下方新增一行：

```
TripDetailPage:
┌──────────────────────────────────────┐
│         [▶ 播放路线]                  │
│  回放风格: 极简白  >                  │  ← 点击进入风格选择
│  背景音乐: 城市漫步 >                 │  ← 点击进入音乐选择
└──────────────────────────────────────┘
```

这样用户在进入回放前就可以预览和调整风格偏好。点击跳转到同一套 Tab 面板。

---

### 1.3 其他个性化方向（对标成熟软件）

对比 **Instagram Stories**、**Strava**、**Google Photos Memories**、**小红书**、**抖音**、**NOMO CAM**：

| 灵感来源 | 功能 | 我们的 Replay 增广方向 |
|---------|------|---------------------|
| **Strava** | 运动轨迹热力图 | 按照片密度给连接线上色（冷暖色表示节点密集度） |
| **Instagram Stories** | 文字/贴纸自由叠加 | 回放中允许用户在照片上叠 emoji/文字水印 |
| **NOMO CAM** | 模拟胶片相机 | 整条 Replay 套一层整体滤镜（胶片颗粒/褪色/LUT），与 Style Kit 独立 |
| **Google Photos** | AI 自动精选高光 | AI 自动标记"最佳照片"作为每个节点的封面，代替当前首张 |
| **小红书** | 模板化拼图导出 | 回放结束后生成"路线总结卡片"（节点缩略图 + 路线地图截图），可保存/分享 |
| **抖音** | 转场特效 | 节点间切换除了当前的淡入淡出，增加右滑/缩放/翻页等转场选项 |
| **Flightradar24** | 3D 地球视角 | 为回放增加可选的地球缩放动画（从远处俯冲至节点） |

**技术可行性高、立即可做的**:

1. **整体滤镜叠加** — ArkUI 的 `colorFilter` / `linearGradient` / `overlay` 完全支持
2. **从照片提取主色调** — `hos_ref_cases/feature/effectkit` 已演示 `ColorPicker.getMainColorSync()`，可用来让卡片背景自适应照片颜色
3. **转场动画选项** — `TransitionEffect` + `animateTo` 已有成熟案例
4. **路线总结卡片导出** — `componentSnapshot.get()` 截图，存入相册

#### 各功能 UI 入口设计

##### 1.3.1 滤镜叠加

**入口**: `ReplaySettingsSheet` → "风格" Tab → 滤镜选择行（位于风格套件选择器下方）

```
风格 Tab 内 (套件选择器下方):
┌─────────────────────────────────────────┐
│  整体滤镜                                │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐       │
│  │ 原图 │ │ 胶片 │ │ 褪色 │ │ 黑白 │  ←  │  横向滤镜预览条
│  │  ↑   │ │     │ │     │ │     │       │  带实时照片缩略图
│  └─────┘ └─────┘ └─────┘ └─────┘       │
│  ┌─────┐ ┌─────┐                        │
│  │ 暖调 │ │ 冷调 │          ← 可滑动    │
│  └─────┘ └─────┘                        │
└─────────────────────────────────────────┘
```

每个滤镜选项用 56×56 的照片缩略图 + 滤镜名称标签展示。选中的滤镜即时应用到回放画面。持久化到 `replayFilterId`。

##### 1.3.2 照片提取主色调自适应

**入口**: `ReplaySettingsSheet` → "特效" Tab → "照片取色" 开关

```
特效 Tab 内:
┌─────────────────────────────────────────┐
│  照片取色           [═══════●] 已开启    │  ← Toggle 开关
│  卡片背景随照片颜色自动变化               │    副标题说明
└─────────────────────────────────────────┘
```

这是一个简单的 Toggle 开关，不需要独立的面板。开启后自动在 `ReplayPhotoCard` 中生效。

##### 1.3.3 转场动画选项

**入口**: `ReplaySettingsSheet` → "转场" Tab（独立 Tab 页）

```
转场 Tab 内:
┌─────────────────────────────────────────┐
│  节点切换转场效果                         │
│                                         │
│  ○ 淡入淡出 (默认)                       │  ← Radio 列表
│  ○ 平移滑入 (左→右)                      │
│  ○ 缩放弹出                              │
│  ○ 3D 翻转                               │
│  ○ 卡片飞入 (从地图位置)                  │
│                                         │
│  [▶ 预览效果]                            │  ← 点击播放一段预览动画
└─────────────────────────────────────────┘
```

选中新转场类型后即时生效，持久化到 `replayTransitionType`。

##### 1.3.4 路线总结卡片导出

**入口**: 回放结束后自动弹出 + `TripDetailPage` 手动触发

**入口 A — 自动弹出**（回放播放完毕时）:

```
回放结束后覆盖层:
┌─────────────────────────────────────────┐
│                                         │
│           🎉 旅程回放完成                 │
│                                         │
│     ┌─────────────────────────┐         │
│     │    [路线总结卡片预览]     │         │
│     │   地图缩略图 + 节点信息   │         │
│     │   总距离 · 节点数 · 时长  │         │
│     └─────────────────────────┘         │
│                                         │
│   [重新播放]    [保存到相册]    [分享]    │
└─────────────────────────────────────────┘
```

**入口 B — 手动触发**（`TripDetailPage`）:

在 TripDetailPage 的现有操作按钮区域增加第三个按钮：

```
TripDetailPage 操作按钮区域:
┌──────────────────────────────────────┐
│  [▶ 播放路线]  [📤 分享路线]          │
│  [📸 生成路线卡片]                    │  ← 新增
└──────────────────────────────────────┘
```

点击后直接在 TripDetailPage 上弹出卡片预览 + 保存选项，无需进入回放。

---

## 2. 沉浸感与视觉效果增广

基于 `hos_ref_cases` 中已验证的 ArkUI 技术，以下方案在鸿蒙前端生态中**立即可实现**：

### 2.1 节点到达特效 (Node Arrival Effect)

**参考**: `hos_ref_cases/feature/waterripples` 案例

在回放流程中，当相机到达新节点时，在节点标记位置触发**水波纹脉冲动画**——两个同心圆从标记中心扩散（opacity 0.8→0，scale 1→6x）。

```
现有流程:  FADE_IN → STAY → FADE_OUT → MOVE
增强流程:  FADE_IN + [波纹脉冲] → STAY → FADE_OUT → MOVE
```

实现位置: `TripReplayPage.ets` 的 `PHASE_FADE_IN` 阶段，参考 `waterripples` 的 `animateTo` 交错循环。

**UI 入口**: `ReplaySettingsSheet` → "特效" Tab → "节点到达波纹" Toggle 开关。无额外面板，开/关即可。

### 2.2 卡片背景自适应照片颜色

**参考**: `hos_ref_cases/feature/effectkit` 案例

在 `ReplayPhotoCard` 组件中，对每张照片使用 `effectKit.createColorPicker(pixelMap).getMainColorSync()` 提取主色调，将卡片下部的文字区域背景色设为提取色 + 渐变透明。

```
效果: 照片是蓝色大海 → 卡片底部是蓝→透明渐变
      照片是橙色日落 → 卡片底部是橙→透明渐变
```

**UI 入口**: `ReplaySettingsSheet` → "特效" Tab → "照片取色" Toggle 开关（与 1.3.2 共用同一开关）。

### 2.3 路线绘制动画 (Animated Route Drawing)

**现状**: `drawRouteAndMarkers()` 一次性绘制完整折线。

**增强**: 从起点开始逐步绘制连接线，模拟"路线被画出来"的效果。利用 `mapController.addPolyline` 的分段能力，每隔一小段时间追加一段 line segment:

```
[起点] ──动画──> [节点1] ──动画──> [节点2] ──动画──> [节点3]
```

也可以使用 Canvas Path 的 `strokeDashoffset` 技术做"生长"动画。如果 MapKit 不支持，使用叠加 Canvas 层模拟。

**UI 入口**: `ReplaySettingsSheet` → "特效" Tab → "路线绘制动画" Toggle 开关。开启后，进入回放时路线从起点逐步绘制。

### 2.4 照片转场增强 (Photo Transition)

**参考**: `hos_ref_cases/feature/cardswiperanimation` + `hos_ref_cases/feature/cuberotateanimation`

当前照片卡片使用 `animateTo` 对 `opacity` 做淡入淡出。可增加更多选项：

| 转场类型 | 实现方式 | 参考案例 |
|---------|---------|---------|
| **淡入淡出** (现有) | `animateTo` opacity | — |
| **平移滑入** | `TransitionEffect.move(LEFT/RIGHT)` | `multimodaltransion` |
| **缩放弹出** | `animateTo` scale 0.8→1 + opacity 0→1 | — |
| **3D 翻转** | `rotate({ y: 1 })` 90°→0°, 类似翻牌 | `cuberotateanimation` |
| **卡片飞入** | `animateTo` translate + rotate, 从地图标记位置飞到卡片位置 | `transitionanimation` |

**UI 入口**: `ReplaySettingsSheet` → "转场" Tab → Radio 列表选择（与 1.3.3 共用同一面板）。

### 2.5 粒子特效系统 (Particle Effects)

**技术**: ArkUI `Canvas` 组件 + `requestAnimationFrame`

在回放场景中的可用粒子效果:

- **到达节点庆祝** — 彩色粒子爆发（星空/花瓣/彩带），根据 mood 标签切换
- **连接线上微粒子流动** — 表示"路线在呼吸"
- **时间天气粒子** — 如果节点有天气数据，添加雨滴/雪花/阳光粒子

技术上完全可行：`hos_ref_cases/feature/paintcomponent` 演示了 Canvas + Path 动态绘制，在此基础上扩展粒子系统（定义粒子位置/速度/生命周期/颜色）。

**UI 入口**: `ReplaySettingsSheet` → "特效" Tab → "粒子特效" Toggle 开关。开启后进一步展开子选项:

```
特效 Tab 内 (粒子特效开启后):
┌─────────────────────────────────────────┐
│  粒子特效           [═══════●] 已开启    │
│                                         │
│  粒子主题:                              │
│  ○ 无 (仅在到达时播放庆祝粒子)           │
│  ○ 星空      ○ 花瓣                    │  ← Radio 按钮
│  ○ 彩带      ● 光点 (默认)             │
└─────────────────────────────────────────┘
```

### 2.6 沉浸式覆盖层增强

**参考**: `hos_ref_cases/feature/backgroundblur` + `hos_ref_cases/feature/fadingedge` + `hos_ref_cases/feature/miniplayeranimation`

当前 `PhotoCardOverlay` 是简单的半屏卡片 + 暗色遮罩。可增强为:

1. **毛玻璃效果**: 使用 `backgroundBlurStyle(BlurStyle.Thin)` + `backgroundBrightness()` 替代纯黑遮罩
2. **照片边缘渐变**: 使用 `fadingedge` 技法，照片两侧加线性渐变让视觉聚焦中心
3. **手势联动关闭**: `miniplayeranimation` 的 PanGesture 下滑关闭
4. **动态高度**: 根据内容量自适应覆盖层高度

**UI 入口**: `ReplaySettingsSheet` → "特效" Tab → "毛玻璃效果" Toggle 开关。此为纯视觉增强，无子选项。

### 2.7 Lottie 天气/情绪动画

**参考**: `hos_ref_cases/feature/lottieview` 案例

在回放页面为每个节点加载与 mood 标签对应的微型 Lottie 动画:

- mood=`开心` → 笑脸跳动
- mood=`安静` → 落叶飘落
- mood=`兴奋` → 星星闪烁
- 天气数据 → 太阳/云/雨/雪

Lottie 动画体积极小（几 KB JSON），可以放在 `rawfile/` 中，渲染在节点标记上方或卡片角落。

**UI 入口**: `ReplaySettingsSheet` → "特效" Tab → "情绪动画" Toggle 开关。开启后使用节点 mood 标签自动匹配对应 Lottie 动画，无手动选择。

---

## 3. UI 入口架构总览

### 3.1 设置面板统一入口：`ReplaySettingsSheet`

所有回放个性化设置集中在一个底部弹出面板中，通过 Tab 分类管理。该组件作为 `TripReplayPage` 的子组件，使用 ArkUI `bindSheet` 实现。

**触发路径汇总**:

```
TripDetailPage                      TripReplayPage
  │                                     │
  ├─ "回放风格: xxx >"  ────────────────┤
  ├─ "背景音乐: xxx >"  ────────────────┤
  │                                     │
  │                          ┌──────────┤
  │                          │          │
  └──────────────────────────┤          │
                             │    [⚙️ 齿轮按钮] (顶部工具栏)
                             │          │
                             ▼          ▼
                      ┌─────────────────────┐
                      │  ReplaySettingsSheet │
                      │  (bindSheet 弹出)    │
                      │                     │
                      │  [风格] [音乐] [特效] [转场] │
                      └─────────────────────┘
```

### 3.2 `ReplaySettingsSheet` 四 Tab 内容布局

```
┌──────────────────────────────────────────────────┐
│  回放设置                                    [✕]  │
├──────────────────────────────────────────────────┤
│   [🎨 风格]    [♫ 音乐]    [✨ 特效]    [🔄 转场]  │
├──────────────────────────────────────────────────┤
│                                                  │
│  Tab 1 — 🎨 风格:                                 │
│  ├─ 风格套件横向卡片选择器 (6 套件)                  │
│  ├─ 实时预览区 (卡片 + 连接线 + 节点示意)            │
│  └─ 滤镜叠加横向选择器 (原图/胶片/褪色/黑白/暖调/冷调) │
│                                                  │
│  Tab 2 — ♫ 音乐:                                 │
│  ├─ 当前播放曲目                                   │
│  ├─ 曲目列表 (清晨/城市漫步/夜晚/活力/静谧)          │
│  │  每行: [▶ 预览] 曲目标题 · 风格标签 · 时长       │
│  └─ 音量滑块                                      │
│                                                  │
│  Tab 3 — ✨ 特效:                                 │
│  ├─ [Toggle] 节点到达波纹                          │
│  ├─ [Toggle] 照片取色自适应                        │
│  ├─ [Toggle] 路线绘制动画                          │
│  ├─ [Toggle] 毛玻璃覆盖层                          │
│  ├─ [Toggle] 情绪动画 (Lottie)                     │
│  └─ [Toggle] 粒子特效  → 展开子选项 (星空/花瓣等)    │
│                                                  │
│  Tab 4 — 🔄 转场:                                 │
│  └─ Radio 列表: 淡入淡出 / 平移滑入 / 缩放弹出 /    │
│                  3D 翻转 / 卡片飞入                 │
│     [▶ 预览效果] 按钮                              │
│                                                  │
└──────────────────────────────────────────────────┘
```

### 3.3 回放结束覆盖层入口

```
回放播放至最后一帧后自动弹出:
┌──────────────────────────────────────┐
│                                      │
│            🎉 旅程回放完成             │
│                                      │
│      ┌────────────────────┐          │
│      │  [路线总结卡片预览]  │          │
│      │  地图 + 节点 + 统计  │          │
│      └────────────────────┘          │
│                                      │
│   [🔄 重新播放]  [💾 保存卡片]  [📤 分享] │
│                                      │
└──────────────────────────────────────┘
```

### 3.4 持久化 Key 汇总

| 持久化 Key | 类型 | 默认值 | 存储位置 |
|-----------|------|--------|---------|
| `replayStyleKitId` | `string` | `'minimal_white'` | AppStorage → Preferences |
| `replayBgmId` | `string` | `'city_walk'` | AppStorage → Preferences |
| `replayFilterId` | `string` | `'none'` | AppStorage → Preferences |
| `replayTransitionType` | `string` | `'fade'` | AppStorage → Preferences |
| `replayEnableRipple` | `boolean` | `true` | AppStorage → Preferences |
| `replayEnableAdaptiveColor` | `boolean` | `true` | AppStorage → Preferences |
| `replayEnableRouteAnim` | `boolean` | `false` | AppStorage → Preferences |
| `replayEnableBlurOverlay` | `boolean` | `true` | AppStorage → Preferences |
| `replayEnableLottie` | `boolean` | `true` | AppStorage → Preferences |
| `replayEnableParticles` | `boolean` | `false` | AppStorage → Preferences |
| `replayParticleTheme` | `string` | `'sparkle'` | AppStorage → Preferences |

### 3.5 页面修改范围

| 页面 | 新增内容 |
|------|---------|
| `TripReplayPage.ets` | 顶部齿轮按钮 ⚙️、`ReplaySettingsSheet` 绑定、样式参数响应、回放结束覆盖层 |
| `TripDetailPage.ets` | "播放路线"下方新增"回放风格"和"背景音乐"预设行、新增"生成路线卡片"按钮 |
| `ReplayPhotoCard.ets` | 接收 `ReplayStyleKit` 参数、照片取色逻辑 |
| `ReplayProgressBar.ets` | 接收 `ReplayStyleKit` 配色参数 |
| `PhotoCardOverlay.ets` | 毛玻璃效果开关、手势关闭 |

**新增文件**:

| 文件 | 职责 |
|------|------|
| `common/service/ReplayStyleKit.ets` | 风格套件数据类 + 6 套预设工厂 |
| `feature/map-travel/components/ReplaySettingsSheet.ets` | 设置面板组件（4 Tab） |
| `feature/map-travel/components/ReplayEndOverlay.ets` | 回放结束覆盖层组件 |
| `feature/map-travel/components/ReplayMusicPicker.ets` | 音乐选择子组件（可内嵌于 Sheet） |
| `feature/map-travel/components/RouteSummaryCard.ets` | 路线总结卡片组件 |

---

## 4. 优先级建议

按**实现成本→体验增益**排序:

| 优先级 | 功能 | 工作量 | 增益 | UI 入口 | 依赖 |
|-------|------|--------|------|---------|------|
| **P0** | BGM 多曲目切换 | 小 (1 天) | 高 | 回放页长按音乐按钮 → 选曲面板 | 无 |
| **P0** | 风格套件系统 (含 3 套) | 中 (2-3 天) | 高 | 回放页齿轮图标 → 设置面板 / 详情页预设行 | 无 |
| **P1** | 卡片背景自适应照片色 | 小 (半天) | 中 | 设置面板 → 特效 Tab → Toggle | `effectKit` |
| **P1** | 节点到达水波纹特效 | 小 (半天) | 中 | 设置面板 → 特效 Tab → Toggle | 无 |
| **P1** | 毛玻璃覆盖层 | 小 (半天) | 中 | 设置面板 → 特效 Tab → Toggle | `backgroundBlurStyle` |
| **P2** | 照片转场选项 (2-3 种) | 中 (1-2 天) | 中 | 设置面板 → 转场 Tab → Radio | 无 |
| **P2** | 滤镜叠加系统 | 中 (1 天) | 中 | 设置面板 → 风格 Tab → 滤镜选择器 | `colorFilter` |
| **P3** | 路线绘制动画 | 中 (1-2 天) | 中 | 设置面板 → 特效 Tab → Toggle | MapKit 分段能力 |
| **P3** | Lottie 情绪动画 | 中 (2 天) | 中 | 设置面板 → 特效 Tab → Toggle | `@ohos/lottie` |
| **P4** | 粒子特效系统 | 高 (3-5 天) | 高 | 设置面板 → 特效 Tab → Toggle + 子选项 | Canvas 粒子引擎 |
| **P4** | 路线总结卡片导出 | 高 (2-3 天) | 高 | 回放结束覆盖层 / 详情页按钮 | `componentSnapshot` |

---

## 5. 技术参考索引

| 参考案例 | 路径 | 相关功能 |
|---------|------|---------|
| 水波纹动画 | `hos_ref_cases/feature/waterripples/` | 节点到达特效 |
| 照片主色提取 | `hos_ref_cases/feature/effectkit/` | 卡片背景自适应 |
| 卡片轮播动画 | `hos_ref_cases/feature/cardswiperanimation/` | 照片转场增强 |
| 3D 旋转 | `hos_ref_cases/feature/cuberotateanimation/` | 照片转场增强 |
| 毛玻璃效果 | `hos_ref_cases/feature/backgroundblur/` | 覆盖层增强 |
| 边缘渐变 | `hos_ref_cases/feature/fadingedge/` | 覆盖层增强 |
| 迷你播放器动画 | `hos_ref_cases/feature/miniplayeranimation/` | 手势联动 |
| 页面转场 | `hos_ref_cases/feature/transitionanimation/` | 卡片飞入 |
| 多模态转场 | `hos_ref_cases/feature/multimodaltransion/` | 转场选项 |
| Lottie 动画 | `hos_ref_cases/feature/lottieview/` | 情绪动画 |
| Canvas 绘制 | `hos_ref_cases/feature/paintcomponent/` | 粒子特效 |
| 橡皮擦/绘图 | `hos_ref_cases/feature/eraser/` | Canvas 交互 |
| 地图图钉动画 | `hos_ref_cases/feature/mapthumbtack/` | 节点标记动画 |

---

## 6. 当前 Replay 相关文件索引

| 文件 | 职责 |
|------|------|
| `feature/map-travel/pages/TripReplayPage.ets` | 主回放页，含地图、播放状态机、音频、移动动画 |
| `feature/map-travel/pages/TripDetailPage.ets` | 旅程详情页，含"播放路线"入口按钮 |
| `feature/map-travel/components/ReplayPhotoCard.ets` | 悬浮照片卡片（Swiper + 标题 + 标签） |
| `feature/map-travel/components/ReplayProgressBar.ets` | 离散步进进度条 |
| `feature/map-travel/components/PhotoCardOverlay.ets` | 底部半屏展开覆盖层 |
| `common/service/types.ets` | `ReplayNode`、`ReplayRoute`、`Position` 数据模型 |
| `common/utils/Constants.ets` | `AppColors`、`AppTheme`、`AppDimens`、路由常量 |
| `references/diagrams/C4_Level2_Feature_replay.svg` | Replay 功能 C4 架构图 |
