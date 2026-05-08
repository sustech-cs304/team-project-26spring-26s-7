# Replay Feature 增广实现计划

> 规划日期: 2026-05-07
> 输入文档: `references/documents/replay/replay-enhancement-research.md`
> 当前代码基线: `feature/social-share`
> 实施原则: 先建立可扩展配置骨架，再逐步接入视觉、音乐、转场和高成本特效。

## 1. 需求理解

这份增广需求不是单点功能，而是把当前 Replay 从“固定样式的路线播放页”升级为“可配置的沉浸式回放系统”。核心能力可以归纳为四层:

1. 用户偏好层: BGM、风格套件、滤镜、转场、特效开关需要有统一配置和持久化。
2. 表现参数层: 地图折线、节点标记、照片卡片、进度条、控制栏、覆盖层都要能读取同一套 replay 配置。
3. UI 入口层: `TripReplayPage` 内提供设置入口，`TripDetailPage` 提供进入回放前的预设入口。
4. 特效增强层: 波纹、照片取色、玻璃覆盖层、滤镜、转场、路线绘制动画、粒子、Lottie、结束总结卡等按收益和风险分批实现。

当前代码中 Replay 的主要逻辑集中在:

| 文件 | 当前职责 | 对实现计划的影响 |
| --- | --- | --- |
| `frontend/entry/src/main/ets/feature/map-travel/pages/TripReplayPage.ets` | 地图、播放状态机、BGM、移动动画、控制栏 | 需要先拆配置和子组件，避免继续膨胀 |
| `frontend/entry/src/main/ets/feature/map-travel/pages/TripDetailPage.ets` | 旅行详情和“播放路线”入口 | 适合新增回放预设入口，但不应承载复杂设置逻辑 |
| `frontend/entry/src/main/ets/feature/map-travel/components/ReplayPhotoCard.ets` | 悬浮照片卡片 | 需要接收 style/filter/transition/adaptiveColor 参数 |
| `frontend/entry/src/main/ets/feature/map-travel/components/ReplayProgressBar.ets` | 离散节点进度条 | 需要接收 style kit 配色 |
| `frontend/entry/src/main/ets/feature/map-travel/components/PhotoCardOverlay.ets` | 照片展开覆盖层 | 需要接入玻璃/手势/动态高度等增强 |
| `frontend/entry/src/main/ets/common/service/types.ets` | `ReplayNode` / `ReplayRoute` 数据模型 | 可放基础类型，但 replay 偏好配置建议独立文件 |
| `frontend/entry/src/main/resources/rawfile/` | 当前仅有 `South-East-Traveling.mp3` | 多 BGM 需要补充授权明确的音频素材 |

## 2. 实施总策略

不要一次性实现研究文档里的全部效果。建议分成 6 个可回滚、可验收的阶段:

| Phase | 目标 | 推荐优先级 | 主要风险 |
| --- | --- | --- | --- |
| Phase 0 | 配置模型、偏好存储、UI 骨架 | P0 | 低 |
| Phase 1 | 多 BGM + 设置面板音乐页 | P0 | 音频素材授权、AVPlayer 切源 |
| Phase 2 | Style Kit 基础版 + 组件参数化 | P0 | MapKit 折线/Marker 样式支持范围 |
| Phase 3 | 低成本视觉增强 | P1 | ArkUI 属性兼容性 |
| Phase 4 | 转场和播放状态机增强 | P2 | 状态机和动画时序回归 |
| Phase 5 | 高成本特效与导出 | P3/P4 | API、性能、权限、素材依赖 |

每个阶段都要求能独立编译，尽量保持现有 Replay 行为作为默认值。

## 3. 推荐文件结构

新增文件建议:

```text
frontend/entry/src/main/ets/
├── common/
│   └── replay/
│       ├── ReplayPreferences.ets      # 偏好 key、默认值、读写封装
│       ├── ReplayStyleKit.ets         # 风格套件枚举、工厂、展示元数据
│       ├── ReplayMusicCatalog.ets     # BGM 列表、rawfile 文件名、标签
│       └── ReplayEffectOptions.ets    # 滤镜/转场/特效枚举与默认配置
└── feature/map-travel/components/
    ├── ReplaySettingsSheet.ets        # 统一设置面板
    ├── ReplayMusicPicker.ets          # 可选；音乐 Tab 子组件
    ├── ReplayStylePicker.ets          # 可选；风格 Tab 子组件
    ├── ReplayEndOverlay.ets           # 回放结束覆盖层
    └── RouteSummaryCard.ets           # 总结卡预览/后续导出基础
```

说明:

1. 研究文档建议 `common/service/ReplayStyleKit.ets`，但从职责看更适合放到 `common/replay/`，避免把 UI 配置塞进 service 层。
2. 如团队希望少建目录，也可以放入 `common/service/`，但要在 `common/index.ets` 做统一导出，避免页面直接深层相对导入。
3. `ReplaySettingsSheet` 初期可以只实现 Style/Music 两个 Tab，Effects/Transition 先留禁用项或占位文案。

## 4. 任务清单

### Phase 0: 配置模型与设置面板骨架

目标: 建立后续所有功能的基础，不改变默认播放效果。

| ID | 任务 | 修改范围 | 验收标准 |
| --- | --- | --- | --- |
| R0.1 | 新建 replay 配置目录和类型定义 | `common/replay/*` | 定义 `ReplayStyleKitId`、`ReplayBgmId`、`ReplayFilterId`、`ReplayTransitionType` 等枚举 |
| R0.2 | 新建 `ReplayPreferences` | `common/replay/ReplayPreferences.ets` | 封装 `AppStorage` key、默认值、读取、写入、版本刷新 |
| R0.3 | 在 `common/index.ets` 导出 replay 配置 | `common/index.ets` | 页面和组件能通过 `../../../common` 引入 |
| R0.4 | 新建 `ReplaySettingsSheet` 空骨架 | `feature/map-travel/components/ReplaySettingsSheet.ets` | 支持 `@Prop/@Link` 接收当前配置，能打开/关闭 |
| R0.5 | `TripReplayPage` 新增齿轮入口 | `TripReplayPage.ets` | 右上角音乐按钮左侧显示设置按钮，点击弹出设置面板 |
| R0.6 | 构建验证 | `frontend/` | `git diff --check` 通过，`assembleHap` 通过 |

实现要点:

1. 默认配置必须复刻当前行为: minimal style、当前 BGM、fade 转场、无路线绘制动画、无粒子。
2. `TripReplayPage` 只负责读取当前配置和传参，不在页面里硬编码所有风格细节。
3. 设置变更先使用 `AppStorage.setOrCreate`，如果后续发现应用重启不持久，再补 Preferences 文件持久化。

### Phase 1: 多 BGM 与音乐选择

目标: 从硬编码单曲升级为可选择曲库，并保持现有音乐开关行为。

| ID | 任务 | 修改范围 | 验收标准 |
| --- | --- | --- | --- |
| R1.1 | 建立 BGM 曲库元数据 | `ReplayMusicCatalog.ets` | 每首曲目包含 id、标题、标签、描述、rawfile 文件名、默认音量 |
| R1.2 | 替换硬编码 `South-East-Traveling.mp3` | `TripReplayPage.ets` | `initAndPlayMusic()` 根据当前 `replayBgmId` 取 rawfile |
| R1.3 | 支持切歌时释放旧播放器并重新初始化 | `TripReplayPage.ets` | 切换曲目后当前播放状态正确，不出现双音轨 |
| R1.4 | 实现音乐 Tab | `ReplaySettingsSheet.ets` / `ReplayMusicPicker.ets` | 可查看曲目列表、选中当前曲目、调整音量占位或基础滑块 |
| R1.5 | 音乐按钮交互保留 | `TripReplayPage.ets` | 短按仍是暂停/恢复；长按打开设置面板音乐 Tab 可作为增强项 |
| R1.6 | 素材接入 | `resources/rawfile/` | 至少新增 2-3 首授权明确的 mp3，文件名稳定 |

实现要点:

1. 音频素材必须记录来源和授权，建议在 `references/documents/replay/music-attribution.md` 记录。
2. 没有素材前可以先用单曲元数据完成代码结构，不要虚构授权。
3. AVPlayer 切源要走 `stop/release/create/prepare/play`，不要在旧实例上直接覆盖 `fdSrc`。

### Phase 2: Style Kit 基础版

目标: 先实现 3 套稳定风格，并打通组件参数化。

建议首批风格:

1. `minimal_white`: 当前默认风格，回归基准。
2. `dark_night`: 差异明显，适合验证深色 UI。
3. `vintage_film`: 差异明显，适合验证卡片、进度条、控制栏联动。

| ID | 任务 | 修改范围 | 验收标准 |
| --- | --- | --- | --- |
| R2.1 | 实现 `ReplayStyleKit` 工厂 | `ReplayStyleKit.ets` | 输出卡片、进度条、控制栏、折线、marker 的基础参数 |
| R2.2 | `ReplayPhotoCard` 接收 style 参数 | `ReplayPhotoCard.ets` | 卡片背景、圆角、阴影、文字颜色随 style 变化 |
| R2.3 | `ReplayProgressBar` 接收 style 参数 | `ReplayProgressBar.ets` | track/selected/block/label 颜色随 style 变化 |
| R2.4 | `TripReplayPage` 控制栏读取 style | `TripReplayPage.ets` | 底部控制栏背景、按钮颜色随 style 变化 |
| R2.5 | 地图折线读取 style | `TripReplayPage.ets` | `addPolyline` 的 width、颜色能力按 MapKit 实际 API 接入；不支持时记录降级 |
| R2.6 | 设置面板 Style Tab | `ReplaySettingsSheet.ets` | 可选择 3 套 style，选择后即时生效并保存 |
| R2.7 | `TripDetailPage` 预设入口 | `TripDetailPage.ets` | “播放路线”下方显示当前风格/BGM，点击可打开选择或跳转到 replay 设置 |

实现要点:

1. `TripReplayPage.drawRouteAndMarkers()` 目前有 `routeRendered` 防重绘。切换 style 后如折线样式变化，需要支持清理并重绘，或者明确“下次进入生效”。
2. Marker 自定义图标可能需要资源文件或 MapKit bitmap 能力，Phase 2 可以先只改 alpha/zIndex/默认 marker 降级。
3. `vintage_film` 的胶片齿孔边框不要先做复杂矢量，先用边框/背景/阴影表达，后续再增强。

### Phase 3: 低成本视觉增强

目标: 在不大改播放状态机的前提下提升视觉差异。

| ID | 任务 | 修改范围 | 验收标准 |
| --- | --- | --- | --- |
| R3.1 | 滤镜枚举和 Style Tab 滤镜行 | `ReplayEffectOptions.ets` / `ReplaySettingsSheet.ets` | 支持 none/film/warm/cool/mono 的选择和持久化 |
| R3.2 | 图片区域滤镜 | `ReplayPhotoCard.ets` / `PhotoCardOverlay.ets` | 通过 ArkUI 支持的 `colorFilter`、overlay 或渐变实现基础滤镜 |
| R3.3 | 玻璃覆盖层开关 | `PhotoCardOverlay.ets` | 开启后使用 blur/半透明背景；不支持时退化为现有遮罩 |
| R3.4 | 节点到达波纹 | 新组件或 `TripReplayPage.ets` | 在 `PHASE_FADE_IN` 开始时触发轻量波纹动画 |
| R3.5 | Effects Tab 基础开关 | `ReplaySettingsSheet.ets` | 波纹、玻璃覆盖层、滤镜开关可配置 |

实现要点:

1. 波纹建议使用 `Stack + Circle + animateTo`，不要第一版就引入 Canvas 粒子系统。
2. 照片主色提取依赖 EffectKit，先作为单独任务，不与普通滤镜绑定。
3. 所有视觉增强必须有开关，默认值要保守，避免低端设备卡顿。

### Phase 4: 转场与播放状态机增强

目标: 增加 2-3 种照片卡片转场，控制复杂度。

| ID | 任务 | 修改范围 | 验收标准 |
| --- | --- | --- | --- |
| R4.1 | 转场枚举和设置 UI | `ReplayEffectOptions.ets` / `ReplaySettingsSheet.ets` | 支持 fade/slide/scale 三种 |
| R4.2 | 抽象卡片进入/退出动画 | `TripReplayPage.ets` | 当前 `cardOpacity` 扩展为 opacity/scale/translate |
| R4.3 | 接入 slide 转场 | `TripReplayPage.ets` | 节点切换时卡片平移进入/退出，手动跳转不闪旧内容 |
| R4.4 | 接入 scale 转场 | `TripReplayPage.ets` | 卡片弹出缩放，不影响地图移动 |
| R4.5 | 回归播放控制 | `TripReplayPage.ets` | 播放、暂停、上一节点、下一节点、进度条跳转行为稳定 |

实现要点:

1. 不建议第一轮做 3D 翻转和卡片飞入，因为当前卡片强制刷新依赖 `isCardVisible=false/true`，复杂转场容易与状态刷新冲突。
2. 先把 `playSequence()` 里进入/停留/退出动画抽成小方法，再加转场分支。
3. 每种转场都要测试单节点、两节点、多节点三种路线。

### Phase 5: 高成本增强和导出能力

目标: 在主链路稳定后再做，避免占用 P0/P1 交付窗口。Phase 5 内部再按“路线表达清晰度优先”拆成三层，先交付路线留痕基础版，再做运动标记增强，最后再评估粒子、Lottie 和导出。

| ID | 任务 | 优先级 | 前置条件 | 验收标准 |
| --- | --- | --- | --- | --- |
| R5.1 | 照片主色提取 | P3 | EffectKit API 验证 | 卡片底部背景可随当前照片主色变化，有失败降级 |
| R5.2 | 路线留痕基础版 | P3 | MapKit overlay 清理/双 polyline 能力验证 | 回放开始时显示“未来路线底线 + 已走路线高亮”，手动跳转可直接同步到目标节点 |
| R5.3 | 路线运动标记增强 | P3 | 地图投影与 UI overlay 同步稳定 | 路线上有主题化小圆点/标记随当前段移动，和已走路线状态一致 |
| R5.4 | Lottie 心情动画 | P3 | 依赖包和 JSON 素材确认 | 根据 mood 显示轻量动画，不阻塞回放 |
| R5.5 | 路线粒子尾迹 | P4 | Canvas/ArkUI overlay 性能验证 | 开启后可见轻量拖尾/火花，关闭后完全退回无粒子模式 |
| R5.6 | ReplayEndOverlay | P3 | 播放完成事件稳定 | 回放结束显示重新播放/保存/分享入口 |
| R5.7 | RouteSummaryCard 导出 | P4 | 截图、相册写入、权限验证 | 可保存路线总结卡到本地相册 |

#### Phase 5 分层交付

##### Layer 1: 路线留痕基础版

目标: 先解决“黑色连接线信息密度低”的核心问题，把路线拆成“未来路线”和“已走路线”两层。

| ID | 任务 | 修改范围 | 分层验收标准 |
| --- | --- | --- | --- |
| R5.2a | 双路线 polyline 模型 | `TripReplayPage.ets` / `ReplayStyleKit.ets` | 主题提供 `routePendingColor`、`routeVisitedColor`、对应宽度；现有单线逻辑可切换回退 |
| R5.2b | 未来路线底线 | `TripReplayPage.ets` | 回放进入后全程浅色底线可见，未播放时也能正确显示 |
| R5.2c | 已走路线高亮留痕 | `TripReplayPage.ets` | 自动播放时已走路线按节点推进；手动拖动/上一节点/下一节点时直接同步到目标节点 |
| R5.2d | 路线动画开关 | `ReplayEffectOptions.ets` / `ReplaySettingsSheet.ets` / `TripReplayPage.ets` | 关闭开关后退回当前静态路线表现，不影响回放主链路 |

测试建议:

1. 单节点路线: 不应出现异常 polyline，只显示节点和卡片。
2. 两节点路线: 自动播放时底线先显示，高亮线在移动完成后覆盖第一段。
3. 多节点路线: 手动拖动进度条到中间节点时，高亮线应直接更新到目标节点，不等待整段动画补完。
4. 切换主题后重新进入 Replay: 底线和留痕颜色、宽度随 style 改变。

##### Layer 2: 路线运动标记增强

目标: 让“当前正在走哪一段”更加明确，但不引入高成本粒子系统。

| ID | 任务 | 修改范围 | 分层验收标准 |
| --- | --- | --- | --- |
| R5.3a | 运动标记视觉升级 | `TripReplayPage.ets` / `ReplayStyleKit.ets` | 现有移动图标升级为主题化小圆点或轻量 travel dot，不遮挡主卡片 |
| R5.3b | 标记与路线状态同步 | `TripReplayPage.ets` | 圆点位置、相机移动、已走路线更新三者时序一致 |
| R5.3c | 节点到达反馈复用 | `TripReplayPage.ets` | 到达节点时复用已有波纹或轻量 pulse，不新增复杂依赖 |
| R5.3d | 手动跳转一致性 | `TripReplayPage.ets` | 手动跳转仍保持快速模式，不为追踪标记牺牲响应速度 |

测试建议:

1. 自动播放时观察圆点是否沿当前段移动，且不会和底部卡片重叠得过于突兀。
2. 连续点击“下一节点”时，圆点不能回跳到旧段。
3. 拖动进度条快速跳到末尾再回到中间节点时，圆点和高亮线必须同步，不出现旧定时器串扰。
4. `0.5x / 1x / 2x` 三档速度下，圆点动画都应跟随当前移动时长变化。

##### Layer 3: 粒子与演示增强

目标: 只在 Layer 1/2 稳定后再追求更强视觉表现，且默认关闭。

| ID | 任务 | 修改范围 | 分层验收标准 |
| --- | --- | --- | --- |
| R5.5a | 粒子尾迹预研 | 新组件或 `TripReplayPage.ets` | 明确采用 ArkUI overlay 还是 Canvas；失败可直接整层跳过 |
| R5.5b | 主题适配策略 | `ReplayStyleKit.ets` / `ReplaySettingsSheet.ets` | 仅对适合的主题开放较强发光效果，复古主题保持克制 |
| R5.5c | 性能与默认值 | `TripReplayPage.ets` / 设置面板 | 默认关闭；开启后帧率可接受，退出页面不残留定时器或绘制对象 |

测试建议:

1. 粒子关闭时，表现必须与 Layer 2 完全一致。
2. 粒子开启时，自动播放 30s 以上不能出现明显掉帧或残影残留。
3. 切后台、退出 Replay、切换音乐和主题时，粒子对象必须正确释放。

实现要点:

1. 路线绘制动画不要从“整条线流动特效”起步，先做“未来路线底线 + 已走路线高亮”的双层表达，这一层收益最高、风险最低。
2. 当前运动标记优先继续使用 UI overlay + 地图投影坐标，不建议第一轮把复杂 marker 自定义压到 MapKit 本身。
3. 手动跳转必须保持当前“快速响应优先”的交互，不应为了路线动画重新引入完整退出/进入时序。
4. 粒子效果定位为演示增强，默认关闭，且只在 Layer 1/2 稳定后再做。
5. 导出总结卡涉及 `componentSnapshot`、媒体库写入权限、分享链路，建议单独开任务，不要和路线动画或粒子混在一起。

## 5. 分支和提交建议

建议按阶段拆分提交，避免一个 PR 同时改配置、音频、样式和动画:

1. `feat(replay): add replay preference model and settings sheet`
2. `feat(replay): support selectable background music`
3. `feat(replay): apply style kits to replay components`
4. `feat(replay): add lightweight replay visual effects`
5. `feat(replay): support configurable photo transitions`
6. `feat(replay): add replay completion summary overlay`

每个提交都应保持 `assembleHap` 可通过。

## 6. 验收清单

### 基础回归

- [ ] 无节点旅行进入 Replay 时仍提示“当前旅行还没有可回放的节点”。
- [ ] 单节点旅行可显示卡片、播放/暂停不崩溃。
- [ ] 多节点旅行可播放完整路线，进度条、上一节点、下一节点、跳转都正常。
- [ ] 进入页面自动播放 BGM，退出页面释放播放器。
- [ ] 设置面板打开/关闭不会打断地图和卡片显示。

### 偏好持久化

- [ ] 选择 BGM 后退出 Replay 再进入仍保持选择。
- [ ] 选择 Style Kit 后退出 Replay 再进入仍保持选择。
- [ ] 切换滤镜/转场/特效开关后能立即生效或明确提示“下次进入生效”。

### 视觉和性能

- [ ] 三套基础风格下文字对比度可读。
- [ ] 深色风格下控制栏、进度条、照片卡片没有白底穿帮。
- [ ] 快速连续点击播放/暂停、切歌、切风格不会出现重复音轨或卡片旧数据。
- [ ] 低成本特效开启后没有明显掉帧。

### 构建检查

- [ ] `git diff --check`
- [ ] `cd frontend; powershell -ExecutionPolicy Bypass -File build.ps1 --mode module -p module=entry@default assembleHap`

## 7. 风险和决策点

| 风险 | 影响 | 建议决策 |
| --- | --- | --- |
| BGM 素材版权不明确 | 不能提交音频资源 | 先提交曲库结构，素材来源确认后再加 mp3 |
| `AppStorage` 不等于重启持久化 | 偏好可能只在进程内有效 | Phase 0 先封装读写，后续可替换为 Preferences，不影响调用方 |
| MapKit polyline/marker 样式能力有限 | Style Kit 地图部分可能降级 | 先实现卡片/进度条/控制栏，地图样式按 API 能力渐进增强 |
| 播放状态机已经较集中 | 转场改动容易引入回归 | Phase 4 前先抽动画方法，不直接堆分支 |
| 粒子/Lottie/导出依赖重 | 可能拖慢 P0/P1 | 明确放到 Phase 5，不作为首版验收条件 |

## 8. 推荐首个开发切片

首个切片建议只做 Phase 0，产出一个“能打开但只含基础选项的设置面板”，不改播放表现。这样可以先确认 ArkUI 的 `bindSheet`、状态传递、`AppStorage` key、导入路径和构建是否稳定。

完成 Phase 0 后再进入 Phase 1/2。这样即使 BGM 素材或 MapKit 样式遇到阻塞，也不会影响 Replay 配置基础设施。
