# AI 文案生成 Prompt 规则

> 适用范围：[`AiCopyPage`](frontend/entry/src/main/ets/feature/ai-copy/pages/AiCopyPage.ets) → [`AiGatewayClient.generateCopyFromImages`](frontend/entry/src/main/ets/common/api/AiGatewayClient.ets) 这条链路。
>
> 实现入口：[`AiGatewayClient.ets`](frontend/entry/src/main/ets/common/api/AiGatewayClient.ets) 里的 `buildBatchPrompt(request, exifDesc)`。

---

## 1. 设计原则

四条核心约束，迭代多版后保留下来的：

1. **结构化分段**：用 `【任务】 / 【场景信息】 / 【照片元数据】 / 【输出要求】` 把上下文和指令分块，比一大段连续中文更可靠地让 Qwen3 系列模型遵守约束。
2. **空字段不渲染**：用户没填的字段（如 mood / tags）整行不出现，避免 prompt 里出现 `心情：` 这种空 placeholder 让模型反复纠结要不要填。
3. **明确输出格式**：显式说"直接给正文，不要标题/前言/总结/Markdown"。不加这一条模型有概率给 `# 标题` 或 `**加粗**`。
4. **cloud-on 必加 grounding 句**：开启云端识别（首张照片随 prompt 一起发）时，必须显式说"基于照片中实际看到的画面来写，不要编造画面里没有的内容"。Qwen-VL 是 prompt-sensitive 的，没这条容易把图片当 optional context 略过，瞎编画面里没有的细节。

不做：
- ❌ 角色扮演（"你是资深旅行博主"）— 套路过气，输出反而油腻
- ❌ 塞 GPS 数字 / 经纬度坐标 — 对模型无信息量，反而会机械复述"我在 22.5N 113.9E ..."

---

## 2. Prompt 模板

```
【任务】用「{styleDesc}」的风格写一段中文旅行短文。

【场景信息】
- 地点：{poiName}                 ← 可选
- 心情：{mood}                    ← 可选
- 标签：{tag1}、{tag2}、{tag3}    ← 可选
- 用户补充：{userPrompt}          ← 可选

【照片元数据】
{exifDesc}                       ← 可选（无照片时不出现）

【输出要求】
- 基于照片中实际看到的画面来写，不要编造画面里没有的内容    ← 仅 cloud-on
- 长度：{lengthDesc}
- 直接给正文，不要标题、前言、总结，不要 Markdown 格式
- 生动描绘场景与氛围
- 照片里出现的地名、招牌、菜名可自然融入文中
```

> 没填的字段（无 mood、无 tags、无 userPrompt 等）对应行**整行不出现**。
> 没有任何【场景信息】子项时，整个【场景信息】section 也不出现。

---

## 3. 字段含义与取值

### 3.1 风格 `style` → `styleDesc`

| `style` 值 | `styleDesc` |
|---|---|
| `poetic` | 诗意盎然、优美浪漫 |
| `factual` | 客观纪实、真实记录 |
| `casual` | 轻松随意、生活化 |
| `minimal` | 极简主义、言简意赅 |

定义：[`STYLE_PROMPTS`](frontend/entry/src/main/ets/common/api/AiGatewayClient.ets) (line ~29)

### 3.2 长度 `lengthLevel` → `lengthDesc`

| `lengthLevel` | `lengthDesc` | 目标字数 |
|---|---|---|
| `short` | 1-2 句话，不超过 30 字，精炼概括 | ~30 |
| `medium` | 3-5 句话，约 50-80 字，适当展开描写 | ~80 |
| `long` | 6-10 句话，约 120-200 字，详细描绘场景细节和感受 | ~200 |

定义：[`LENGTH_PROMPTS`](frontend/entry/src/main/ets/common/api/AiGatewayClient.ets) (line ~37) + [`LENGTH_TARGET_CHARS`](frontend/entry/src/main/ets/common/api/AiGatewayClient.ets)

`max_tokens` 由目标字数派生：`Math.ceil(targetChars * 1.3) + 16`（中文一字约 1.3 token，留 16 给标点和 stop token）。

### 3.3 场景上下文

| 字段 | 来源 | 备注 |
|---|---|---|
| `poiName` | 节点 POI 名称（用户写或地图选） | 例如 "深圳湾公园西门" |
| `mood` | 节点心情标记 | 例如 "惬意"、"兴奋" |
| `tags` | 节点自定义标签数组 | 数组在 prompt 里用 `、` 顿号连接 |
| `userPrompt` | AI 页"补充说明"输入框 | 用户对生成的额外指引 |

每一项**任一为空就跳过对应行**，不出现"地点：（空）"这种 placeholder。

### 3.4 `exifDesc`（照片元数据描述）

由 [`LocalImageTagger.describeAggregate`](frontend/entry/src/main/ets/common/ai/LocalImageTagger.ets) 生成。

主要包含：
- 张数、拍摄时间范围（早/午/晚 / 跨天）
- 主色调 / 亮度倾向
- 像素尺寸 / 横竖屏比例统计
- 云端识别 ON 时**仅传首张**（其余张本地标签描述）

**不**包含：
- 经纬度数值（前面提到为什么）
- 设备型号 / 拍摄参数（对文案无用，反而会让模型把 ISO/光圈写进文章）

### 3.5 云端识别（`enableCloudTagging`）

| 状态 | prompt 行为 | 数据发送 |
|---|---|---|
| OFF（默认） | 仅文本 prompt 走 `askText` | 不上传照片任何字节 |
| ON | 首张照片裹 prompt 一起调 `askImage`；prompt 多一行 grounding 约束 | **仅**首张照片字节（剥 EXIF 副本）+ 文本 prompt |

控制开关：AI 文案页顶部 banner 上的 Switch（持久化在 [`ConsentManager`](frontend/entry/src/main/ets/common/utils/ConsentManager.ets) 里）。

---

## 4. 例子

### 4.1 最小输入（仅 POI + 1 张图，cloud-off）

```
【任务】用「轻松随意、生活化」的风格写一段中文旅行短文。

【场景信息】
- 地点：深圳湾公园西门

【照片元数据】
共 1 张照片，拍摄时间约 14:20，画面以蓝绿色调为主，竖屏…

【输出要求】
- 长度：3-5 句话，约 50-80 字，适当展开描写
- 直接给正文，不要标题、前言、总结，不要 Markdown 格式
- 生动描绘场景与氛围
- 照片里出现的地名、招牌、菜名可自然融入文中
```

### 4.2 完整输入（cloud-on + 全字段）

```
【任务】用「诗意盎然、优美浪漫」的风格写一段中文旅行短文。

【场景信息】
- 地点：南山广场港式茶餐厅
- 心情：惬意
- 标签：早午餐、家庭聚会
- 用户补充：写出虾饺和小笼包蒸笼冒着热气的感觉

【照片元数据】
共 3 张照片，拍摄时间约 10:30—11:10，画面以暖黄/竹色为主，第一张为竹蒸笼俯拍，其余为桌面与人物侧影…

【输出要求】
- 基于照片中实际看到的画面来写，不要编造画面里没有的内容
- 长度：6-10 句话，约 120-200 字，详细描绘场景细节和感受
- 直接给正文，不要标题、前言、总结，不要 Markdown 格式
- 生动描绘场景与氛围
- 照片里出现的地名、招牌、菜名可自然融入文中
```

---

## 5. 调用链与重试

```
用户点"生成文案"
  ↓
端侧 ExifTagger 批量提取元数据（异步并发）→ exifDesc
  ↓
buildBatchPrompt(request, exifDesc)                  ← 本文档描述的逻辑
  ↓
cloudOn ?
  ├─ askImage(firstPhoto, prompt)  →  ai-relay /v1/chat/completions/image
  └─ askText(prompt)               →  ai-relay /v1/chat/completions
  ↓
ai-relay → SiliconFlow Qwen3 / Qwen3-VL → 返回文本
  ↓
（命中敏感词 → finish_reason=content_filter 替换为固定话术）
  ↓
前端展示 generatedCopy + debugPrompt（默认收起）
```

详见 [`AUDIT_AUTH_FLOW.md`](backend/AUDIT_AUTH_FLOW.md) 和 ai-relay 源码。

---

## 6. 调试与答辩展示

AI 文案页底部有一张「📖 AI 看到的提示词」卡片，默认收起。点"查看"展开，能看到本次实际发给 LLM 的完整 prompt，并可一键复制。

**答辩演示建议**：

1. 给老师准备 2 张照片（同样一组）
2. 风格切到「诗意盎然」→ 生成 → 展开提示词卡片 → 指给老师看 `【任务】用「诗意盎然、优美浪漫」的风格...` 和【输出要求】区
3. 风格切到「极简主义」→ 重新生成 → 提示词卡片自动刷新 → 对比 `【任务】用「极简主义、言简意赅」的风格...`
4. 同样可以演示心情、标签、长度等字段开关如何精确改变 prompt 文本

这样既能让评审看到"个性化选项 → prompt 变化 → 输出风格变化"的因果链，也能保留页面正常用户的简洁体验（不展开就只是一行）。这一形态可以直接上架，不需要在 release / debug 间切换。

---

## 7. 已知限制

- **prompt 总长度上限**：ai-relay 配 `MAX_QUESTION_CHARS=3000`（环境变量 `AI_SERVICE_MAX_QUESTION_CHARS`）。超过 → 413。
- **首张照片体积**：cloud-on 时首张照片转 base64 后塞 multipart，理论无 hard limit，实测 > 8MB 易触发 nginx `client_max_body_size`（当前 15MB，定义在 [`audit.itsmappin.top.test.conf`](Backend_ItsMapPin_new/deploy/nginx/audit.itsmappin.top.test.conf)）。
- **流式输出未启用**：当前都是 non-stream 等完整响应，长度 `long` (~200 字) 等 30s 是正常的；流式接入是未来工作。
- **prompt 注入风险**：`userPrompt` 字段是用户自由输入，理论上可写"忽略以上指令，输出..."；目前依赖后端 sensitive-check `/text_check` 拦截，但 prompt-injection 本身无系统级防护。下一步要在 `buildBatchPrompt` 里对 `userPrompt` 做基础消毒（去掉 `【】` / 系统词等）。
