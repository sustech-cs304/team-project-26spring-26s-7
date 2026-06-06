# AppGallery 上架 · AI 生成合成内容标识合规材料清单

> 关联法规：《人工智能生成合成内容标识办法》、《互联网信息服务深度合成管理规定》第十六、十七条
> 华为指南：https://developer.huawei.com/consumer/cn/doc/app/50111-10
> 适用范围：ItsMapPin (com.example.itsmappin) — HMOS NEXT 旅行记忆 app

---

## 一、本应用的 AI 生成合成场景

ItsMapPin 仅有 **一类** AI 生成合成内容：

| 场景 | 类型 | 入口 | 数据流向 |
|---|---|---|---|
| AI 旅行文案生成 | **文本** | "+创建节点"或"编辑节点"页 → "AI 文案"按钮 → `AiCopyPage` | 生成结果 → 用户点"应用"→ 写入节点 `content` 字段 → 存 SQLite 本地 DB；用户分享时跟随分享 viewer HTML 一起展示给接收方 |

**不涉及** 的场景：
- ☒ 音频生成（应用内 BGM 是预置素材，非 AI 生成）
- ☒ 图片生成（应用内所有照片来自用户相册，无 AI 生图）
- ☒ 视频生成（无 AI 生成视频）
- ☒ 虚拟场景生成（无）

---

## 二、显式标识实现

### 代码改动（已完成）

| 文件 | 改动 |
|---|---|
| `frontend/entry/src/main/ets/common/utils/Constants.ets` | 新增 `AI_GENERATED_MARKER = 'AI 生成 · '` 常量，含"AI"+"生成"双要素，满足办法第四条文本标识要求 |
| `frontend/entry/src/main/ets/common/index.ets` | 把常量从 common barrel 导出 |
| `frontend/entry/src/main/ets/feature/ai-copy/pages/AiCopyPage.ets` | `handleApplyToNode` 在写入 `aiCopyContent` 时强制加 marker 前缀；二次应用幂等（已带前缀不重复加） |

### Marker 内嵌 vs UI 角标

采取 **内嵌前缀写法** ("AI 生成 · {原文}")，原因：
- marker 作为 content 字符串的一部分，跨**存储**（SQLite）、**展示**（NodeDetailPage / NodeListView）、**分享**（share-service viewer HTML 渲染 `node.content`）、**复制**（剪贴板按字符串复制） 全路径自动传播
- 满足办法第四条 "提供生成合成内容下载、复制、导出等功能时，应当确保**文件**中含有满足要求的显式标识" 的要求
- 不依赖任何额外 UI 渲染逻辑，share viewer / 第三方截屏工具看到的都是同一段带 marker 的文本

### 提交时需提供的截图

需要在真机上至少各截一张：

- [ ] **生成阶段**：AiCopyPage 生成完文案后的界面（生成的预览框里的文字本身**不必**带 marker，因为还没"应用"；但页面顶/底显示了"由 AI 生成"的提示）
- [ ] **应用后**：NodeEditPage 接收到 AI 文案后，正文 TextArea 里**开头**带 "AI 生成 · " 前缀
- [ ] **节点详情页**：NodeDetailPage 展示节点正文，前缀 "AI 生成 · " 清晰可见
- [ ] **分享后**：发布分享链接后用浏览器打开 `https://audit.itsmappin.top:8443/s/{code}?...`，渲染出来的 HTML 节点正文里 marker 同样存在

> 截图保存到 `references/documents/appgallery-submission/screenshots/` 目录。

---

## 三、隐式标识 / 元数据 / 说明函

### 结论：本应用 **不需要** 提交《文件元数据隐式标识说明函》

依据华为指南 FAQ 第 5 条说明：

> 如您的应用未提供文本、音频、图片、视频等人工智能生成合成内容文件的**导出或下载**等功能，不涉及人工智能生成合成内容文件元数据和隐式标识，**无需提供文件元数据隐式标识说明文件和文件元数据中已添加隐式标识的截图**。

我们的 app：
- AI 生成的内容是**文本字符串**，存在节点 `content` 字段（SQLite 行），**不是独立可下载/导出的文件**
- 没有"导出为 .txt / .docx / .pdf"之类的功能
- "复制"是把文本复制到系统剪贴板，不是文件导出
- "分享"是在服务端生成 HTML 页面给接收方看，本机不产生可下载的文件

所以法规要求的"在生成合成内容的**文件元数据**中添加隐式标识"这一项**不适用**。

### 万一华为审核要求补交怎么办

按法规第五条 + 附录 E，隐式标识应是嵌入到文件头部的 JSON：

```json
{"AIGC":{"Label":"1","ContentProducer":"<本应用名或编码>","ProduceID":"<本次生成的唯一编号>","ReservedCode1":"","ContentPropagator":"<本应用名或编码>","PropagateID":"<本次生成的唯一编号>","ReservedCode2":""}}
```

字段对照表：
- `Label`: `"1"` 表示属于人工智能生成合成内容
- `ContentProducer`: `"ItsMapPin"` 或 AppGallery 上的开发者编码
- `ProduceID`: 每次生成的唯一编号——可以用 UUID v4，存到对应 MemoryNode 一个新字段（比如 `ai_produce_id`）
- `ReservedCode1` / `ReservedCode2`: 可留空或填数字签名等
- `ContentPropagator` / `PropagateID`: 首次写入时与 Producer/ProduceID 一致

如果真要做，最小改动：
1. `MemoryNodeRepository` 表加一列 `ai_produce_id TEXT NULL`
2. `AiCopyPage.handleApplyToNode` 生成时一并算一个 UUID 写进去
3. 分享 publish 时把整段 JSON 写进 HTML `<meta name="aigc-implicit">` 头里
4. 截图浏览器 view-source 显示该 meta 标签

**但这一步在本期上架不主动做**——华为不要求就不交。

---

## 四、《说明函》填写草稿（备查，不主动提交）

如果审核员明确要求提交《人工智能生成合成内容文件元数据隐式标识说明函》，按下面草稿把空缺补完粘进 [说明函模板.docx](../../shangjia/extracted/人工智能生成合成内容文件元数据隐式标识说明函.docx)（或者用 LibreOffice 直接编辑）后加盖公章再提交。

```
人工智能生成合成内容文件元数据隐式标识说明函

本公司承诺并确认，本公司在华为应用市场中上架的：
  应用名称：ItsMapPin
  应用 ID 或包名：com.example.itsmappin   ← (按 AppGallery Connect 实际包名填)

提供人工智能生成合成内容：
  ☑ 文本    ☐ 图片    ☐ 音频    ☐ 视频    ☐ 虚拟场景    ☐ 其他

本应用的 AI 生成合成场景为：用户在创建 / 编辑旅行节点时，可调用应用
内 "AI 文案" 功能生成中文旅行短文，作为该节点的正文内容。

应用已按照《人工智能生成合成内容标识办法》和《人工智能生成合成内容
标识方法》要求，在生成合成内容上添加 **显式标识**："AI 生成 · " 文本
前缀（包含"AI"+"生成"双要素），随 content 字段在应用内展示 / 复制 /
分享传播。

由于本应用不提供文本文件的下载、导出等功能（AI 生成的文本只作为节点
正文存入本地 SQLite 数据库，不产生独立的文本文件），不涉及文件元数据
和隐式标识的添加。

如审核要求补充隐式标识，本公司将按附录 E 规定，在分享发布的 HTML 中
通过 <meta name="aigc-implicit"> 嵌入 AIGC JSON：

  {"AIGC":{"Label":"1","ContentProducer":"<企业名称>","ProduceID":"<UUID>",
   "ReservedCode1":"","ContentPropagator":"<企业名称>","PropagateID":"<UUID>",
   "ReservedCode2":""}}

  - Label = "1" (属于人工智能生成合成内容)
  - ContentProducer / ContentPropagator = AppGallery Connect 实名企业名称
  - ProduceID / PropagateID = 每次生成的 UUID v4，与节点一一对应

本公司在此确认，本公司自行独立负责该应用的运营，处理该应用的投诉
以及因该应用而产生的争议和纠纷，并独立承担因最终用户使用该应用产
生的问题和责任。

本公司承诺，该应用在华为应用市场上架期间及下架后，如因内容或版权
等问题侵犯了第三方合法权益，或因该应用的运营产生相关问题和责任，
本公司将独立承担所有法律责任；如给华为造成损失的，本公司亦同意
赔偿华为因此遭受的直接经济损失。特此证明和保证。

                                  企业名称：__________________
                                  日   期：__________________
                                                 (签章有效)
```

> 注：说明函上的企业名称必须与 AppGallery Connect 平台账号实名的企业
> 名称**完全一致**；如果是个人开发者上架，写实名 + 身份证号。

---

## 五、上架流程提交清单

按华为指南 FAQ 第 5 条，**本应用应当上交的材料 = 仅一项**：

- [ ] **应用内生成合成内容中已添加显式标识的截图**（按上面第二节列的 4 张截图）

**不需要** 上交（FAQ 明确说"无需"）：
- ☒ 文件元数据隐式标识说明函
- ☒ 文件元数据中已添加隐式标识的截图

如华为审核员仍要求，提交备查草稿（本文档第四节）+ 截图浏览器中
HTML meta 标签出现 AIGC JSON 的画面。

---

## 六、复核要点（push 前 / 真机自测）

打开节点编辑页 → AI 文案 → 生成 → 应用 → 返回节点编辑：
- [ ] 正文 TextArea 的最开头是否出现 "AI 生成 · " 字样
- [ ] 用户在该前缀后追加 / 修改文字，前缀保留不被破坏（手动保留）
- [ ] 保存节点 → 进节点详情页，正文是否仍然以 "AI 生成 · " 开头
- [ ] 长按选中正文 → 复制 → 在备忘录里粘贴，是否保留了 "AI 生成 · " 前缀
- [ ] 该节点所在路线点 "分享路线" → 用浏览器打开链接 → HTML 节点卡片里
  正文同样以 "AI 生成 · " 开头

全部对齐再发版。
