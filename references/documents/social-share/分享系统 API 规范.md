# 分享系统 API 规范 v1.0

> **文档用途**：前后端接口契约。App 端与自建服务器同步开发时以此为准。
> **日期**：2026-04-28
> **基准文档**：`技术需求文档：地图叙事 H5 海报分享系统 (项目对齐版).md`

---

## 1. 概述

| 项目 | 说明 |
|------|------|
| 协议 | HTTPS（生产）/ HTTP（开发调试） |
| 编码 | UTF-8 |
| 服务端 Base URL | `https://<自建服务器域名>` |
| 鉴权 | HMAC-SHA256 签名（仅限 `/s/:shortCode` 访问校验） |
| 发布接口鉴权 | 暂无（MVP 阶段可内网调用或加简单 API Key） |

---

## 2. 前后端职责划分

```
┌─────────────────────────────────────────────────────────────┐
│                      App 端 (前端)                           │
│                                                             │
│  ① 从 RDB 读取 trip + nodes 数据                              │
│  ② 读取照片文件 → 本地 EXIF 清洗 → ArrayBuffer[]              │
│  ③ 组装 multipart 请求体                                     │
│  ④ POST /api/v1/share/publish                               │
│  ⑤ 解析响应 → 提取 data.url                                  │
│  ⑥ systemShare 分享链接 / 剪贴板复制                          │
│                                                             │
│  工作量: ★★☆ (~20%)                                           │
└──────────────────────────┬──────────────────────────────────┘
                           │  multipart (JSON + binary)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    自建服务器 (后端)                           │
│                                                             │
│  ── publish 处理 ──                                          │
│  ① 解析 multipart → tripData JSON + photo_N[]               │
│  ② 校验 (photoCount、节点数量、大小限制、expiryHours 范围)     │
│  ③ EXIF 二次清洗（保底）                                     │
│  ④ 照片 → WebP 转码 (375w / 750w 两档)                       │
│  ⑤ 生成 shortCode (8 位随机, 冲突重试)                       │
│  ⑥ HMAC-SHA256 签名                                         │
│  ⑦ 写入临时缓存 (trip 元数据 + WebP 文件, TTL = expiryHours)  │
│  ⑧ 返回 201 + URL                                           │
│                                                             │
│  ── 访问处理 ──                                              │
│  ⑨ GET /s/:shortCode → 校验签名 → 校验过期                   │
│  ⑩ 从缓存读取数据 → EJS 模板渲染 → 返回完整 HTML              │
│                                                             │
│  ── 维护任务 ──                                              │
│  ⑪ WebP 文件静态托管 (Nginx)                                 │
│  ⑫ 过期缓存清理 (lazy delete + cron)                        │
│  ⑬ H5 前端页面开发与部署 (Vite + EJS)                        │
│                                                             │
│  工作量: ★★★★★ (~80%)                                        │
└─────────────────────────────────────────────────────────────┘
```

### 边界一句话总结

**App 端只负责：读数据 → 发请求 → 分享返回的 URL。其余全部在后端。**

---

## 3. API 列表

| # | 方法 | 路径 | 说明 | 调用方 |
|---|------|------|------|--------|
| 1 | `POST` | `/api/v1/share/publish` | 发布分享（上传图文） | App 端 |
| 2 | `GET` | `/s/:shortCode` | 访问 H5 分享页面 | 浏览器 |
| 3 | `GET` | `/api/v1/share/:shortCode/status` | 查询分享状态（可选） | App 端 |

---

## 4. POST /api/v1/share/publish

### 4.1 请求

```
POST /api/v1/share/publish
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary
```

**Parts 定义**：

| Part Name | 类型 | 必填 | 说明 |
|-----------|------|------|------|
| `tripData` | text/plain | 是 | trip 元数据 JSON 字符串（结构见 4.2） |
| `photo_N` | image/* | 否 | 照片文件，N 从 0 开始连续编号；与 `tripData.nodes` 中的 `photoCount` 字段联合解析 |
| `expiryHours` | text/plain | 否 | 过期小时数，默认 168（7 天），范围 1–720 |

**约束**：
- 单个照片文件 ≤ 20 MB（按照后端调整）
- 总请求体 ≤ 100 MB（对应约 20 张照片）（按照后端调整）
- 照片格式：JPEG / PNG / HEIF（服务端统一转码 WebP）
- 照片数量必须等于所有 `nodes[].photoCount` 之和，否则返回 400

### 4.1.1 照片文件规格（按照 AI Feature 处理图片的逻辑来）

每个 `photo_N` 是一个标准 multipart file part，包含以下 HTTP 头：

| 头 | 值 | 说明 |
|----|-----|------|
| `Content-Disposition` | `form-data; name="photo_N"; filename="photo_N.{ext}"` | N 从 0 开始连续；`{ext}` 为格式对应扩展名 |
| `Content-Type` | 见下表 | 必须与实际文件格式匹配 |

**接受的文件格式**：

| 格式 | MIME Type | 扩展名 | 说明 |
|------|-----------|--------|------|
| JPEG | `image/jpeg` | `.jpg` / `.jpeg` | 推荐，兼容性最好 |
| PNG | `image/png` | `.png` | 支持透明通道 |
| HEIF/HEIC | `image/heic` 或 `image/heif` | `.heic` / `.heif` | HarmonyOS 设备原生格式 |

**传输形式**：

- part body 为**原始文件字节流**（raw binary），不 base64 编码
- 由 `http.MultipartBuilder.addBinaryPart()` 直接写入文件 buffer
- 服务端按 `Content-Type` 判断解码器，不做扩展名推断

**示例**（单个照片 part 的 HTTP 表示）：
```
------Boundary
Content-Disposition: form-data; name="photo_0"; filename="photo_0.jpg"
Content-Type: image/jpeg

<JPEG 文件原始字节流>
------Boundary
```

### 4.2 tripData JSON 结构

```json
{
  "tripId": "trip_abc123",
  "tripName": "深圳湾周末骑行",
  "totalDistance": 12.5,
  "coverIndex": 0,
  "createdAt": 1714200000000,
  "nodes": [
    {
      "id": "node_001",
      "title": "红树林公园",
      "content": "下午三点到达，阳光正好...",
      "poiName": "深圳湾红树林",
      "photoCount": 2,
      "mood": "惬意",
      "tags": ["骑行", "日落", "自然"],
      "visitedAt": 1714200000000,
      "nodeOrder": 0
    },
    {
      "id": "node_002",
      "title": "人才公园",
      "content": "傍晚的灯光很美。",
      "poiName": "深圳人才公园",
      "photoCount": 1,
      "mood": "感动",
      "tags": ["夜景"],
      "visitedAt": 1714300000000,
      "nodeOrder": 1
    }
  ]
}
```

**字段说明**：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `tripId` | string | 是 | App 端 Travel ID，服务端仅用于幂等去重 |
| `tripName` | string | 是 | 路线名称，显示在 H5 标题和分享文案中 |
| `totalDistance` | number | 否 | 总距离（km），H5 展示用 |
| `coverIndex` | number | 否 | 封面照片在扁平化 photo 列表中的索引，默认 0 |
| `createdAt` | number | 否 | 路线创建时间 (Unix ms) |
| `nodes` | array | 是 | 节点列表，至少 1 个，最多 30 个 |
| `nodes[].id` | string | 是 | 节点唯一 ID |
| `nodes[].title` | string | 是 | 节点标题 |
| `nodes[].content` | string | 否 | 用户笔记全文 |
| `nodes[].poiName` | string | 否 | 地点名称 |
| `nodes[].latitude` | number | 否 | 节点纬度。Phase 1 可不消费，Phase 2 地图回放使用 |
| `nodes[].longitude` | number | 否 | 节点经度。Phase 1 可不消费，Phase 2 地图回放使用 |
| `nodes[].photoCount` | number | 是 | 该节点的照片数量（可为 0） |
| `nodes[].mood` | string | 否 | 心情标签 |
| `nodes[].tags` | string[] | 否 | 自定义标签列表 |
| `nodes[].visitedAt` | number | 否 | 到访时间 (Unix ms) |
| `nodes[].nodeOrder` | number | 是 | 路线顺序，从 0 开始 |

### 4.3 照片与节点的对应规则

```
照片扁平列表: [photo_0, photo_1, photo_2, ...]
              
按 nodeOrder 升序遍历节点：
  node[0].photoCount = 2  →  photo_0, photo_1 属于 node[0]
  node[1].photoCount = 1  →  photo_2 属于 node[1]
  node[2].photoCount = 0  →  无照片
  ...
```

**校验**：`sum(nodes[].photoCount) === photos.length`，不匹配返回 `400 INVALID_PHOTO_COUNT`。

### 4.4 成功响应

```
HTTP 201 Created
Content-Type: application/json
```

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "url": "https://tp.app/s/xK9mNz?t=1714800000&s=a7f2c9b3d1e4f5a6b7c8d9e0f1a2b3c4",
    "shortCode": "xK9mNz",
    "expiresAt": 1714800000
  }
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `url` | string | 完整分享链接，可直接复制/分享 |
| `shortCode` | string | 短码，调试用 |
| `expiresAt` | number | 过期时间 (Unix timestamp，秒级) |

### 4.5 错误响应

```
HTTP 4xx / 5xx
Content-Type: application/json
```

```json
{
  "code": 40001,
  "message": "INVALID_PHOTO_COUNT",
  "detail": "expected 3 photos, got 2"
}
```

**错误码**：

| HTTP | code | message | 说明 |
|------|------|---------|------|
| 400 | 40001 | `INVALID_PHOTO_COUNT` | 照片数量与 photoCount 之和不匹配 |
| 400 | 40002 | `EMPTY_NODES` | nodes 数组为空 |
| 400 | 40003 | `TOO_MANY_NODES` | nodes 超过 30（待议） 个 |
| 400 | 40004 | `PHOTO_TOO_LARGE` | 单张照片超过 20（按照后端需求调整） MB |
| 400 | 40005 | `BODY_TOO_LARGE` | 总请求体超过 100（按照后端需求调整） MB |
| 400 | 40006 | `INVALID_JSON` | tripData JSON 解析失败 |
| 400 | 40007 | `INVALID_EXPIRY` | expiryHours 不在 1–720 范围内 |
| 429 | 42901 | `RATE_LIMITED` | 请求频率过高 |
| 500 | 50000 | `INTERNAL_ERROR` | 服务端内部错误 |

---

## 5. GET /s/:shortCode

### 5.1 请求

```
GET /s/{shortCode}?t={expiryTimestamp}&s={signature}
```

| 参数 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `shortCode` | path | string | 是 | 8 位短码（大小写字母+数字） |
| `t` | query | string | 是 | 过期时间 (Unix timestamp，秒) |
| `s` | query | string | 是 | HMAC-SHA256 签名 (hex 编码，64 字符) |

**示例**：
```
https://tp.app/s/xK9mNz?t=1714800000&s=a7f2c9b3d1e4f5a6b7c8d9e0f1a2b3c4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0
```

### 5.2 正常响应（分享有效）

```
HTTP 200 OK
Content-Type: text/html; charset=utf-8
Cache-Control: no-store
```

返回注入 trip 数据的完整 H5 页面 HTML。数据内联在 `<script>window.__ROUTE_DATA__ = {...};</script>` 中。

**`window.__ROUTE_DATA__` 结构**：

```typescript
interface ShareRouteData {
  tripId: string;
  tripName: string;
  totalDistance: number;
  nodeCount: number;
  coverPhotoUrl: string;
  createdAt: number;
  expiresAt: number;
  nodes: ShareNodeData[];
}

interface ShareNodeData {
  id: string;
  title: string;
  content: string;
  poiName: string;
  photos: { url: string; width: 375 | 750 }[];
  mood: string;
  tags: string[];
  nodeOrder: number;
}
```

`photos[].url` 指向自建服务器上转码后的 WebP 资源，如：
```
https://tp.app/cache/xK9mNz/node_001_0_375w.webp
https://tp.app/cache/xK9mNz/node_001_0_750w.webp
```

### 5.3 签名校验失败

```
HTTP 403 Forbidden
Content-Type: text/html; charset=utf-8
```

返回错误页 HTML（不含任何 trip 数据）：
```html
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>链接已失效</title></head>
<body>
  <h1>此链接无效或已过期</h1>
  <p>请向分享者重新索取链接。</p>
</body>
</html>
```

### 5.4 三种校验失败场景

| 场景 | HTTP | 页面文案 |
|------|------|---------|
| 签名不匹配 | 403 | "此链接无效或已过期" |
| 已过期 | 410 Gone | "此链接已过期" |
| shortCode 不存在 | 404 | "页面不存在" |

---

## 6. GET /api/v1/share/:shortCode/status（可选）

供 App 端查询分享状态，用于判断是否需要重新发布。

### 6.1 请求

```
GET /api/v1/share/{shortCode}/status
```

### 6.2 响应

**分享有效**：
```json
{
  "code": 0,
  "data": {
    "shortCode": "xK9mNz",
    "expiresAt": 1714800000,
    "remainingSeconds": 580000,
    "publishedAt": 1714200000
  }
}
```

**分享已过期/不存在**：
```json
{
  "code": 40401,
  "message": "NOT_FOUND_OR_EXPIRED"
}
```

---

## 7. HMAC 签名算法

### 7.1 服务端生成（POST /publish 时）

```
Input:
  shortCode: 随机 8 位字符串（A-Za-z0-9）
  expiryTimestamp: floor(Date.now() / 1000) + expiryHours * 3600
  SECRET: 环境变量 SHARE_HMAC_SECRET

Algorithm:
  message = shortCode + ":" + String(expiryTimestamp)
  signature = HMAC-SHA256(message, SECRET)   // hex 编码，小写
  url = "https://<domain>/s/" + shortCode + "?t=" + String(expiryTimestamp) + "&s=" + signature
```

### 7.2 服务端校验（GET /s/:shortCode 时）

```
Input:
  shortCode: 从 URL path 提取
  t: 从 query 提取
  s: 从 query 提取

Step 1: 验证 Date.now() / 1000 < t
Step 2: expectedSig = HMAC-SHA256(shortCode + ":" + t, SECRET)  // hex
Step 3: 常量时间比较 expectedSig == s
```

### 7.3 参考实现

**Node.js 服务端**：
```javascript
const crypto = require('crypto');

function generateSignature(shortCode, expiryTimestamp) {
  const message = `${shortCode}:${expiryTimestamp}`;
  return crypto
    .createHmac('sha256', process.env.SHARE_HMAC_SECRET)
    .update(message)
    .digest('hex');
}

function verifySignature(shortCode, expiryTimestamp, signature) {
  const expected = generateSignature(shortCode, expiryTimestamp);
  return crypto.timingSafeEqual(
    Buffer.from(expected),
    Buffer.from(signature)
  );
}
```

**App 端**（仅用于状态校验，不生成 URL）：
```typescript
// App 端不需要实现 HMAC，URL 由服务端返回
// 如需本地校验 URL 格式：
function validateShareUrl(url: string): boolean {
  const pattern = /^https:\/\/.+\/s\/[A-Za-z0-9]{8}\?t=\d+&s=[a-f0-9]{64}$/;
  return pattern.test(url);
}
```

---

## 8. 服务端处理流程摘要

### 8.1 POST /api/v1/share/publish

```
1. 解析 multipart
2. 校验 tripData JSON 合法性
3. 校验 photoCount 总和 == photos 数量
4. 校验 expiryHours 范围
5. EXIF 清洗（移除 GPS、设备信息）
6. 照片 → WebP 转码（375w + 750w 两档）
7. 生成 shortCode（8 位随机，冲突重试）
8. 签名 = HMAC-SHA256(shortCode + ":" + expiryTimestamp, SECRET)
9. 缓存 trip 元数据 + WebP URL（TTL = expiryHours）
10. 存储 WebP 文件（路径: /cache/{shortCode}/）
11. 返回 201 + URL
```

### 8.2 GET /s/:shortCode

```
1. 提取 shortCode, t, s
2. 校验签名 → 403
3. 校验过期 → 410
4. 查询缓存 → 404
5. 注入数据到 EJS 模板
6. 返回 HTML（Cache-Control: no-store）
```

### 8.3 缓存清理

```
Lazy: GET /s/:shortCode 发现过期 → 即时清除缓存 + 删除 WebP 文件
Cron: 每小时 → 扫描所有缓存条目 → 清除过期者
```

---

## 9. 请求/响应示例

### 9.1 完整的 publish 请求（HTTP 格式）

```
POST /api/v1/share/publish HTTP/1.1
Host: tp.app
Content-Type: multipart/form-data; boundary=----Boundary

------Boundary
Content-Disposition: form-data; name="tripData"
Content-Type: text/plain

{"tripId":"trip_abc123","tripName":"深圳湾周末骑行","totalDistance":12.5,"coverIndex":0,"createdAt":1714200000000,"nodes":[{"id":"node_001","title":"红树林公园","content":"下午三点到达，阳光正好...","poiName":"深圳湾红树林","photoCount":2,"mood":"惬意","tags":["骑行","日落"],"visitedAt":1714200000000,"nodeOrder":0},{"id":"node_002","title":"人才公园","content":"傍晚的灯光很美。","poiName":"深圳人才公园","photoCount":1,"mood":"感动","tags":["夜景"],"visitedAt":1714300000000,"nodeOrder":1}]}
------Boundary
Content-Disposition: form-data; name="photo_0"; filename="photo_0.jpg"
Content-Type: image/jpeg

<binary data>
------Boundary
Content-Disposition: form-data; name="photo_1"; filename="photo_1.jpg"
Content-Type: image/jpeg

<binary data>
------Boundary
Content-Disposition: form-data; name="photo_2"; filename="photo_2.jpg"
Content-Type: image/jpeg

<binary data>
------Boundary
Content-Disposition: form-data; name="expiryHours"
Content-Type: text/plain

168
------Boundary--
```

### 8.2 publish 响应

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "url": "https://tp.app/s/xK9mNz?t=1714800000&s=a7f2c9b3d1e4f5a6b7c8d9e0f1a2b3c4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0",
    "shortCode": "xK9mNz",
    "expiresAt": 1714800000
  }
}
```

### 8.3 H5 页面访问

```
GET /s/xK9mNz?t=1714800000&s=a7f2c9b3d1e4f5a6b7c8d9e0f1a2b3c4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0 HTTP/1.1
Host: tp.app
```

响应：完整 H5 HTML 页面（含内联 `window.__ROUTE_DATA__`）。

---

## 10. App 端对接清单

| # | 事项 | 说明 |
|---|------|------|
| 1 | `ApiEndpoints.SHARE_PUBLISH` | 常量 `='/api/v1/share/publish'` |
| 2 | `HttpTimeout.UPLOAD` | 复用现有 120s 超时 |
| 3 | 照片清洗 | publish 前调用 EXIF 清除工具（复用 AI feature 实现） |
| 4 | multipart 组装 | `http.MultipartBuilder` 构造 body |
| 5 | `photoCount` 计算 | 确保 `sum(nodes[].photoCount) === 实际照片数` |
| 6 | `expiryHours` 默认值 | 168（7 天） |
| 7 | 错误处理 | 按 4.5 节错误码处理，400xx → 提示用户检查数据；429/5xx → 允许重试 |

---

## 11. 附录：App 端 type 定义（建议新增到 `common/service/types.ets`）

```typescript
// ============ Share API Types ============

// POST /api/v1/share/publish 请求体中的 tripData
interface SharePublishRequest {
  tripId: string;
  tripName: string;
  totalDistance: number;
  coverIndex: number;
  createdAt: number;
  nodes: SharePublishNode[];
}

interface SharePublishNode {
  id: string;
  title: string;
  content: string;
  poiName: string;
  photoCount: number;
  mood: string;
  tags: string[];
  visitedAt: number;
  nodeOrder: number;
}

// POST /api/v1/share/publish 响应
interface SharePublishResponse {
  code: number;
  message: string;
  data: {
    url: string;
    shortCode: string;
    expiresAt: number;
  };
}

// GET /api/v1/share/:shortCode/status 响应
interface ShareStatusResponse {
  code: number;
  data?: {
    shortCode: string;
    expiresAt: number;
    remainingSeconds: number;
    publishedAt: number;
  };
  message?: string;
}
```
