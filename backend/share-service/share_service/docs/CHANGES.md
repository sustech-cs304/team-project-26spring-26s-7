# share_service 后端改动记录

> 仓库：`/data2/cse12310817/backend/share_service/`
> 关联前端文档：`team-project-26spring-26s-7/references/documents/social-share/前端接入实现说明.md`
> 关联前端契约：`team-project-26spring-26s-7/references/documents/social-share/分享系统 API 规范.md`

本文档按迭代倒序记录，最新的在最上面。

---

## 2026-05-08 · 迭代 v1.0 · 回放偏好（5 BGM / 3 styleKit / 5 filter / 3 transition / 2 toggle）后端对齐

### 背景

前端 `incremental-dev-20260423` 分支把 `TripReplayPage` 大幅扩展为可定制：5 首背景音乐、3 套配色（极简白 / 暗夜蓝 / 复古胶片）、5 种照片滤镜、3 种节点切换动画、2 个开关（毛玻璃模态、路线动画）。本迭代把这些偏好接到 publish 链路上，让分享出去的 `/sreplay/...` 页面**完整复刻发布者本机回放设置的视觉**。

### Wire 协议（`POST /api/v1/share/publish` 新 6 个可选 multipart 字段）

| 字段 | 类型 | 允许值（与 frontend ArkTS enum value 对齐，全小写） |
|---|---|---|
| `replayStyleKitId` | str | `minimal_white` / `dark_night` / `vintage_film` |
| `replayBgmId` | str | `morning_chill_birds` / `city_lights_lofi` / `jazz_night` / `tropical_chill_travel` / `cinematic_ambient` |
| `replayFilterId` | str | `none` / `film` / `warm` / `cool` / `mono` |
| `replayTransitionType` | str | `fade` / `slide` / `scale` |
| `replayEnableBlurOverlay` | bool | `true`/`false` / `1`/`0` |
| `replayEnableRouteAnimation` | bool | 同上 |

容错优先：任何字段不在白名单 → fallback 到默认（不报 400），让前后端 enum 不同步时不阻塞 publish。完全没传任何 replay 字段 → DB 存 `replay_prefs_json IS NULL`，viewer 走全局 default。

### 改动文件

| 文件 | 改动 |
|---|---|
| [`db/schema_publish.sql`](../db/schema_publish.sql) | `share_publish` 表新增 `replay_prefs_json TEXT` 列 |
| [`db/repository_publish.py`](../db/repository_publish.py) | idempotent `ALTER TABLE` 给老 DB 补列；`insert_publish` passthrough |
| [`models/publish.py`](../models/publish.py) | `REPLAY_STYLE_KITS` / `REPLAY_BGMS` / `REPLAY_FILTERS` / `REPLAY_TRANSITIONS` 白名单 + `REPLAY_DEFAULT` + `normalize_replay_prefs()` |
| [`routers/publish.py`](../routers/publish.py) | publish 路由解析 6 个 multipart 字段，落库 `replay_prefs_json` |
| [`routers/viewer.py`](../routers/viewer.py) | `/sreplay/{...}` 渲染时读 `replay_prefs_json`，按 `bgmId` 计算 `audio_url`，把整套 prefs 注入 `window.__REPLAY_PREFS__`；新路由 `GET /assets/replay-audio/{bgmId}.mp3`（白名单 + path-traversal 双重过滤） |
| [`static/replay-audio/*.mp3`](../static/replay-audio/) | 5 个 BGM 文件，文件名严格等于 `bgmId` 的 wire 值 |
| [`static/viewer_replay.html`](../static/viewer_replay.html) | 内置 STYLE_KITS / FILTERS 表，写到 `:root` 的 CSS 变量驱动整页配色；filter 用 `.photo-frame::after` overlay + `img { opacity, filter }` 三件组合实现；transition 用 `@keyframes card-{in,out}-{fade,slide,scale}` 6 条配 `data-anim` 触发；blurOverlay 切 `--ov-blur` 0/14px；routeAnimation 把单条 polyline 拆成 pending（虚线灰底）+ visited（实线主色）双层，MOVING 阶段末尾延伸 visited |
| [`tests/test_publish_replay_prefs.py`](../tests/test_publish_replay_prefs.py) | 11 个新测试覆盖 normalize / publish / viewer 注入 / audio 路由 / path traversal |

### 测试

```
102 passed in 4.39s
```

（v0.9.4 是 91；新增 11 个全部针对 v1.0）

### 兼容老 v0.9 链接

老 publish 出去的 HTML 里硬编码 `/assets/replay-audio.mp3`，`replay_audio_legacy` 路由保留。新发布的 viewer_replay 都走 v1.0 的 `/{bgmId}.mp3`。DB 老行的 `replay_prefs_json` 是 NULL，viewer 注入 `window.__REPLAY_PREFS__ = null`，前端走 PREFS_DEFAULT。

### 仍依赖前端

`SharePublishNode` 之外，新增可选 `ReplayPrefsForShare`，由 `SharePage` 在 publish 前调用 `ReplayPreferences.getState()` 读出当前 AppStorage 设置，传到 `ShareService.publish()`。下面的迭代 v1.0-frontend 跟进。

---

## 2026-05-08 · 迭代 v0.9.3 · 回放 viewer 两处 bug 修复

### 1. 节点照片去重正则没兼容 v0.4 新文件名 → 1 张照片显示成 2 张

**根因**：`viewer_replay.html` 的 `collectNodePhotoUrls()` 用旧正则 `/(\d+)_(\d+)_(\d+)w\.webp$/` 匹配节点照片 url，去重 key 是 `nodeOrder_photoIdx`。但 v0.4 起后端文件名改成了 `{flatIdx}_{w}w.webp`（只有 2 段数字），新正则匹配不上 → 落到 `byKey.set(p.url, p.url)` 兜底分支 → 同一张图的 375w 和 750w URL 不同被当成两条独立 entry → 1 张原图渲染成 2 张照片 + 多一个 dot。

**修复**：正则改成 `/(\d+(?:_\d+)?)_(\d+)w\.webp$/`，第一个捕获组兼容 `0`（新格式）和 `0_0`（旧格式），都用作 photoIdx 去重 key。已验证：
- `0_375w.webp` + `0_750w.webp` → 1 个 photoIdx ✓
- `0_0_375w.webp` + `0_0_750w.webp` → 1 个 photoIdx（向后兼容） ✓

### 2. ⏮ ⏭ 按钮误把回放暂停 → 改成保留 play/pause 状态

**根因**：`jumpTo(idx)` 无脑调 `pause()`，意味着用户播放中点 ⏭ 想看下一段会被打断要再点 ▶。

**修复**：jumpTo 记下 `wasPlaying = State.isPlaying`：
- 之前在播 → 清掉旧节点的 phase 计时器，但**不**翻 isPlaying / 不暂停音乐；新节点 instant focus 后从 FADE_IN 阶段重启状态机
- 之前暂停 → 只刷新到新节点的卡片，保持暂停

slider 拖动也走同一路径，正确响应。同时把"延迟 50ms 启动 enterPhase / showCard" 的 setTimeout 存回 `State.phaseTimer`，下一次 jumpTo（slider 频繁 oninput）能 clearTimeout 取消，不堆叠。

### 改动文件

只 [`static/viewer_replay.html`](../static/viewer_replay.html)。无后端逻辑 / DB / 测试改动，91/91 测试照常通过。

---

## 2026-05-08 · 迭代 v0.9.2 · 把"路线回放"嵌进默认分享页

### 背景

v0.9 加了 `/sreplay/{...}` 独立回放页，但前端实际生成的分享链接仍然是 `/s/{...}?t=&s=`（publish viewer），没有任何指向回放的入口。接收方只能看到静态图文，看不到回放体验。

### 改动

publish viewer (`viewer_publish.html`) 顶部 trip 信息下方加一个紫色 CTA 按钮 "▶ 路线回放（动态地图 + 节点逐个展示）"。

点击按钮 → 全屏 iframe overlay 弹出，src 指向同 `shortCode + sig + expiry` 的 `/sreplay/...` URL；右上角 × 按钮（或 Esc 键）关闭 overlay 并把 iframe `src` 设回 `about:blank`，停掉里面的音频和地图渲染。

iframe 的 `src` **延迟加载** —— HTML 初始 `src="about:blank"`，真实 URL 放在 `data-replay-url` 属性，用户点了按钮才注入 `iframe.src`。这样：
- 用户没点 → 不发请求，省 Leaflet JS / 瓦片 / 音频文件流量（~3.7MB 音乐就是大头）
- 用户关闭 → 立刻停止后台运行（避免在另一个 tab 后台空跑）

### 节点没有坐标 → 按钮不出现

`render()` 里检查 `nodes.some(n => typeof n.latitude === 'number' && typeof n.longitude === 'number')`，没坐标就不创建 trigger 按钮。这样一条没有坐标的 trip 不会出现一个点了就报错的按钮。

### 改动文件

| 文件 | 改动 |
|---|---|
| [`static/viewer_publish.html`](../static/viewer_publish.html) | 新增 `.replay-trigger` / `.replay-overlay` / `.replay-iframe` / `.replay-close` CSS；body 里加 iframe overlay；render() 顶部插入 `<button id="replay-trigger">`；新增 `wireReplayOverlay()` 处理点击 / 关闭 / Esc / 延迟加载 |
| [`routers/viewer.py`](../routers/viewer.py) | publish viewer 渲染时新增 `replay_url` 计算 + `{{REPLAY_URL}}` 占位符替换 |
| [`tests/test_publish_api.py`](../tests/test_publish_api.py) | 新测试：publish HTML 里 iframe 的 `data-replay-url` 指向同 shortCode 的 `/sreplay/...` URL |

### 测试

```
91 passed in 4.10s
```
（v0.9.1 是 90；新增 1 个）

### 仍依赖前端

`/sreplay/...` 真正能放出有效内容，需要 publish 时**节点带 lat/lng**。前端的 `SharePublishNode` 类型已经支持 `latitude?` / `longitude?` 可选字段，只需要 `SharePage.buildRequestFromRdb()` 把 `MemoryNode.latitude/longitude` 写进去即可（参见 frontend 接入说明 v0.7）。

---

## 2026-05-08 · 迭代 v0.9.1 · 节点正文长文本"展开/收起"按钮

### 目的

issue：节点 content（正文）很长时占据卡片大量空间，几个长 node 把页面拉得很长。需要默认折叠到前几行，长正文旁出"展开"按钮。

### 改动

5 个 viewer 都加：默认 4 行 line-clamp（replay modal 是 6 行），溢出时才显示按钮，点击切换"展开 / 收起"。

| 文件 | 范围 |
|---|---|
| [`static/viewer.html`](../static/viewer.html) | 节点卡 `.content` |
| [`static/viewer_publish.html`](../static/viewer_publish.html) | 节点卡 `.content` |
| [`static/viewer_3d.html`](../static/viewer_3d.html) | 节点卡 `.content` （Vue template 包了 `.content-block` div + 按钮，渲染后 `nextTick` 扫一遍） |
| [`static/viewer_map.html`](../static/viewer_map.html) | 右侧节点列表 `.item .content`（按钮 click `@click.stop` 防止点开按钮触发地图 flyTo） |
| [`static/viewer_replay.html`](../static/viewer_replay.html) | 半模态 `.modal .note`，6 行（模态本身就是为看全文而开的，给得宽松点） |

### 实现一致性

每个文件都用同一个小模式：

```html
<div class="content-block">
  <p class="content">{{ 用户文本 }}</p>
  <button class="toggle-content hidden" type="button">展开</button>
</div>
```

```css
.content {
  display: -webkit-box;
  -webkit-line-clamp: 4;          /* replay modal 用 6 */
  -webkit-box-orient: vertical;
  overflow: hidden;
  white-space: pre-wrap;          /* 保留原有 pre-wrap */
}
.content.expanded { -webkit-line-clamp: unset; display: block; }
.toggle-content.hidden { display: none; }
```

```js
// 渲染 / nextTick 之后跑一遍：scrollHeight > clientHeight 才显示按钮
requestAnimationFrame(() => {
  if (content.scrollHeight > content.clientHeight + 1) {
    btn.classList.remove("hidden");
  }
});
btn.onclick = () => {
  const isExp = content.classList.toggle("expanded");
  btn.textContent = isExp ? "收起" : "展开";
};
```

### 测试

90/90 通过（无新增逻辑测试 — CSS / DOM 行为靠真机视觉验收）。所有 5 个 viewer 路由对一个含 1 个长正文 + 1 个短正文的 trip 都返 200，按钮 HTML 都注入。

### 验收点

打开同一个 trip 的 5 种 viewer：
- 长正文节点旁应出现 "展开" 按钮，点击后展开全文，按钮文案变 "收起"
- 短正文节点旁**不应**出现按钮（隐藏到位）
- replay viewer 点照片卡 → 半模态打开 → 长 note 显示前 6 行 + "展开"

---

## 2026-05-08 · 迭代 v0.9 · 路线回放 viewer (Plan A)

### 目的

把 frontend `TripReplayPage.ets`（map-travel/pages/）的回放体验复刻进 H5 viewer，让分享链接的接收方也能看到"地图相机沿路线穿梭 + 节点照片渐显 + 背景音乐"的动态回放。对齐文档 §8 的 Phase 2 要求。

产品决策按"完全对齐前端"原则：
- 5 阶段时序常量与 TripReplayPage 一致：`FADE_IN 2s → STAYING 3s → FADE_OUT 1s → MOVING 1.5s`
- 倍速 0.5x / 1x / 2x（三档循环按钮）
- 倍速**只影响动画**，音频不跟随（与 TripReplayPage 同步保留 SDK 层限制）
- 默认开始就播放音乐 + 循环；右上角 ♪ 切换静音
- 使用同一首背景乐：`South-East-Traveling.mp3`（从 frontend rawfile 拷过来）
- 节点 marker 红色水滴形、路线虚线、点 marker 不响应（与 TripReplayPage 一致）
- 卡片紧贴屏幕中线偏上、点卡片展开为 65vh 半模态、模态里能横向滚 swiper 看大图 + 全文 note + 时间戳
- 进度条离散滑块（每节点一档），拖动跳转即暂停 + 显示该节点卡

### 与 TripReplayPage 的差异

| 项 | TripReplayPage | viewer_replay (v0.9) |
|---|---|---|
| 地图引擎 | Huawei MapKit | Leaflet（CARTO Dark） |
| 相机 3D | bearing + tilt 45° 跟随 | 纯俯视（Leaflet 不支持 tilt；要 3D 得 Plan B 上 MapLibre GL） |
| "行人 icon 沿 polyline 走" | 有 | 无（实现复杂收益不高） |
| 进度条样式 | ArkUI Slider | 原生 `<input type=range>` 用 CSS 美化 |
| 上一/下一节点 | ✅ | ✅（⏮ ⏭ 按钮） |
| 节点照片 swiper | 手动滑（卡内）+ 模态自动 3s | 手动左右箭头（卡内）+ 模态横向滚动 |

### 接口扩展

新端点 `GET /sreplay/{shortcode}?t=&s=`（与 publish viewer 同样的 sig 校验链路）。

新静态资源 `GET /assets/replay-audio.mp3`，长缓存（`max-age=31536000, immutable`）。

`PublishOk` 响应里**不变**，但 `_build_route_data()` 渲染的 `ShareRouteData.nodes[]` 现在多 3 个字段（Phase 2 schema）：
- `latitude` (number | null)
- `longitude` (number | null)
- `visitedAt` (number | null)

旧的 `/s/{shortcode}?t=&s=` (publish viewer) 也会在 `__ROUTE_DATA__` 里看到这三个字段，下游使用方按需消费。没坐标的节点为 `null`。

### 改动文件

| 文件 | 改动 |
|---|---|
| [`routers/viewer.py`](../routers/viewer.py) | 抽出 `_validate_and_fetch_share` + `_build_route_data` 给两个 viewer 共用；新增 `viewer_replay` 路由 + `replay_audio` 路由；route_data 加 lat/lng/visitedAt |
| [`static/viewer_replay.html`](../static/viewer_replay.html) | **新增** 580 行：Leaflet + 5 阶段状态机 + 照片卡 + 半模态展开 + 进度条 + 倍速 + 音频 + 微信兼容 hook |
| [`static/replay-audio.mp3`](../static/replay-audio.mp3) | **新增** 3.7MB，从 frontend `rawfile/South-East-Traveling.mp3` 拷过来 |
| [`tests/test_publish_api.py`](../tests/test_publish_api.py) | 5 个新测试：replay HTML 渲染 / audio URL 注入 / 错误 sig 403 / 音频强缓存头 / publish viewer 也能读到 lat/lng |

### 测试

```
90 passed in 4.01s
```
（v0.8.1 是 85；新增 5 个）

### 隧道实测样本

```
trip "敦煌 7 日 · 路线回放 demo" 4 个节点
  shortCode = c7S07yUM
  /sreplay/c7S07yUM?t=...&s=... → 200, 31KB HTML
  /assets/replay-audio.mp3       → 200, 3.7MB, max-age=31536000 immutable
```

可在浏览器打开看回放效果（手机端体验最佳，地图占满全屏）。

### 已知限制

1. **Leaflet 没有 3D bearing/tilt**：相机始终俯视，少了原生 TripReplayPage 的"第一人称穿梭"沉浸感。要 3D 需要切 MapLibre GL（Plan B）
2. **音频 autoplay 政策**：iOS Safari / 微信内置浏览器可能拒绝自动播放，用户需要手动点 ▶。已有 `WeixinJSBridgeReady` hook 兜底，但不保证 100% 工作
3. **倍速不影响音乐**：与 TripReplayPage 一致，AVPlayer / HTMLAudioElement 都没有干净的"实时变速"API（HTMLAudioElement 的 `playbackRate` 会变调）
4. **没有"行人 icon 沿 polyline 走"动画**：实现复杂、收益小，视觉上 `flyTo` 已经足够表达"路线移动"
5. **进度条拖动跳转后**：当前行为是"暂停 + 显示该节点卡"。用户再点 ▶ 才继续 —— 与 TripReplayPage 一致

---

## 2026-05-08 · 迭代 v0.8.1 · 4 个 viewer 长文本自适应防溢出

### 背景

用户反馈：节点 title / content / 简介里的文字过长时，分享网页排版会出问题——具体表现是 viewport 被撑宽，整页缩放比例与屏幕不匹配（mobile 上看起来"挤进去一小块"）。

根因：4 个 viewer（simple / 3D / map / publish）的 CSS 都**没**对长不可断字符串（英文 URL / 长 hashtag / 连续标点）做防御。CSS 默认 `overflow-wrap: normal`，遇到这种串只会延伸到容器外，把父容器撑破。

### 改的事

每个 viewer 的 `<style>` 顶部加一段统一的"防溢出"块（仅 simple 把 `overflow-x:hidden` 加在 html/body 上，3D 已有不重复加）：

```css
html, body { overflow-x: hidden; max-width: 100%; }
body, h1, h2, h3, p, span, article {
  overflow-wrap: anywhere;
  word-break: break-word;
}
img { max-width: 100%; }
main, .meta, .tags, .photos { min-width: 0; }
```

`overflow-wrap: anywhere` 比 `break-word` 更强 —— 真的可以在任意字符位置断。两个一起用是兼容老浏览器（虽然项目目标设备都不老）。

### 各 viewer 的额外修补

| 文件 | 额外改动 |
|---|---|
| [`viewer.html`](../static/viewer.html) | 仅加防御块 |
| [`viewer_3d.html`](../static/viewer_3d.html) | 已有 body `overflow-x: hidden`，仅加 wrapping 规则 + `.hero-content min-width: 0` |
| [`viewer_map.html`](../static/viewer_map.html) | `.item` 的 grid 模板从 `32px 1fr` 改成 `32px minmax(0, 1fr)` —— 普通 `1fr` 默认 `min-width: auto`，遇到长 content 会撑爆，`minmax(0, 1fr)` 才允许收缩 |
| [`viewer_publish.html`](../static/viewer_publish.html) | `.summary .pill { min-width: 0; max-width: 100%; }` —— 头部 pill 行用 flex+wrap，长描述能正确换行 |

### 测试

```
85 passed in 3.74s
```
（无新增测试 —— CSS 改动靠真机视觉验收。但所有 4 个 viewer 路由仍返 200。）

### 隧道实测路径

构造一个 stress trip（tripName / content / poiName / tag 全是 ≥80 字符的不可断长串，混合中英文），4 个 viewer 都返 200。具体 URL：

```
trip_long_overflow → Od0xZpjr
  spec   /s/Od0xZpjr?t=...&s=...
  simple /s/Od0xZpjr.<sig>
  3D     /s3d/Od0xZpjr.<sig>
  map    /smap/Od0xZpjr.<sig>
```

视觉验收点：
- 长串 trip name 在 hero 标题区**自动换行**，不撑出屏幕
- 长 content 文字在卡片内**断行**，卡片宽度 = main 容器宽度
- map viewer 的节点列表项里，长 title 在第二列内**收缩换行**，不让 32px 数字 + 1fr 列加起来超过容器
- 任何 viewer 的 viewport 都不会因为内容横向撑破

---

## 2026-05-06 · 迭代 v0.8 · Trip 改私密自动关停其全部分享

### 目的

产品需求 issue：用户把某条 trip 从公开切到私密后，该 trip 之前发出去的全部分享链接应**立刻**失效，访问者看到的页面文案是 "该用户已设置该路线为私密"（与"自然过期"的 "此链接已过期" 区分开）。

### 接口扩展（向后兼容）

新端点 **`POST /api/v1/share/revoke-by-trip`**

请求 body：
```json
{ "tripId": "trip_abc123" }
```

响应：
```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "tripId": "trip_abc123",
    "revokedCount": 2
  }
}
```

`revokedCount` = 实际被这一次撤销翻成 PRIVATE 的活跃分享条数。已经 revoked / 已自然过期的不重复计数；trip 没分享时是 0；这两种情况都不算错误。

### 数据状态

`share_publish` 表加 `revoked_reason TEXT` 列：
- `NULL` — 活跃，或自然过期（lazy delete 时整行删掉，不会留 NULL 行表示过期）
- `'PRIVATE'` — owner 改私密时被本端点撤销

数据状态机：
```
publish    →  revoked_reason = NULL, cache 文件齐全
private    →  revoked_reason = 'PRIVATE', cache 子目录被 rmtree
expire     →  整行被 lazy_delete / cron 删掉
```

### 三个访问端点的新行为

| 路由 | 看到 revoked_reason='PRIVATE' 时 |
|---|---|
| `/s/{code}?t=&s=` | 410 + 页面文案 "该用户已设置该路线为私密" |
| `/api/v1/share/{code}/status` | `code: 40402, message: REVOKED_BY_OWNER_PRIVATE` |
| `/cache/{code}/*.webp` | 404（且文件其实已经被 rmtree） |

新错误码 **40402 REVOKED_BY_OWNER_PRIVATE**（spec §4.5 错误码表的扩展）。

### 改动文件

| 文件 | 改动 |
|---|---|
| [`db/schema_publish.sql`](../db/schema_publish.sql) | 加 `revoked_reason TEXT` 列 + `idx_share_publish_trip` 索引 |
| [`db/repository_publish.py`](../db/repository_publish.py) | `_ensure_schema()` 加 idempotent `ALTER TABLE` migration（已有 DB 也能升级）；新增 `mark_revoked_by_trip(trip_id, reason) -> list[str]` |
| [`core/lifecycle.py`](../core/lifecycle.py) | 新增 `REVOKE_REASON_PRIVATE` 常量 + `revoke_shares_by_trip(trip_id, reason)` |
| [`models/publish.py`](../models/publish.py) | `RevokeByTripRequest` / `RevokeByTripResponse` |
| [`routers/publish.py`](../routers/publish.py) | 新增 `POST /api/v1/share/revoke-by-trip`；`status_endpoint` 返 40402；`cache_serve` 在 revoked_reason 非空时拒服 |
| [`routers/viewer.py`](../routers/viewer.py) | `_ERR_PRIVATE` 文案；publish viewer 在 expiry 检查**前**先识别 `revoked_reason='PRIVATE'` |
| [`tests/test_publish_api.py`](../tests/test_publish_api.py) | 6 个新测试 |

### 设计决策

- **DB 行保留 + cache 立即删**：保留行让 viewer 能给出 "该用户已设置该路线为私密" 这种明确文案；cache 删掉确保数据真的不可读。DB 行靠 cron 在自然到期时清掉
- **公开→私密→公开 不复活**：被撤销的分享行**不会**因为 owner 又改回公开就重新激活（cache 已删，URL 也没意义。用户得重新点 publish）
- **MVP 不做 auth**：调用方持有 tripId 就能关停。tripId 是本地 UUID 不外泄，风险可接受。AGC Auth 接入后会再加 `ownerUid` 校验

### 测试

```
85 passed in 3.82s
```
（v0.7.1 是 79；新增 6 个：撤销标记 / viewer 文案 / status 40402 / cache 拒服 / 不存在 trip 不算错误 / 幂等）

### 隧道实测

```
1. publish trip_id=trip_smoke_priv → shortCode=XNpD9xNU, viewer 200
2. POST /api/v1/share/revoke-by-trip {tripId:trip_smoke_priv}
       → {revokedCount: 1}
3. viewer → 410 + <h1>该用户已设置该路线为私密</h1>
4. status → {code:40402, message:REVOKED_BY_OWNER_PRIVATE}
5. ls cache/XNpD9xNU/ → No such file or directory
```

### 已知限制

- 没接 auth：tripId 知情者都能撤销
- 多设备同步：A 设备改了私密 → 后端关停了所有分享，但 A 设备 RDB 里的"已发出去的链接列表"（如果有）不会自动刷新。当前没有这种 UI，不影响

---

## 2026-05-05 · 迭代 v0.7.1 · `coverPhotoUrl` 进 publish 响应（QQ 卡片支持）

### 目的

v0.7 加了 OG meta，**微信**接收方会自己 fetch URL 抓 meta 渲染卡片所以工作正常；但 **QQ** 不会主动抓 OG —— 它需要分享方在 SharedData 里直接给 `thumbnail: Uint8Array` 才能渲染卡片预览。

要让前端能传 thumbnail，需要后端先把"封面图的公网 URL"surface 到 publish 响应里，前端才能去 fetch 它。

### 改动

| 文件 | 改动 |
|---|---|
| [`models/publish.py`](../models/publish.py) | `PublishOk` 加 `coverPhotoUrl: Optional[str] = None` |
| [`routers/publish.py`](../routers/publish.py) | 响应组装时根据 `cover_relpath` 生成 `<base>/cache/{shortCode}/{cover_relpath}` URL；无照片时为 None |
| [`tests/conftest.py`](../tests/conftest.py) | 加 autouse fixture 重置 `_PUBLISH_WINDOW` + `_ip_window`，避免测试套累积请求超 30 次/小时撞限流 |
| [`tests/test_publish_api.py`](../tests/test_publish_api.py) | 2 个新测试：有照片时 coverPhotoUrl 非空指向 `/cache/.webp`；0 照片时为 null |

### 测试

```
79 passed in 3.15s
```
（v0.7 是 77；新增 2 个 cover 测试）

### 隧道实测

```json
{
  "code": 0,
  "data": {
    "url":           "https://.../s/k7OlDyDS?t=...&s=...",
    "shortCode":     "k7OlDyDS",
    "expiresAt":     1778003577,
    "sig":           "3fb319a4...",
    "coverPhotoUrl": "https://.../cache/k7OlDyDS/0_375w.webp"
  }
}
```

前端 v0.5.2 同步把它 fetch 成 Uint8Array 塞进 SharedData.thumbnail。

---

## 2026-05-05 · 迭代 v0.7 · OG / social meta 标签 + 第一屏 SSR fallback

### 目的

按对齐版文档 §4.5 / §5.8 / §7.2 的"模块三验收必须项"做的事。前端这边 v0.5（SystemShareService）会调起系统分享面板把 URL 投给 QQ / 微信 / 微博；接收方应用收到后**自己抓 URL 的 head**生成卡片预览。所以这一轮后端必须在 H5 viewer 的 `<head>` 把社交平台想要的所有元信息备齐。

### 加的标签

| 标签 | 用途 |
|---|---|
| `<title>` + `<meta name=description>` | 浏览器 tab 标题 + 搜索引擎摘要 |
| `og:type` / `og:title` / `og:description` / `og:url` / `og:image` / `og:site_name` / `og:locale` | Open Graph，QQ / 微信 / 微博 / Slack 等都吃 |
| `twitter:card` / `twitter:title` / `twitter:description` / `twitter:image` | Twitter 卡片协议 |
| `wxcard:title` / `wxcard:description` / `wxcard:image` | 微信 JS-SDK 二次分享配置位（坑位先留，本期没接 SDK） |

`og:image` 直接指向 `<base>/cache/{shortCode}/{coverRelpath}`（即首张照片的 375w 转码版）。在链接活着期间公网可访问。链接过期后 `/cache` 路由会 404，但接收方应用通常已经把图缓存了。

### 第一屏 SSR fallback

对纯 SPA 不友好的爬虫：在 `<body>` 起头加了一段服务端渲染的标题 + 摘要 HTML，包在自定义标签 `<noscript-or-precrawl>` 里。JS 启动后整个 `#app` innerHTML 被替换成 SPA，fallback 自然消失。

### 改动文件

| 文件 | 改动 |
|---|---|
| [`static/viewer_publish.html`](../static/viewer_publish.html) | head 加 14 个 meta 标签（带 4 个新占位符 `{{HTML_TITLE}}` / `{{SHARE_DESCRIPTION}}` / `{{COVER_PHOTO_URL}}` / `{{SHARE_URL}}`）；body 加 SSR fallback；删了开头注释里的字面 `{{ROUTE_DATA_JSON}}`（之前会被一并替换进去复制一份 JSON） |
| [`routers/viewer.py`](../routers/viewer.py) | `_render_publish_viewer` 注入 4 个新占位符值；新增 `_build_share_description()` 生成 100 字以内紧凑摘要；所有占位符值都 `html.escape(quote=True)` 防 XSS |
| [`tests/test_publish_api.py`](../tests/test_publish_api.py) | 4 个新测试：OG/Twitter/wxcard meta 完整存在 / 第一屏 SSR fallback 含 tripName / tripName 含 `</script>` 等危险字符正确转义 / 0 照片时占位符仍正确替换 |

### 测试

```
77 passed in 2.97s
```
（v0.6 是 73；新增 4 个 OG meta 测试）

### 隧道实测

```bash
$ curl -s "<URL>/s/fvHarKGY?t=...&s=..." | grep -E 'og:|twitter:|wxcard:|<title>'
<title>v0.4 存储规范化烟测 - TravelPin</title>
<meta property="og:title"       content="v0.4 存储规范化烟测 - TravelPin">
<meta property="og:description" content="2 个节点 · 8.0km · 始于PoiA · TravelPin 分享">
<meta property="og:url"         content="https://.../s/fvHarKGY?t=...&amp;s=...">
<meta property="og:image"       content="https://.../cache/fvHarKGY/0_375w.webp">
... (twitter:* / wxcard:* 同步) ...
```

### 仓库版本控制

本目录从 v0.6.1 起接入本地 git（`/data2/cse12310817/backend/share_service/.git`）。
- `89e22ab v0.6.1 baseline` — 截至 v0.6 全部历史的快照
- `fcb0efd feat(viewer): v0.7 加 OG/social meta + 第一屏 server-rendered fallback`

`.gitignore` 排除了 `.env / *.db / cache/ / run/ / .venv/`。

### 仍未做（已知限制）

- **微信 JS-SDK** 没接 —— 只留了 wxcard:* 元数据坑位。要做 JS-SDK 还要服务端配 `signature`+`nonceStr`+`timestamp` 端点，需要微信公众号或小程序的 appId。这次范围之外
- **og:image 在链接过期后仍可被微信缓存沿用** —— 这是社交平台的既有行为，不是 bug。攻击面有限（图片本身已 EXIF 清洗）

---

## 2026-05-05 · 迭代 v0.6 · publish 替换语义（防止冗余链接堆积）

### 背景

v0.5 之后用户可以在前端切换 4 档过期时长。但每次切换都会调一次 publish，**旧链接还活着**直到自然过期——如果用户在 SharePage 里反复切档，会留下一串"用户实际不要"的活链接，浪费磁盘 + 给恶意 / 误操作留刷量空间。

前端建议方案 A："切档时自动撤销旧链接"。本迭代后端配合实现。

### 接口扩展（向后兼容）

`POST /api/v1/share/publish` multipart 增加 3 个**配套**可选字段（要么三个都不传，要么三个都传）：

| 字段 | 类型 | 说明 |
|---|---|---|
| `replaceShortCode` | text | 要随本次发布**自动撤销**的旧 shortCode |
| `replaceExpiry`    | text | 那条旧 link 的 `expiresAt`（秒） |
| `replaceSig`       | text | 那条旧 link 的 `sig`（hex64） |

后端用 `verify_sig_v2` 校验 `HMAC(replaceShortCode + ":" + replaceExpiry, KEY) == replaceSig`，**只有持有那条 URL 的人**能撤销它（防止第三方投毒撤销别人的分享）。校验失败 → `40006 INVALID_JSON`。

响应 `PublishOk` 加 `sig: str` 字段（与 url 中 `&s=` 之后一致），方便前端下次切档时把它直接回填到 `replaceSig`，不用再解析 URL。

### 原子性

撤销发生在**新 publish 成功之后**：

```
new transcode → new manifest.json → new DB insert ←┐ 任何一步失败：
                                                    │ shutil.rmtree 新 cache 子目录
                                                    │ 旧链接保持原样
                                                    └─ 返回 500
                       ↓ 新成功
   delete_share(replaceShortCode)  ← 这一步即使失败也不影响新链接对外可见
                       ↓
                   返回 201
```

旧码根本不存在 / 已被 lazy delete / 永远不存在 → `delete_share` 返 False，**不当作错误**（log 一条 info 即可），新链接照常返回。

### 改动文件

| 文件 | 改动 |
|---|---|
| [`models/publish.py`](../models/publish.py) | `PublishOk` 加 `sig: str` |
| [`routers/publish.py`](../routers/publish.py) | 解析 + 校验 replace 三件套；新发布成功后调 `delete_share`；响应注入 `sig` |
| [`tests/test_publish_api.py`](../tests/test_publish_api.py) | 6 个新测试：happy path / bad sig / 缺少配套字段 / 旧码已经不在 / 新失败时旧保留 / 响应包含 sig |

### 测试

```
73 passed in 2.88s
```
（v0.5 是 67；新增 6 个）

### 隧道实测

```
1. POST /publish expiryHours=168            → AlmoofXF (sig 5e83…)
2. POST /publish expiryMinutes=5
       + replaceShortCode=AlmoofXF
       + replaceExpiry=...  + replaceSig=5e83…  → HCpa0Ejg, 旧的立刻消失
3. GET /s/AlmoofXF?t=...&s=5e83…             → 404
   ls cache/AlmoofXF/                        → No such file
4. GET /api/v1/share/HCpa0Ejg/status         → alive, 300s
5. POST /publish replaceSig=deadbeef…        → 40006 INVALID_JSON
   GET /api/v1/share/HCpa0Ejg/status         → 仍然 alive, 未受影响
```

### 已知限制

- 替换流程需要**两次** transcode（新这一条照常转码 → 旧的删 webp）。如果切档很频繁、照片量大，仍有性能开销。下一步可加"延长不重传"端点（`POST /api/v1/share/{code}/extend?expiryHours=...`）专门处理"同一份内容、只想换有效期"的场景，但需要再加一组契约
- 没有用户身份的话只能靠"持有 sig 才能撤销"做防御。等接 AGC Auth 后可以加"only owner can revoke"双重检查

---

## 2026-05-04 · 迭代 v0.5 · 链接生命周期（用户可选 + lazy delete + cron）

### 目的

前端要给用户提供"5 分钟 / 1 天 / 7 天 / 30 天"四档过期时长选择（5 分钟档为联调 / 测试便利）；后端配合实现真正的生命周期回收（lazy delete on access + cron purge of `share_publish` + cache subdirs）。前端文档：`team-project-26spring-26s-7/references/documents/social-share/前端接入实现说明.md` 同迭代。

### 接口扩展（向后兼容）

`POST /api/v1/share/publish` multipart 增加可选字段 **`expiryMinutes`**：

| 字段 | 是否必填 | 范围 | 说明 |
|---|---|---|---|
| `expiryHours` | 否（旧字段保留） | 1–720 | 整数小时，规范 v1 原始字段 |
| `expiryMinutes` | 否（新增） | 1–43200 | 整数分钟，**优先级高于 expiryHours** |

两个都不传 → 默认 168 小时（7 天）。

后端实际下限改为 **60 秒**（之前是 1 小时）—— 直接放宽给前端 5 分钟选项用。`MIN_EXPIRY_SECONDS=60 / MAX_EXPIRY_SECONDS=720*3600` 在 [`routers/publish.py`](../routers/publish.py)。

### 生命周期回收

| 触发 | 行为 | 谁触发 |
|---|---|---|
| **Lazy delete on access** | 任意一个 `/s/{code}?t=&s=` / `/api/v1/share/{code}/status` / `/cache/{code}/{file}` 路由检测到 `expires_at_s <= now` → 立即 `delete_share(code)`：删 DB 行 + `shutil.rmtree` cache 子目录 → 返回对应错误（410/40401/404） | 任何访问者 |
| **Cron purge** | `python -m share_service.scripts.purge_expired` 每天调一次 → `purge_expired_now(now_s)` 把所有过期行删完 + 删它们的 cache 子目录。同时仍清扫旧 `share_link` 表 | crontab |

### 新增文件

| 文件 | 作用 |
|---|---|
| [`core/lifecycle.py`](../core/lifecycle.py) | `delete_share(code)` 单个清理 + `purge_expired_now(now_s)` 批量清理。无路由层依赖，可直接在测试 / 脚本中调 |

### 改动文件

| 文件 | 改动 |
|---|---|
| [`routers/publish.py`](../routers/publish.py) | 新增 `expiryMinutes` 解析（优先于 `expiryHours`）；下限放宽到 60s；`status_endpoint` + `cache_serve` 两个端点遇到过期行时调 `delete_share` |
| [`routers/viewer.py`](../routers/viewer.py) | publish viewer 的 410 分支调 `delete_share` |
| [`db/repository_publish.py`](../db/repository_publish.py) | 新增 `delete_publish(code) -> bool`，配 lazy delete 用 |
| [`scripts/purge_expired.py`](../scripts/purge_expired.py) | 重写：先调 `purge_expired_now()` 处理 share_publish + cache 目录，再调旧 `purge_old()` 处理 legacy share_link |
| [`tests/test_publish_api.py`](../tests/test_publish_api.py) | 新增 7 个测试覆盖 expiryMinutes / minutes 优先 / 0 分钟 → 40007 / 三个端点的 lazy delete / cron 批量清理 |

### 测试

```
67 passed in 2.38s
```
（v0.4 是 60；新增 7 个：3 个 expiryMinutes 行为 + 3 个 lazy delete 路径 + 1 个 cron 批量）

### 联调验证（5 分钟档实测）

```
12:08  publish with expiryMinutes=2 → mKllAdqy, TTL=120s
12:08  GET /s/...   → 200 (HTML rendered)
12:08  GET /cache/.../0_375w.webp → 200 (image/webp)
12:10  (sleep 125s)
12:10  GET /s/... → 410, lazy delete triggered
12:10  ls cache/mKllAdqy/ → No such file or directory
12:10  GET /api/v1/share/mKllAdqy/status → {"code":40401, ...}
12:10  GET /s/... again → 404 (row gone now)
12:10  POST /publish expiryMinutes=0 → {"code":40007, "detail":"expiry must be in [60s, 2592000s]; got 0s"}
```

### crontab 部署示例

```cron
# 每天凌晨 3 点清扫过期分享 + 旧 demo 表
0 3 * * * cd /data2/cse12310817/backend && \
  /data2/cse12310817/backend/.venv/bin/python -m share_service.scripts.purge_expired \
  >> /data2/cse12310817/backend/share_service/run/purge.log 2>&1
```

注：lazy delete 已经覆盖了"被访问的过期链接"，cron 只是兜底——清掉那些到期后**没人再访问**的链接（这部分本来会无限累积）。

### 已知限制

- 5 分钟档对**网络丢包敏感**：multipart 上传 + 转码用 5 秒，留给真实查看时间只剩 4 分多钟。下次让前端给个"链接快到期了，要不要续？"提示
- 前端 `cachedReq + cachedPhotos` 缓存机制让"换档重发"快了一些，但每次还是要把照片重新走 multipart 上传 → 后端重新转码。理论上能加一个 `/api/v1/share/{code}/extend?expiryHours=...` 端点来"延长不重传"，但要重新签名 + 重新约定 contract，这次不做
- 进程被 kill -9 卡在 transcode 完但 DB insert 之前的窗口里仍有可能留下孤儿目录。manifest.json 已经准备好做依据，等下个迭代加 orphan 扫描

---

## 2026-05-04 · 迭代 v0.4 · 存储规范化（事务 + 命名 + 自描述）

### 目的

v0.3 的 publish 流程对存储有几处不规范的地方，多条分享并存时风险随条目数线性放大。v0.4 把这部分搞规范，**链接生命周期管理（lazy delete + cron）暂不动，等前端同学确定 expiryHours 选项 UI 后再统一接**。

### 改的三件事

| # | 问题 | 修复 |
|---|---|---|
| A | publish 落盘 + DB 插入不是原子的：进程崩在两步之间 → 孤儿 webp | publish 内整段（transcode + write manifest + insert_publish）裹一个 try；任何一步失败 `shutil.rmtree(out_dir, ignore_errors=True)` 把整个 cache 子目录抹掉 |
| B | WebP 文件名 `{nodeOrder}_{photoIdx}_{w}w.webp`：客户端 nodeOrder 重复会互相覆盖 | 改用 `{flatIdx}_{w}w.webp`（multipart `photo_N` 的 N，单条 publish 内天然唯一）。flatIdx ↔ (nodeOrder, photoIdx) 的映射依然在 `photo_index_json` 和新 `manifest.json` 里 |
| C | cache 子目录无自描述：只能靠 DB 知道每个文件归属 | 每个 `cache/{shortCode}/` 写一个 `manifest.json`：schemaVersion / shortCode / tripId / tripName / publishedAtMs / expiresAtS / coverRelpath / photos[]（含每张图的 nodeOrder/nodeId/photoIdx/flatIdx/paths） |

`manifest.json` 不通过 `/cache` 路由对外暴露（[`routers/publish.py`](../routers/publish.py) 的 `cache_serve` 只允许 `.webp` 后缀），是纯内部调试 + 未来孤儿扫描用的。

### 改的文件

| 文件 | 改动 |
|---|---|
| [`core/photos.py`](../core/photos.py) | `process_one(raw, out_dir, flat_idx)`，`ProcessedPhoto` 字段从 `node_order/photo_idx` 改成 `flat_idx`。文件名拼接换成 `{flat_idx}_{w}w.webp` |
| [`routers/publish.py`](../routers/publish.py) | publish handler 的 transcode + manifest + DB insert 重写为单个 try/except，失败 rmtree。新增 manifest.json 落盘步骤。`import shutil` 加到顶 |
| [`tests/test_publish_api.py`](../tests/test_publish_api.py) | 旧文件名断言改成新格式；新增 4 个测试：manifest.json 写入与字段、flatIdx 文件名唯一、`/cache/.../manifest.json` 不可服、DB 插入失败后 cache 子目录被回滚 |

### 向后兼容

旧的 5 条 v0.3 分享（`PsdvNIp5` / `ArA3E7Qo` / `WKW5XjbN` / `AvnqhY1X` / `ggeLWWa3`）的 `photo_index_json` 字段里存的是 `0_0_375w.webp` 风格的旧文件名，磁盘上那些文件也是旧名字。`viewer.py` 的 `_render_publish_viewer` 直接读 `photo_index_json` 里的 path，所以**旧分享继续正常工作**，新分享走新命名。

无需任何数据迁移。

### 测试

```
60 passed in 2.16s
```
（v0.3 是 56；新增 4 个：viewer manifest 不可服 + manifest 字段 + flatIdx 文件名 + 原子回滚）

### 已知未做

- 链接生命周期：v0.3 的状态保留 —— 访问到期链接返 410/404 但 DB 行 + 文件不删；`scripts/purge_expired.py` 还没接 `share_publish` 表（只清旧 `share_link`）。等前端 expiryHours 选项 UI 接好后统一处理 lazy delete + cron。
- 孤儿扫描：进程被 kill -9 卡在 webp 已落盘但 DB insert 还没跑的窗口里仍有可能留下孤儿目录。配合 manifest.json + 未来的 cron 扫描可解决（manifest.json 自带 expiresAtS，是判断的天然依据）。

---

## 2026-04-30 · 迭代 v0.3 · 真机联调对齐

### 目的

前端进入真机联调阶段，需要后端按 [`分享系统 API 规范.md`](../../../team-project-26spring-26s-7/references/documents/social-share/分享系统 API 规范.md) v1.0 提供的契约暴露端点，能完成「上传 trip + 照片 → 拿短链 → 浏览器打开看到 H5 页」的闭环。

### 决策：共存而非替换

迭代 v0.1/v0.2 已经实现了一套以 AGC Cloud Storage key 引用为主的旧 demo 流程（`/api/share/create`、`/s/{code}.{sig}`、`/s3d/...`、`/smap/...`）；v0.3 不动这些路由，**新增**规范要求的 publish 流程，两套并存：

- **demo 流程**（旧）：JSON 上传 + 路径引用 + 客户端 fetch JSON 渲染。链接形如 `/s/{code}.{sig}`（路径含 `.`）。
- **规范流程**（新）：multipart 上传 + 后端 EXIF 清洗 + WebP 转码 + 服务端渲染 HTML。链接形如 `/s/{code}?t=&s=`（路径不含 `.`）。

`/s/{path}` 路由按是否含 `.` 在同一处理器分流，互不干扰。

### 新增端点（与规范 §3 一致）

| 方法 | 路径 | 规范条款 | 说明 |
|---|---|---|---|
| POST | `/api/v1/share/publish` | §4 | multipart 上传 trip + photo_N，返回签名 URL |
| GET  | `/s/{shortCode}?t=&s=` | §5 | 服务端渲染 H5，注入 `window.__ROUTE_DATA__` |
| GET  | `/api/v1/share/{shortCode}/status` | §6 | 状态查询 |
| GET  | `/cache/{shortCode}/{file}` | §5.2 | 静态托管转码后的 WebP |

### 新增文件

| 文件 | 作用 |
|---|---|
| [`core/photos.py`](../core/photos.py) | EXIF 清洗 + WebP 转码（375w / 750w 双倍率），符合规范 §8.1 step 5–6 |
| [`db/schema_publish.sql`](../db/schema_publish.sql) | 新表 `share_publish`，与旧 `share_link` 隔离 |
| [`db/repository_publish.py`](../db/repository_publish.py) | `share_publish` 表的 CRUD |
| [`models/publish.py`](../models/publish.py) | Pydantic 模型，对应规范 §4.2 / §4.4 / §4.5 / §6.2 |
| [`routers/publish.py`](../routers/publish.py) | publish / status / cache 三个 endpoint |
| [`static/viewer_publish.html`](../static/viewer_publish.html) | 服务端渲染 H5 模板，含 `{{ROUTE_DATA_JSON}}` 占位符 |
| [`tests/test_publish_api.py`](../tests/test_publish_api.py) | 21 个端到端测试覆盖规范全部 endpoint |

### 修改的文件

| 文件 | 改动 |
|---|---|
| [`core/security.py`](../core/security.py) | 新增 `compute_sig_v2` / `verify_sig_v2` / `generate_short_code_v2` —— 按规范 §7 用 hex64 + msg=`{code}:{exp}`（旧 base64url 截 8 字符的 demo 函数保留） |
| [`routers/viewer.py`](../routers/viewer.py) | `/s/{path}` 重构为按 `.` 分流；新增 `_render_publish_viewer` 做服务端渲染 + HMAC 校验 |
| [`main.py`](../main.py) | 注册 `publish.router` |
| [`requirements.txt`](../requirements.txt) | 新增 `Pillow>=10.0,<12.0` |

### 安全 / 合规细节

实现规范 §6 + §8 + 我自己加的几道防线：

- **EXIF 清洗**：`ImageOps.exif_transpose` 应用旋转后 `exif=b""` 落盘，确保 GPS/设备信息不暴露
- **HMAC 截断逻辑**：完整 64 字符 hex（不截断），与规范 Node.js 参考实现字节级一致（[`tests/test_publish_api.py::test_sigv2_msg_format_matches_spec`](../tests/test_publish_api.py)）
- **三段失败码区分（规范 §5.4）**：sig 不匹配 → 403、过期 → 410、shortCode 不存在 → 404
- **Path traversal 防御**（[`routers/publish.py:248`](../routers/publish.py)）：`/cache/...` 拒绝非 `.webp` 扩展名 + 拒绝路径分隔符
- **过期照片同步 404**：即使数据库行还没被清扫，`/cache/...` 读取时再次校验 `expires_at_s` 防止外链
- **限流**：`/publish` 30 次/IP/小时（规范没硬性要求；可改 [`routers/publish.py:51`](../routers/publish.py)）
- **请求体限制（规范 §4.5）**：单张 ≤ 20 MB、总体积 ≤ 100 MB、节点 ≤ 30 个

### 测试

```bash
cd /data2/cse12310817/backend
.venv/bin/python -m pytest share_service/tests/ -q
# 56 passed
```

### 已知偏离 / 与规范不严格一致的地方

| 项 | 规范说法 | 我实现 | 原因 |
|---|---|---|---|
| 错误响应 422 vs 400 | 规范 §4.5 列的是 400 + 自定义 code | publish 端按规范统一返 400+envelope，老 demo 端点用 422 | 老 demo 不在规范范围 |
| `/api/v1/share/{shortCode}/status` 的 code 值 | 规范 §6.2 写"分享有效"返 `code: 0`，无效返 `40401` | 实现一致 | — |
| `tripData.nodes[].latitude/longitude` | 规范 §4.2 表格未列、对齐版文档列了 | 后端 `PublishNode` 接受可选字段 | 兼容前端两种发法 |

### 重启 / 运维

进程脱离我会话独立跑（`PPID=1`，`setsid -f`）。

```bash
# 看状态
pgrep -af "uvicorn share_service.main:app"
pgrep -af "cloudflared.*8001"
tail -f /data2/cse12310817/backend/share_service/run/uvicorn.log

# 重启 uvicorn（改了代码 / .env 后）
kill $(pgrep -f "uvicorn share_service.main:app")
setsid -f /data2/cse12310817/backend/share_service/run/start_uvicorn.sh \
  < /dev/null > /data2/cse12310817/backend/share_service/run/uvicorn.log 2>&1

# 重启 cloudflared（注意：会换临时域名！需更新 .env 的 SHARE_PUBLIC_BASE 再重启 uvicorn）
kill $(pgrep -f "cloudflared.*8001")
setsid -f /data2/cse12310817/bin/cloudflared tunnel --url http://127.0.0.1:8001 --no-autoupdate \
  < /dev/null > /data2/cse12310817/backend/share_service/run/cloudflared.log 2>&1
```

当前生效的隧道域名：见 [`/data2/cse12310817/backend/share_service/.env`](../.env) 的 `SHARE_PUBLIC_BASE`。

---

## 2026-04-29 · 迭代 v0.2 · 多 viewer

### 目的

让 demo 链接打开后看到设计过的页面，而不是裸 JSON。

### 新增

- `static/viewer.html`（简单时间线版） + `GET /s/{code}.{sig}`
- `static/viewer_3d.html`（Vue 3 + Three.js 立体多面体 + 鼠标拖拽，自动按节点 lat/lng 在球面打 marker） + `GET /s3d/{code}.{sig}`
- `static/viewer_map.html`（Vue 3 + Leaflet + CARTO Dark 瓦片，节点按 nodeOrder 用虚线连成路线） + `GET /smap/{code}.{sig}`

三个 viewer 共用同一 demo 数据（`/api/share/{code}.{sig}` 提供 JSON）。

### 修改

- `routers/viewer.py`：3 个 viewer 路由
- `tests/test_viewer.py`：4 个新测试

---

## 2026-04-27 · 迭代 v0.1 · MVP 骨架

### 目的

按 [P08 临时分享链接后端交接文档] 的"方案 1（AGC Cloud Function + AGC Hosting）"思路落地一个本地原型，先跑通端到端，再迁 AGC。

### 实现范围

- 5 个 endpoint：create / get / mine / revoke / health
- HMAC-SHA256 签名（msg=`code|uid|exp`，base64url 截 8 字符）
- SQLite + WAL，schema 自动应用
- 跨用户对象引用防御（photoManifest key 必须以 `users/{uid}/` 开头）
- 限流（每 uid 50 创建/天，公开 GET 30/min/IP）
- pytest 31 个测试通过
- cloudflared 临时隧道接入

### 文件清单

见 [share_service/README.md](../README.md)。
