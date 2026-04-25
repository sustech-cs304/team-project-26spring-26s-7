# Sprint 2 UI/UX Issues 清单

**创建日期**: 2026-04-22  
**里程碑**: Sprint 2 - UI/UX 优化  
**分支**: `sprint1`

---

## Issues 总览

| ID | 标题 | 类型 | 模块 | 优先级 | 状态 |
|----|------|------|------|--------|------|
| #1 | 不同尺寸照片的自适应设计问题 | UI | map-travel | 🟡 P1 | ⏳ Open |
| #2 | 地图选点初始停留位置未考虑用户偏好 | UX | map-travel | 🟢 P2 | ⏳ Open |
| #3 | 音乐播放功能缺少用户控制开关 | UX | trip-replay | 🟢 P2 | ⏳ Open |
| #4 | 地图首页节点上方缺少图片展示和聚合效果 | UI | map-travel | 🟡 P1 | ⏳ Open |
| #5 | 无图片节点的占位显示页面过大 | UI | map-travel | 🟢 P2 | ⏳ Open |
| #6 | 旅行名称在地图浏览框中是白字看不清 | UI | map-travel | 🟡 P1 | ⏳ Open |
| #7 | 离线删除节点后恢复网络无法立即刷新 | Sync | cloud-sync | 🔴 P0 | ⏳ Open |
| #8 | 长按选点仅显示经纬度，建议显示具体地名 | UX | map-travel | 🟢 P2 | ⏳ Open |
| #9 | 浅色/暗色模式切换功能缺失 | UX | common | 🟡 P1 | ⏳ Open |
| #10 | 部分页面地图非全面屏，上下有空白 | UI | map-travel | 🟡 P1 | ⏳ Open |
| #11 | 编辑旅行页面"添加节点"照片无法上传 | Bug | map-travel | 🔴 P0 | ⏳ Open |
| #12 | APP 独立存在一段时间后华为账号登录失效 | Auth | auth | 🔴 P0 | ⏳ Open |
| #13 | 公开/私密功能的底层实现需白箱化 | Backend | backend | 🟡 P1 | ⏳ Open |
| #14 | 播放/前进后退按钮使用 emoji 不够专业 | UI | trip-replay | 🟢 P2 | ⏳ Open |
| #15 | 节点所属旅行变化时云端原路径照片未删除 | Sync | cloud-sync | 🟡 P1 | ⏳ Open |
| #16 | 节点的时间属性需要可以被编辑与正常云同步 | UX | map-travel | 🟡 P1 | ⏳ Open |
| #17 | 新节点 NodeOrder 未成功上传至云端 | Sync | cloud-sync | 🔴 P0 | ⏳ Open |
| #18 | 手动上传后节点下标跳跃问题 | Sync | cloud-sync | 🟡 P1 | ⏳ Open |
| #19 | 游客身份登录功能缺失 | Auth | auth | 🟡 P1 | ⏳ Open |

**优先级说明**:
- 🔴 P0: 最高优先级 - 功能缺失/数据一致性问题
- 🟡 P1: 中等优先级 - UI/UX 缺陷
- 🟢 P2: 低优先级 - 体验优化

---

## Issue #1: 不同尺寸照片的自适应设计问题

**优先级**: 🟡 P1

### 问题描述
用户上传的照片尺寸比例不一（如 4:3, 16:9, 1:1 等），当前在节点卡片、详情页、回放页等位置的展示效果不一致，部分场景可能存在拉伸、裁剪不当或留白过多问题。

### 涉及场景
- 节点列表卡片封面 (`NodeListView.ets`)
- 节点详情页大图展示 (`NodeDetailPage.ets`)
- 旅行回放照片卡片 (`TripReplayPage.ets`, `ReplayPhotoCard.ets`)
- 旅行详情页地图浏览框 (`TripDetailPage.ets`)

### 期望行为
- 统一使用 `ImageFit.Cover` 或 `ImageFit.Contain` 策略
- 卡片封面统一裁剪比例（如 1:1 或 4:3）
- 详情页大图支持缩放查看完整图片
- 回放照片卡片保持视觉一致性

### 涉及文件
- `frontend/entry/src/main/ets/feature/map-travel/views/NodeListView.ets`
- `frontend/entry/src/main/ets/feature/map-travel/components/ReplayPhotoCard.ets`
- `frontend/entry/src/main/ets/feature/map-travel/pages/TripDetailPage.ets`

### 验收标准
- [ ] 所有照片展示场景使用统一的适配策略
- [ ] 卡片封面尺寸统一，无参差不齐
- [ ] 用户可查看完整原图（支持缩放）

---

## Issue #2: 地图选点初始停留位置未考虑用户偏好

**优先级**: 🟢 P2

### 问题描述
地图选点页面 (`LocationPickerPage`) 或地图首页 (`MapHomeView`) 的初始中心点固定为深圳 (22.55, 113.96)，未根据用户历史偏好、常用地点或定位自动调整。

### 期望行为
- 首次启动时使用定位或默认城市（如深圳）
- 后续启动时优先定位到用户最近一次使用的地点
- 或根据用户已创建节点的中心点自动调整
- 支持"回到当前位置"快捷按钮

### 涉及文件
- `frontend/entry/src/main/ets/feature/map-travel/views/MapHomeView.ets`
- `frontend/entry/src/main/ets/feature/map-travel/pages/LocationPickerPage.ets`
- `frontend/entry/src/main/ets/entryability/EntryAbility.ets`

### 修改建议
1. 在 `AppStorage` 中保存用户上次地图中心点
2. 启动时读取定位权限，获取当前位置
3. 计算已创建节点的地理中心作为默认视图

### 验收标准
- [ ] 地图初始位置考虑用户历史数据
- [ ] 支持快捷回到当前位置
- [ ] 定位失败时有降级策略（如默认深圳）

---

## Issue #3: 音乐播放功能缺少用户控制开关

**优先级**: 🟢 P2

### 问题描述
旅行回放 (`TripReplayPage`) 功能中，背景音乐播放缺少用户控制入口（播放/暂停按钮），用户无法自定义是否播放音乐。

### 期望行为
- 回放页面增加音乐开关按钮（右上角）
- 支持播放/暂停状态切换

### 涉及文件
- `frontend/entry/src/main/ets/feature/map-travel/pages/TripReplayPage.ets`

### 修改建议
1. 使用音符图标按钮（图案为音符，背景为圆形，颜色符合主题）
2. 使用 `@State` 管理播放状态
3. 点击一下颜色发生变化（暂停到播放：浅色到深色，反过来同理）

### 验收标准
- [ ] 回放页面有明确的播放/暂停按钮

---

## Issue #4: 地图首页节点上方缺少图片展示和聚合效果

**优先级**: 🟡 P1

### 问题描述
地图首页 (`MapHomeView`) 中，地图上的节点 Marker 仅显示标题和地点名，缺少节点封面图片的预览。同时多个节点聚集时缺少聚合展示效果（如数字标记）。

### 期望行为
- Marker 点击后预览卡片显示节点封面图
- 多节点聚集时显示聚合标记（如"5 个节点"）
- 聚合标记可展开查看该区域所有节点

### 涉及文件
- `frontend/entry/src/main/ets/feature/map-travel/views/MapHomeView.ets`
- `frontend/entry/src/main/ets/feature/map-travel/components/PhotoCardOverlay.ets`

### 修改建议
1. 优化 `setupMarkerClickListener` 中预览卡片的图片展示
2. 使用 MapKit 的 Marker 聚合功能或自定义聚合逻辑
3. 聚合标记使用圆形背景 + 数字展示

### 验收标准
- [ ] Marker 预览卡片正确显示封面图
- [ ] 多节点聚集时显示聚合标记
- [ ] 聚合标记可点击展开

---

## Issue #5: 无图片节点的占位显示页面过大

**优先级**: 🟢 P2

### 问题描述
当节点没有图片时，占位符（当前为"📍"emoji + "无封面"文字）在卡片中占据空间过大，视觉上不协调。

### 涉及文件
- `frontend/entry/src/main/ets/feature/map-travel/views/NodeListView.ets` (行 210-223)
- `frontend/entry/src/main/ets/feature/map-travel/pages/NodeDetailPage.ets`

### 修改建议
1. 缩小占位符容器尺寸（如从 92x92 改为 64x64）
2. 使用更简洁的占位图标
3. 调整背景色和文字颜色对比度

### 验收标准
- [ ] 占位符尺寸与有图卡片视觉平衡
- [ ] 占位图标简洁清晰
- [ ] 整体视觉协调统一

---

## Issue #6: 旅行名称在地图浏览框中是白字看不清

**优先级**: 🟡 P1

### 问题描述
旅行详情页 (`TripDetailPage`) 地图浏览框上方的旅行名称使用白色文字 (`#FFFFFF`)，在浅色背景或天空场景下对比度不足，难以辨认。

### 涉及文件
- `frontend/entry/src/main/ets/feature/map-travel/pages/TripDetailPage.ets` (行 250-258)

### 修改建议
1. 为文字添加深色背景遮罩（当前已有 `#00000055`，可调深）
2. 或为文字添加阴影效果增强对比度
3. 或根据背景亮度动态调整文字颜色

### 验收标准
- [ ] 旅行名称在任何地图背景下清晰可见
- [ ] 文字与背景对比度符合无障碍标准

---

## Issue #7: 离线删除节点后恢复网络无法立即刷新

**优先级**: 🔴 P0 (最高优先级)

### 问题描述
用户在离线状态下删除节点，恢复网络连接后，点击"下载云端"按钮，被删除的节点不会立即从节点展示页面消失，需要重新登录才能看到删除效果。这疑似是同步刷新机制的问题。

### 复现步骤
1. 断开网络连接
2. 在节点详情页删除一个节点
3. 恢复网络连接
4. 点击"下载云端"同步按钮
5. 观察节点展示页面中被删除的节点是否消失

### 期望行为
- 同步完成后，本地数据库中被软删除的节点应立即从 UI 中移除
- 或同步逻辑正确处理删除操作的逆向同步

### 涉及文件
- `frontend/entry/src/main/ets/common/sync/SyncManager.ets`
- `frontend/entry/src/main/ets/common/sync/CloudSyncService.ets`
- `frontend/entry/src/main/ets/common/data/MemoryNodeRepository.ets`
- `frontend/entry/src/main/ets/common/data/TravelRepository.ets`

### 修改建议
1. 检查 `SyncManager.pullAllCloudToLocal()` 是否处理了云端删除标记
2. 检查本地软删除 (`deleted_at`) 是否与云端同步逻辑一致
3. 同步完成后确保触发 `travelDataVersion` 更新
4. 或在 UI 层添加同步完成后的强制刷新逻辑

### 验收标准
- [ ] 同步完成后，被删除节点立即从 UI 消失
- [ ] 无需重新登录或手动刷新页面
- [ ] 本地与云端删除状态一致

---

## Issue #8: 长按选点仅显示经纬度，建议显示具体地名

**优先级**: 🟢 P2

### 问题描述
在地图首页长按选点创建节点时，仅自动填入经纬度坐标（如"22.5500, 113.9600"），而新增节点页面 (`NodeEditPage`) 中的地图标点功能可以获取具体地名（POI 名称）。建议统一两者的逻辑。

### 涉及文件
- `frontend/entry/src/main/ets/feature/map-travel/views/MapHomeView.ets` (行 516-531)
- `frontend/entry/src/main/ets/feature/map-travel/pages/LocationPickerPage.ets`
- `frontend/entry/src/main/ets/feature/map-travel/pages/NodeEditPage.ets`

### 修改建议
1. 在 `setupMapLongClickListener` 中，长按选点后调用逆地理编码 API 获取地名
2. 将获取到的 POI 名称传递给 `NodeEditPage`
3. 复用 `LocationPickerPage` 中的地名获取逻辑

### 验收标准
- [ ] 长按选点后自动填充具体地名
- [ ] 地名获取失败时降级显示经纬度
- [ ] 与新增节点页面的地名获取逻辑一致

---

## Issue #9: 浅色/暗色模式切换功能缺失

**优先级**: 🟡 P1

### 问题描述
当前应用主题色固定在 `EntryAbility.onCreate()` 中设置为 `COLOR_MODE_NOT_SET`，不支持浅色/暗色模式切换，也不支持跟随系统。

### 期望行为
- 支持三种模式：浅色、暗色、跟随系统
- 在个人中心设置页面增加主题切换入口
- 主题切换后全局生效
- 所有 UI 组件适配两种主题

### 涉及文件
- `frontend/entry/src/main/ets/entryability/EntryAbility.ets` (行 84-88)
- `frontend/entry/src/main/ets/common/utils/Constants.ets` (AppColors 定义)
- `frontend/entry/src/main/ets/feature/profile/views/ProfileView.ets` (设置入口)

### 修改建议
1. 在 `EntryAbility` 中移除固定的 `setColorMode` 调用
2. 使用 `AppStorage` 管理主题模式状态
3. 在 `ProfileView` 设置页面增加主题切换选项
4. 定义暗色主题的颜色常量
5. 使用 `@Watch` 监听主题变化并全局刷新

### 验收标准
- [ ] 设置页面可切换浅色/暗色/跟随系统
- [ ] 切换后全局 UI 颜色适配
- [ ] 主题偏好持久化

---

## Issue #10: 部分页面地图非全面屏，上下有空白

**优先级**: 🟡 P1

### 问题描述
地图首页 (`MapHomeView`) 和旅行详情页 (`TripDetailPage`) 的地图组件在某些设备上不是全面屏展示，上下两侧存在空白区域，视觉体验不佳。

### 涉及文件
- `frontend/entry/src/main/ets/feature/map-travel/views/MapHomeView.ets`
- `frontend/entry/src/main/ets/feature/map-travel/pages/TripDetailPage.ets`
- `frontend/entry/src/main/ets/pages/MainPage.ets` (可能需要检查 Tab 布局)

### 修改建议
1. 检查 `MapComponent` 的 `width('100%')` 和 `height('100%')` 是否正确继承
2. 检查父容器是否有固定高度或 padding 限制
3. 使用 `layoutWeight(1)` 确保地图填满可用空间
4. 检查安全区域适配（刘海屏、灵动岛）

### 验收标准
- [ ] 地图组件占满整个屏幕可视区域
- [ ] 上下无多余空白
- [ ] 适配不同屏幕尺寸和安全区域

---

## Issue #11: 编辑旅行页面"添加节点"照片无法上传

**优先级**: 🔴 P0 (最高优先级)

### 问题描述
在编辑旅行页面 (`TripEditPage`) 使用"添加节点"功能时，照片选择器无法正常工作，用户上传的照片无法显示或保存。

### 复现步骤
1. 打开旅行编辑页面
2. 点击"添加节点"
3. 使用照片选择器选择照片
4. 观察照片是否正确展示和保存

### 期望行为
- 照片选择器正常工作
- 选中的照片在编辑器中展示
- 保存后照片正确关联到节点

### 涉及文件
- `frontend/entry/src/main/ets/feature/map-travel/pages/TripEditPage.ets`
- `frontend/entry/src/main/ets/feature/map-travel/components/PhotoSelector.ets`
- `frontend/entry/src/main/ets/common/utils/PhotoPickerUtil.ets`

### 修改建议
1. 检查 `PhotoSelector` 组件是否正确接收 `photos` 双向绑定
2. 检查照片选择回调是否正确更新状态
3. 检查沙箱路径权限和照片读取逻辑

### 验收标准
- [ ] 照片选择器可正常选择和预览
- [ ] 照片正确关联到节点
- [ ] 保存后照片在详情页正常展示

---

## Issue #12: APP 独立存在一段时间后华为账号登录失效

**优先级**: 🔴 P0 (最高优先级)

### 问题描述
APP 在手机中独立存在一段时间（如后台运行或锁屏）后，重新打开时需要重新使用华为账号登录。这疑似是 Session 持久化或 Token 刷新机制的问题。

### 复现步骤
1. 使用华为账号登录
2. 将 APP 切到后台或锁屏
3. 等待一段时间（如 30 分钟）
4. 重新打开 APP
5. 观察是否需要重新登录

### 期望行为
- Session Token 在有效期内保持有效
- Token 过期前自动刷新
- 用户无需频繁重新登录

### 涉及文件
- `frontend/entry/src/main/ets/common/auth/AuthService.ets`
- `frontend/entry/src/main/ets/common/auth/CloudStorageService.ets`
- `frontend/entry/src/main/ets/entryability/EntryAbility.ets` (Session 恢复逻辑)

### 修改建议
1. 检查 `AuthService.restoreSession()` 的实现逻辑
2. 检查 Token 有效期和刷新机制
3. 在 `EntryAbility.onForeground()` 中检查 Session 状态
4. 增加 Token 自动刷新逻辑

### 验收标准
- [ ] Session 在有效期内保持有效
- [ ] Token 过期前自动刷新
- [ ] 用户无需频繁重新登录

---

## Issue #13: 公开/私密功能的底层实现需白箱化

**优先级**: 🟡 P1

### 问题描述
当前旅行和节点的"公开/私密"属性在前端有展示（如 `trip.isPublic`），但底层实现逻辑不清晰，包括：
- 公开/私密数据在云端的存储策略
- 分享链接的访问控制
- 公开数据的可见性范围

### 期望行为
- 明确公开/私密数据的存储和访问规则
- 实现基于公开属性的访问控制
- 分享链接支持有效期和访问权限控制

### 涉及文件
- `frontend/entry/src/main/ets/common/service/types.ets` (数据模型定义)
- `frontend/entry/src/main/ets/common/sync/CloudTravel.ets`
- 后端相关 API 和数据库 Schema

### 修改建议
1. 在前端数据模型中明确 `isPublic` 字段的语义
2. 与后端协作实现基于 `isPublic` 的访问控制
3. 分享链接生成时检查 `isPublic` 属性
4. 私密数据的分享需特殊处理（如一次性链接）

### 验收标准
- [ ] 公开/私密字段在前端后端语义一致
- [ ] 私密数据不会被未授权访问
- [ ] 分享链接的权限控制正确

---

## Issue #14: 播放/前进后退按钮使用 emoji 不够专业

**优先级**: 🟢 P2

### 问题描述
旅行回放页面 (`TripReplayPage`) 中的播放控制按钮（播放/暂停、前进、后退）当前使用 emoji 字符（如"▶️"、"⏸️"、"⏪"、"⏩"），视觉风格不够专业，与整体 UI 设计不协调。

### 期望行为
- 使用 SVG 图标或系统图标替代 emoji
- 图标风格与整体 UI 一致
- 增加按钮点击态和禁用态样式

### 涉及文件
- `frontend/entry/src/main/ets/feature/map-travel/pages/TripReplayPage.ets`
- `frontend/entry/src/main/resources/base/element/media.png` (可能需要新增图标资源)

### 修改建议
1. 使用 HarmonyOS 系统图标资源（`$r('app.media.*')`）
2. 或引入第三方图标库（如 Remix Icon、Material Icons）
3. 或使用 SVG 自定义图标
4. 为按钮增加 `:active` 和 `:disabled` 状态样式

### 验收标准
- [ ] 控制按钮使用专业图标
- [ ] 图标风格与整体 UI 一致
- [ ] 按钮有明确的交互反馈

---

## Issue #15: 节点所属旅行变化时云端原路径照片未删除

**优先级**: 🟡 P1

### 问题描述
当节点的 `travelId` 发生变化时（如从旅行 A 移动到旅行 B），云端存储中原旅行路径下的照片没有被删除，导致云端存储冗余和潜在的数据不一致。

### 期望行为
- 节点变更旅行时，云端原路径下的照片被删除或移动
- 云端照片路径与节点归属保持一致
- 删除操作在同步队列中正确处理

### 涉及文件
- `frontend/entry/src/main/ets/common/sync/CloudSyncService.ets`
- `frontend/entry/src/main/ets/common/sync/CloudMemoryNode.ets`
- `frontend/entry/src/main/ets/common/sync/SyncManager.ets`
- `frontend/entry/src/main/ets/common/data/MemoryNodeRepository.ets`

### 修改建议
1. 在 `updateNode` 时检测 `travelId` 是否变化
2. 如变化，将原照片路径加入删除队列
3. 同步时将删除操作上传到云端
4. 或在云端通过 `cloud_id` 关联重新组织照片路径

### 验收标准
- [ ] 节点变更旅行后，原路径照片被删除
- [ ] 云端照片路径与节点归属一致
- [ ] 无冗余照片残留

---

## Issue #16: 节点的时间属性需要可以被编辑与正常云同步

**优先级**: 🟡 P1

### 问题描述
当前节点编辑页面 (`NodeEditPage.ets`) 不支持编辑节点的时间属性 (`createdAt`)，用户无法修改记忆的发生时间。同时，如果未来支持时间编辑，该属性的变更也需要正确同步到云端。

### 期望行为
- 节点编辑页面提供时间选择器，允许用户修改记忆发生时间
- 时间修改后正确保存到本地数据库
- 时间属性的变更能够正确同步到云端
- 时间变更后，节点在时间轴上的排序自动更新

### 涉及文件
- `frontend/entry/src/main/ets/feature/map-travel/pages/NodeEditPage.ets`
- `frontend/entry/src/main/ets/common/service/types.ets` (`MemoryNode.createdAt`)
- `frontend/entry/src/main/ets/common/sync/CloudMemoryNode.ets`
- `frontend/entry/src/main/ets/common/sync/SyncManager.ets`

### 修改建议
1. 在 `NodeEditPage` 中增加时间选择器组件（使用 ArkUI 的 DatePicker）
2. 将 `createdAt` 加入可编辑状态，支持用户修改
3. 保存时将修改后的时间写入 `MemoryNode`
4. 确保同步逻辑正确处理 `createdAt` 字段的更新
5. 时间变更后，触发所在旅行的节点重新排序

### 验收标准
- [ ] 节点编辑页面可修改时间属性
- [ ] 修改后正确保存到本地数据库
- [ ] 时间变更后云端同步正常
- [ ] 节点在时间轴上的位置自动更新

---

## Issue #17: 新建节点 NodeOrder 未成功上传至云端

**优先级**: 🔴 P0 (最高优先级)

### 问题描述
在添加新节点后，节点的 `nodeOrder` 字段没有成功上传至云端数据库。云端数据库中 `nodeOrder` 字段为空，导致节点排序异常。只有手动触发上传后才能恢复正常。

### 复现步骤
1. 创建一个新节点并保存
2. 查看云端数据库中该节点的 `nodeOrder` 字段
3. 观察该字段是否为空或异常值
4. 手动触发上传同步
5. 再次查看云端数据库，观察 `nodeOrder` 是否恢复正常

### 期望行为
- 新节点创建时，`nodeOrder` 自动计算并赋值
- 同步时 `nodeOrder` 正确上传到云端
- 无需手动上传即可保持排序正确

### 涉及文件
- `frontend/entry/src/main/ets/common/data/MemoryNodeRepository.ets` (getNextNodeOrder 方法)
- `frontend/entry/src/main/ets/common/sync/CloudSyncService.ets`
- `frontend/entry/src/main/ets/common/sync/CloudMemoryNode.ets`
- `frontend/entry/src/main/ets/common/sync/SyncManager.ets`
- 后端云数据库 Schema (nodeOrder 字段定义)

### 修改建议
1. 检查 `MemoryNodeRepository.insert()` 中 `nodeOrder` 的赋值逻辑
2. 检查 `CloudSyncService.buildNodePayload()` 是否包含 `nodeOrder` 字段
3. 检查云端数据库写入时 `nodeOrder` 的处理
4. 确保 `nodeOrder` 在同步队列中被正确传递

### 验收标准
- [ ] 新节点创建后 `nodeOrder` 立即同步到云端
- [ ] 云端数据库 `nodeOrder` 字段不为空
- [ ] 无需手动上传即可保持正确排序
- [ ] 多节点场景下排序顺序正确

---

## Issue #18: 手动上传后节点下标跳跃问题

**优先级**: 🟡 P1

### 问题描述
在手动触发上传同步后，部分节点会出现下标跳跃现象。例如，原本顺序为第 4 的节点，在同步后获得了 index 6，导致节点显示顺序错乱。

### 复现步骤
1. 创建多个节点（如 6 个），观察初始排序
2. 手动触发上传同步
3. 再次查看节点列表排序
4. 观察是否有节点的 index 发生跳跃

### 期望行为
- 同步后节点排序保持不变
- `nodeOrder` 值不因同步而重新计算
- 原有顺序与云端一致

### 涉及文件
- `frontend/entry/src/main/ets/common/data/MemoryNodeRepository.ets`
- `frontend/entry/src/main/ets/common/sync/SyncManager.ets`
- `frontend/entry/src/main/ets/common/service/RdbDataService.ets`

### 修改建议
1. 检查 `SyncManager.syncAllLocalToCloud()` 是否重新计算了 `nodeOrder`
2. 检查 `upsertFromCloud()` 是否正确保留原有 `nodeOrder`
3. 确保 `nodeOrder` 是"写入一次，永不重算"的逻辑
4. 同步时应读取并保留本地已有的 `nodeOrder`，而非重新生成

### 验收标准
- [ ] 同步后节点排序不变
- [ ] 无下标跳跃现象
- [ ] 本地与云端排序一致

---

## Issue #19: 游客身份登录功能缺失

**优先级**: 🟡 P1

### 问题描述
当前应用仅支持华为账号登录，不支持游客身份使用。用户在没有华为账号或不愿登录的情况下无法使用应用的基本功能。

### 期望行为
- 首次打开应用时提供"游客登录"选项
- 游客模式下可使用本地功能（创建节点、旅行等）
- 游客模式下云同步功能禁用或提示升级
- 游客可随时切换到华为账号登录并同步数据

### 涉及文件
- `frontend/entry/src/main/ets/pages/LoginPage.ets`
- `frontend/entry/src/main/ets/common/auth/AuthService.ets`
- `frontend/entry/src/main/ets/entryability/EntryAbility.ets`
- `frontend/entry/src/main/ets/feature/profile/views/ProfileView.ets`

### 修改建议
1. 在 `LoginPage` 增加"以游客身份继续"按钮
2. 创建游客身份的虚拟 User 对象（uid 为 "guest"）
3. 游客模式下禁用云同步相关功能和 UI
4. 在 `ProfileView` 提供"升级为正式用户"入口
5. 切换登录时迁移游客数据到云端

### 验收标准
- [ ] 登录页面有游客登录入口
- [ ] 游客可正常使用本地功能
- [ ] 云同步功能对游客有明确提示
- [ ] 游客可无缝切换到正式账号

---

## 附录：模块与文件映射

| 模块 | 涉及文件 |
|------|---------|
| **map-travel** | `MapHomeView.ets`, `NodeEditPage.ets`, `NodeListView.ets`, `TripDetailPage.ets`, `TripEditPage.ets`, `LocationPickerPage.ets` |
| **trip-replay** | `TripReplayPage.ets`, `ReplayPhotoCard.ets`, `ReplayProgressBar.ets`, `PhotoCardOverlay.ets` |
| **cloud-sync** | `CloudSyncService.ets`, `CloudMemoryNode.ets`, `CloudTravel.ets`, `SyncManager.ets` |
| **auth** | `AuthService.ets`, `CloudStorageService.ets`, `LoginPage.ets` |
| **data** | `RdbDataService.ets`, `TravelRepository.ets`, `MemoryNodeRepository.ets`, `types.ets` |
| **common** | `Constants.ets`, `PhotoPickerUtil.ets`, `EntryAbility.ets`, `ProfileView.ets` |

---

## 下一步操作

1. ✅ 确认本清单内容无误
2. ⏭️ 使用 `gh issue create` 发布到 GitHub
3. ⏭️ 分配负责人并开始修复
4. ⏭️ 按优先级顺序依次处理
