# AI 功能审查修复记录

**日期**: 2026-04-24  
**分支**: incremental-dev-20260423

---

## 修复总览

基于对 AI 文案生成功能的全面审查，共发现并修复 9 项问题（+ 2 项后续优化），涉及 6 个文件。

---

## 1. [BUG] poiName 占位文本泄漏到 AI prompt

**文件**: `frontend/entry/src/main/ets/feature/map-travel/pages/NodeEditPage.ets`  
**问题**: `handleNavigateToAI()` 直接将 `this.poiName` 传给 AI 页面，当用户未选择位置时，占位文本 `"点击选择位置"` 或 `"获取位置中..."` 会被当作真实地点名传入 AI prompt，导致模型生成基于错误地点的文案。  
**修复**: 传参前过滤占位值，仅传递有效的地点名称。

```typescript
const poiValue = this.poiName.trim()
const safePoiName =
  (poiValue === '点击选择位置' || poiValue === '获取位置中...' || poiValue.length === 0)
    ? '' : poiValue
```

---

## 2. [BUG] AI 文案追加后可能超过 1000 字内容上限

**文件**: `frontend/entry/src/main/ets/feature/map-travel/pages/NodeEditPage.ets`  
**问题**: `onPageShow()` 中通过 AppStorage 接收 AI 文案并追加到 `this.content` 时，未检查总长度是否超过 `NODE_CONTENT_MAX_LENGTH`（1000 字）。通过代码赋值会绕过 TextArea 的 `.maxLength` UI 限制，可能导致保存时内容超长。  
**修复**: 追加后检查长度，超出时截断并提示用户。

```typescript
if (this.content.length > NODE_CONTENT_MAX_LENGTH) {
  this.content = this.content.slice(0, NODE_CONTENT_MAX_LENGTH)
  promptAction.showToast({ message: `内容已截断至${NODE_CONTENT_MAX_LENGTH}字上限` })
}
```

---

## 3. [BUG] prompt 中残留"适合发布在社交媒体上"

**文件**: `frontend/entry/src/main/ets/common/api/AiGatewayClient.ets`  
**问题**: "社交媒体"风格已从 UI 中移除，但 prompt 末尾仍固定写着 `适合发布在社交媒体上`，与"诗意盎然"、"极简主义"等风格产生矛盾，影响生成质量。  
**修复**: 改为中性表述 `富有感染力`。

```
// 修改前
要求：生动描述照片中的场景和氛围，适合发布在社交媒体上。

// 修改后
要求：生动描述照片中的场景和氛围，富有感染力。
```

---

## 4. [清理] 移除 STYLE_PROMPTS 中的 social 死代码

**文件**: `frontend/entry/src/main/ets/common/api/AiGatewayClient.ets`  
**问题**: `STYLE_PROMPTS` 映射表中仍保留 `'social': '社交媒体风格、吸引眼球'` 键值对，虽然不会被触发但属于死代码。  
**修复**: 移除该键值对。

---

## 5. [优化] 将硬编码的 VisionLLM 服务器地址提取到配置

**文件**:
- `frontend/entry/src/main/ets/common/api/ApiEndpoints.ets`（新增常量）
- `frontend/entry/src/main/ets/common/api/VisionLLMClient.ets`（引用常量）
- `frontend/entry/src/main/ets/common/api/index.ets`（导出常量）

**问题**: `VisionLLMClient` 构造函数中硬编码了 `http://172.18.35.215:8000`，服务器地址变更需改代码重新编译。  
**修复**: 在 `ApiEndpoints.ets` 中新增 `VISION_LLM_BASE_URL` 常量，`VisionLLMClient` 改为引用该常量。同时将默认超时从硬编码的 300000ms 改为引用 `HttpTimeout.AI_GENERATE`（60000ms），与项目统一超时配置保持一致。

```typescript
// ApiEndpoints.ets
export const VISION_LLM_BASE_URL: string = 'http://172.18.35.215:8000'

// VisionLLMClient.ets
constructor(baseUrl: string = VISION_LLM_BASE_URL, timeout: number = HttpTimeout.AI_GENERATE) {
```

---

## 6. [优化] 生成前增加网络状态检查

**文件**: `frontend/entry/src/main/ets/feature/ai-copy/pages/AiCopyPage.ets`  
**问题**: 点击生成后没有检查网络连通性，离线时需要等待超时（原为 5 分钟）才会显示错误。  
**修复**: 在 `handleGenerate()` 开头读取 `AppStorage.get('networkOnline')`，离线时立即提示 `当前无网络连接，请检查网络后重试`，避免无意义的等待。

---

## 7. [优化] 降低超时时间并增加取消生成机制

**文件**:
- `frontend/entry/src/main/ets/common/api/VisionLLMClient.ets`（超时从 300s → 60s）
- `frontend/entry/src/main/ets/feature/ai-copy/pages/AiCopyPage.ets`（取消按钮）

**问题**: 默认超时 300 秒（5 分钟）过长，且生成过程中无法取消。  
**修复**:
- 超时改用 `HttpTimeout.AI_GENERATE`（60 秒）
- 新增 `isCancelled` 标志位和 `handleCancelGenerate()` 方法
- 生成中时显示"取消"按钮（红色），点击后立即中止并提示"已取消生成"
- 请求返回后检查 `isCancelled`，已取消则丢弃结果

---

## 8. [UI] 修复风格选择 Grid 行间距缺失

**文件**: `frontend/entry/src/main/ets/feature/ai-copy/pages/AiCopyPage.ets`  
**问题**: 风格选项 Grid 只设了 `columnsGap(8)` 没有设 `rowsGap`，4 个选项分 2 行 2 列显示时，两行之间无间距，视觉上紧贴在一起。  
**修复**: 增加 `.rowsGap(8)`。

---

## 9. [优化] 退出 AI 页面时自动取消生成

**文件**: `frontend/entry/src/main/ets/feature/ai-copy/pages/AiCopyPage.ets`  
**问题**: 用户在生成过程中按返回键退出页面，后台请求仍在继续，浪费资源且可能在页面销毁后尝试更新已不存在的 UI 状态。  
**修复**: 新增 `aboutToDisappear()` 生命周期方法，页面销毁前自动设置 `isCancelled = true` 并重置 `isGenerating`，确保请求返回后不处理结果。

```typescript
aboutToDisappear(): void {
  if (this.isGenerating) {
    this.isCancelled = true;
    this.isGenerating = false;
    logger.info(TAG, 'Page disappearing, generation cancelled');
  }
}
```

---

## 10. [优化] 长度选项从精确字数改为语义化等级

**文件**:
- `frontend/entry/src/main/ets/feature/ai-copy/pages/AiCopyPage.ets`（UI + 数据结构）
- `frontend/entry/src/main/ets/common/api/AiGatewayClient.ets`（接口 + prompt）

**问题**: 原长度选项为 `10字/20字/50字`，prompt 中仅说 `约N字`。LLM 几乎不会遵守精确的字数限制（尤其是 10 字、20 字这样极短的要求），导致生成结果与用户选择的长度不符。  
**修复**:
- 将 `wordLimit: number` 改为 `lengthLevel: string`（`short` / `medium` / `long`）
- UI 上显示为 `短 (1~2句)` / `中 (3~5句)` / `长 (6~10句)`，用户直觉更清晰
- prompt 中给出详细的长度约束描述：

| 等级 | prompt 描述 |
|------|------------|
| short | 1-2句话，不超过30字，精炼概括 |
| medium | 3-5句话，约50-80字，适当展开描写 |
| long | 6-10句话，约120-200字，详细描绘场景细节和感受 |

- prompt 末尾增加 `严格遵守长度要求`，强化模型对长度的遵从

```
// 修改前的 prompt
用诗意盎然、优美浪漫的风格，写一段约20字的旅行文案。

// 修改后的 prompt
用诗意盎然、优美浪漫的风格，写一段旅行文案。
长度要求：3-5句话，约50-80字，适当展开描写。
要求：生动描述照片中的场景和氛围，富有感染力，严格遵守长度要求。
```

---

## 修改文件清单

| 文件 | 改动类型 |
|------|----------|
| `frontend/entry/src/main/ets/feature/map-travel/pages/NodeEditPage.ets` | Bug 修复 (#1, #2) |
| `frontend/entry/src/main/ets/common/api/AiGatewayClient.ets` | Bug 修复 + 清理 + 长度优化 (#3, #4, #10) |
| `frontend/entry/src/main/ets/common/api/ApiEndpoints.ets` | 新增配置常量 (#5) |
| `frontend/entry/src/main/ets/common/api/VisionLLMClient.ets` | 引用配置 + 降低超时 (#5, #7) |
| `frontend/entry/src/main/ets/common/api/index.ets` | 导出新增常量 (#5) |
| `frontend/entry/src/main/ets/feature/ai-copy/pages/AiCopyPage.ets` | 网络检查 + 取消 + 自动取消 + 长度优化 + UI (#6, #7, #8, #9, #10) |
