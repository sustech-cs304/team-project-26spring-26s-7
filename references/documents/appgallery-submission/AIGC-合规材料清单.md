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

### 显式 vs 隐式 —— 不能做"更隐式"

法规明确给了两个互斥的定义：

| 类型 | 定义（办法第三条原文） | 适用对象 |
|---|---|---|
| **显式标识** | 在生成合成内容或者**交互场景界面**中添加的，以文字 / 声音 / 图形等方式呈现并**可以被用户明显感知到**的标识 | **AI 文本内容**必须有 |
| **隐式标识** | 采取技术措施在生成合成内容**文件数据**中添加的，**不易被用户明显感知到**的标识 | 文件 metadata，**仅限可导出的文件** |

也就是说："让用户感知不到" 在法规里属于"隐式标识"，**而隐式标识只针对可导出的文件 metadata**——我们 app 没有"导出 AI 文本"功能，所以隐式标识对我们既不适用也满足不了"显式"要求。**显式标识不能"做隐"**，必须用户感知到。

**用户可能后续编辑掉 marker——这个不是合规问题**：法规义务在"服务提供者**生成时**添加"，用户后续手动改文本是用户的事。我们只要保证生成的瞬间出现 marker，截图能证明就够了。

### 代码改动（已完成）

| 文件 | 改动 |
|---|---|
| `frontend/entry/src/main/ets/common/utils/Constants.ets` | `AI_GENERATED_MARKER = '【AI生成】'` 常量，含"AI"+"生成"双要素，用中文方头括号包起来（中文文本常见标注风格） |
| `frontend/entry/src/main/ets/common/index.ets` | barrel export |
| `frontend/entry/src/main/ets/feature/ai-copy/pages/AiCopyPage.ets` | `handleApplyToNode` 写入 `aiCopyContent` 时加 `【AI生成】` 前缀；二次应用幂等（已带前缀不重复加） + 生成结果上方一直显示黄底警示文本 "⚠ 本段文字由 AI 生成，请人工核对后再使用"（满足办法第四条第六款"其他生成合成服务场景根据自身应用特点添加显著的提示标识"） |

### 双层标识策略

| 层 | 形式 | 何时可见 | 满足的条款 |
|---|---|---|---|
| **L1 界面提示** | AiCopyPage 上方黄底警示横幅 | 用户在 AI 生成页面看到 | 第四条第六款（交互场景界面） |
| **L2 内嵌文本前缀** | 节点 content 字符串开头 `【AI生成】` | DB / 详情页 / 分享 viewer / 复制粘贴 都看得到 | 第四条第一款（文本起始位置）+ 第四条最后一段（下载、复制、导出场景） |

L1 保证用户**生成时**就看到 "这是 AI 生成的"，L2 保证 marker 跟随文本传到所有下游。两条互补、缺一不可。

### 提交时需提供的截图（4 张）

每张都有明确的 "看哪个像素证明合规" 的目标，照下面表格截就行：

| # | 在哪个屏幕 | 截图里要清晰可见的关键元素 | 为什么 |
|---|---|---|---|
| 1 | **AiCopyPage**（AI 文案助手页）生成完一段文案后 | 黄底警示横幅 "⚠ 本段文字由 AI 生成，请人工核对后再使用" + "AI 生成结果" 标题 + 下面的预览文本 | 证明 L1 界面提示存在 |
| 2 | **NodeEditPage**（节点编辑页）AiCopyPage 点"应用"返回后 | 正文 TextArea 里**开头有** `【AI生成】` 4 个字（紧跟着原文） | 证明 L2 marker 已写入节点 content |
| 3 | **NodeDetailPage**（节点详情页）保存退出再次进入后 | 正文区域顶部显示 `【AI生成】今天去深圳湾散步……` 这种带前缀的渲染 | 证明 marker 持久化 + 详情展示路径保留 marker |
| 4 | **分享 viewer**（浏览器打开 `https://audit.itsmappin.top:8443/s/{code}?…`） | HTML 卡片里节点正文同样以 `【AI生成】` 开头 | 证明 marker 通过 share-service 传到 web viewer，第三方接收方也能看到 |

> **PNG 截图记得转 JPG** 再放进 zip——AGC 上传栏只接受 JPG / JPEG / BMP / PDF。
>
> 命令行批量转换：`for f in *.png; do convert "$f" "${f%.png}.jpg"; done`（需要 ImageMagick）。
>
> 截图保存到 `references/documents/appgallery-submission/screenshots/`。

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
标识方法》要求，在生成合成内容上添加 **显式标识**："【AI生成】" 文本
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

### AGC 后台位置

AppGallery Connect → 应用信息 → 滚到 **AI 功能声明**：
- `AI 生成合成服务`：选 **涉及**
- `AI 生成合成服务类型`：勾 **文本**（其他不勾）

→ 提示文本会引导到 **版权信息 > 授权书及其他材料** 的 zip 上传栏。

### zip 包格式约束（来自 AGC 上传栏的字面要求）

- 压缩包格式必须是 **zip**
- 大小 ≤ **200 MB**
- 包内只允许这几种文件类型：**JPG / JPEG / BMP / PDF**
  - **不收 PNG！**HMOS 设备截屏默认是 PNG，务必转 JPG 再放进去
  - 文档（说明函等）要以 PDF 提交，不收 docx
- 文件夹层级 ≤ 3 层
- 文件总数 ≤ 200

### zip 内推荐结构

```
itsmappin-aigc-materials.zip
├── 01-explicit-marker-screenshots/
│   ├── aicopy-page.jpg          ← AiCopyPage 生成完文案
│   ├── nodeedit-after-apply.jpg ← 应用到 NodeEditPage 后正文带 "【AI生成】" 前缀
│   ├── nodedetail-display.jpg   ← NodeDetailPage 展示正文带 marker
│   └── share-viewer.jpg         ← 分享 HTML 页面里 marker 同样可见
└── 02-declaration/
    └── AIGC-说明函.pdf          ← 可选；FAQ 说"无需"但放进去当兜底，
                                      用 shangjia/extracted/ 里的 docx 模板
                                      填完盖章后用 Word 导出 PDF
```

### 必交（按华为 FAQ 第 5 条第 2 项）

- [ ] **应用内生成合成内容中已添加显式标识的截图** —— 即 `01-explicit-marker-screenshots/` 下那 4 张

### 可选 / 兜底（华为 FAQ 第 5 条第 1、3 项说"无需"，但建议放进去）

- [ ] **AIGC-说明函.pdf** —— `02-declaration/` 下；如果审核员真要才有用，平时空着 AGC 也不报错

### 不需要（FAQ 明确说"无需"，且我们也没有）

- ☒ 文件元数据隐式标识截图（应用不导出 AI 文件、没法截）
- ☒ 软著方授权发行方 "版权授权书"（自研项目，AGC 界面上灰字写明"如自研可不提供（选填）"）
- ☒ 特种行业许可证（旅行 app 非特种行业）
- ☒ 文件元数据中已添加隐式标识的截图

如华为审核员仍要求，提交备查草稿（本文档第四节）+ 截图浏览器中
HTML meta 标签出现 AIGC JSON 的画面。

---

## 六、复核要点（push 前 / 真机自测）

打开节点编辑页 → AI 文案 → 生成 → 应用 → 返回节点编辑：
- [ ] 正文 TextArea 的最开头是否出现 "【AI生成】" 字样
- [ ] 用户在该前缀后追加 / 修改文字，前缀保留不被破坏（手动保留）
- [ ] 保存节点 → 进节点详情页，正文是否仍然以 "【AI生成】" 开头
- [ ] 长按选中正文 → 复制 → 在备忘录里粘贴，是否保留了 "【AI生成】" 前缀
- [ ] 该节点所在路线点 "分享路线" → 用浏览器打开链接 → HTML 节点卡片里
  正文同样以 "【AI生成】" 开头

全部对齐再发版。
