# P08 临时分享链接后端 — 交接文档

> 收件人：负责后端的 Claude Code / 后端开发者
> 撰写日期：2026-04-27
> 关联前端代码：[feature/social-share/](../../frontend/entry/src/main/ets/feature/social-share/)
> 状态：方案已敲定（方案 1 — AGC Cloud Function + AGC Hosting），待实现

---

## 一、你要做什么（一句话版）

给 TravelPin 实现一个"临时分享链接"后端：前端把一段旅行（trip + nodes + 照片清单）打包发过来，你返回一条带过期时间和 HMAC 签名的短链，接收方在浏览器打开就能看预览页。链接 7 天后自动失效，用户可以主动撤销。

---

## 二、上下文（不要重复造轮子）

TravelPin 是鸿蒙地理位置旅行日记 App，**已经接入了 Huawei AGC**：

- **AGC Auth**：华为账号登录，前端已能拿到 `idToken` 和 `uid`
- **AGC Cloud Database**（Zone：`TravelPinZone`）：已有 `Travel` / `MemoryNode` 两张表，承载多设备同步
- **AGC Cloud Storage**：照片二进制按 `users/{uid}/travels/{travelId}/nodes/{nodeId}/{filename}` 存放
- **同步链路**：[references/documents/sync-architecture.md](../documents/sync-architecture.md) 描述了完整的离线优先 + 自动增量同步设计

**前端已存在的占位实现**（你要替换掉它后面对接的"虚假 URL"）：

- [SharePage.ets:13](../../frontend/entry/src/main/ets/feature/social-share/pages/SharePage.ets#L13) 硬编码 `https://tp.app/s/xK9mNz`，TODO 注释写着 `生成 HMAC-SHA256 签名链接`
- [QRCodeShare.ets:34-53](../../frontend/entry/src/main/ets/feature/social-share/components/QRCodeShare.ets#L34-L53) 占位 `generateShareLink()` 返回 `https://travelpin.example.com/share/${shortCode}`，且自己生成 8 位短码

**已有 backend/ 目录**（只放了 Qwen-VL AI 服务）：
- 端口 **8000** 已被 AI 服务占用
- AI 服务的 cloudflared 临时隧道域名重启就变（见 [memory: backend_qwenvl_constraints](../../memory/backend_qwenvl_constraints.md)）
- **不要**把分享服务塞进 AI 服务里，独立部署到 **8001** 端口

---

## 三、整体架构

```
鸿蒙 App (SharePage)
    │ 1. POST /api/share/create  (附 trip 快照 JSON + photoManifest)
    │    Authorization: Bearer <agc-id-token>
    ▼
[本地阶段: FastAPI / 上线阶段: AGC Cloud Function]
    │ 2. 生成 shortCode + HMAC-SHA256 签名，写入 Cloud DB
    │ 3. 返回 https://share.travelpin.app/s/{code}.{sig8}
    ▼
鸿蒙 App  → systemShare.share() 把 URL 发到微信/微博/复制剪贴板

接收方在浏览器打开：
    https://share.travelpin.app/s/{code}.{sig8}
        │
        ▼
[AGC Hosting 静态 H5]   解析 URL → fetch /api/share/{code}.{sig8}
        │
        ▼
[Cloud Function]   校验 expire / revoked / sig → 返回 trip JSON + 照片签名 URL
        │
        ▼
浏览器渲染地图 + 路线 + 照片缩略图 + AI 文案
```

**已敲定的设计选择（不要重新讨论，直接按此实现）**：

1. **快照模式**：分享时把 trip + nodes + photoManifest 序列化复制到 ShareLink 表里。用户后续编辑/删除原 trip **不影响**已分享内容。理由：解耦撤销点、避免分享后用户误删导致链接失效、避免接收方看到中途修改的状态。
2. **AGC 基建复用**：照片不重新存，引用已有 Cloud Storage 路径，每次 GET 时签发短 TTL 临时下载凭证。
3. **HMAC 必备**：8 位 shortCode 容易被遍历，必须 `shortCode + sig` 两段。sig 用服务端密钥 HMAC-SHA256 算，前端拿到的链接形如 `https://share.travelpin.app/s/{code}.{sig8}`。
4. **本地原型先跑通，再迁 AGC**：演示阶段用 FastAPI + SQLite 本地起 service，AGC 上架前再改成 Cloud Function。业务逻辑同构、改的只是适配层。

---

## 四、数据模型

### 4.1 `ShareLink` 表

| 字段 | 类型 | 说明 |
|---|---|---|
| `shortCode` | string(8), PK | URL 安全字符集 `[A-Za-z0-9_-]`，避开 `0/O/l/1` 等易混字符 |
| `ownerUid` | string | 创建者 uid（AGC Auth 一致） |
| `tripCloudId` | string | 引用 `Travel.cloudId`，仅审计用，渲染走快照 |
| `snapshotJson` | text | trip + nodes 快照，结构见 §4.2 |
| `photoManifest` | text(JSON array) | 云存储对象 key 数组（**不能有** `file://` 本地路径） |
| `createdAt` | int64 | ms 时间戳 |
| `expireAt` | int64 | `createdAt + expireDays * 86_400_000` |
| `revoked` | bool | 用户主动撤销 |
| `viewCount` | int | 累计访问数（每次 GET +1） |
| `sig` | string(8) | `b64url(HMAC_SHA256(SERVER_KEY, shortCode \|\| ownerUid \|\| str(expireAt)))[:8]` |
| `consentVersion` | string | 前端创建时透传的同意版本号（PIPL 留痕） |

**索引**：
- `(ownerUid, createdAt DESC)` — 支撑 §5.4 "我的分享"
- `expireAt` — 支撑过期清扫定时任务

### 4.2 `snapshotJson` 结构（与前端约定）

```jsonc
{
  "v": 1,                            // schema 版本，兼容用
  "trip": {
    "name": "西北 7 日",
    "startDate": "2026-04-01",
    "endDate": "2026-04-07",
    "coverPhoto": "users/abc/travels/21/cover.jpg"
  },
  "nodes": [
    {
      "title": "鸣沙山日落",
      "lat": 40.0883,                 // 是否降精度由前端在快照时决定，后端不处理
      "lng": 94.6764,
      "poiName": "鸣沙山",
      "mood": "amazed",
      "tags": ["sunset", "desert"],
      "content": "AI 生成的文案……",
      "photos": ["users/abc/travels/21/nodes/28/photo_xxx.jpg"],
      "nodeOrder": 0,
      "createdAt": 1714000000000
    }
  ]
}
```

> 前端字段命名取自 [common/service/types.ets:109,193](../../frontend/entry/src/main/ets/common/service/types.ets#L109)（`Trip` / `MemoryNode`），保持一致。

---

## 五、API 规范

所有接口前缀 `/api/share`。除 §5.2 外都要 `Authorization: Bearer <agc-id-token>`。

### 5.1 `POST /api/share/create`

**Request body**:
```json
{
  "tripCloudId": "abc-xyz",
  "expireDays": 7,
  "snapshot": { /* §4.2 */ },
  "photoManifest": ["users/abc/travels/21/nodes/28/photo_xxx.jpg"],
  "consentVersion": "share-v1-2026-04"
}
```

**Response 200**:
```json
{
  "shortCode": "kX9mNz4Q",
  "sig": "a3f1e8b2",
  "url": "https://share.travelpin.app/s/kX9mNz4Q.a3f1e8b2",
  "expireAt": 1714604800000
}
```

**实现要点**：
1. 校验 `Authorization` 拿到 `ownerUid`
2. **跨用户照片引用防御**：`photoManifest` 里每个 key 必须以 `users/{ownerUid}/` 开头，否则 403
3. `expireDays ∈ {1, 7, 30}`，其它值 422
4. `snapshotJson` 序列化后大小 ≤ **256 KB**，photoManifest ≤ **50** 张
5. `shortCode` 用 `secrets.token_urlsafe(6)` → 截到 8 字符；查重，碰撞重试最多 3 次
6. `sig = b64url(hmac_sha256(SERVER_KEY, shortCode || ownerUid || str(expireAt)))[:8]`
7. **限流**：每个 uid 每天最多 50 条 → 超过返回 429（用 SQLite 计数即可，不需要 Redis）

**错误码**：
- 401 缺/错 token
- 403 photoManifest 引用了非自己的对象
- 422 expireDays / snapshot schema 非法、size 超限
- 429 限流

### 5.2 `GET /api/share/{code}.{sig}` （**公开访问，无 token**）

**Response 200**:
```json
{
  "snapshot": { /* §4.2 */ },
  "photoUrls": {
    "users/abc/travels/21/nodes/28/photo_xxx.jpg": "https://agcstorage.../signed?token=..."
  },
  "expireAt": 1714604800000,
  "viewCount": 17
}
```

**实现要点**：
1. 解析 `code.sig`，查表
2. **校验顺序**：`revoked` → `expireAt > now` → HMAC 重算对比 → 通过
3. 任何一步失败统一返回 `404 {"error":"link_expired_or_invalid"}`，**不要**对外区分"过期"和"撤销"，防探测
4. 对每个 photoManifest key 调 AGC Cloud Storage `getDownloadURL`，TTL = `min(expireAt - now, 3600s)`
5. `viewCount += 1` 必须用原子 SQL（`UPDATE ... SET viewCount = viewCount + 1`），不要先查再写
6. **CORS**：`Access-Control-Allow-Origin: https://share.travelpin.app`（再加上你的本地 H5 调试源）
7. **限流**：30 req/min/IP，防爬

### 5.3 `POST /api/share/{code}/revoke`

**Request**: 空 body，要 `Authorization`
**Response 200**: `{"revoked": true}`
**实现**：校验 `ownerUid` 等于该 share 的 owner，否则 403。idempotent — 重复撤销也返回 200。

### 5.4 `GET /api/share/mine`

**Response 200**:
```json
[
  {"shortCode": "...", "tripCloudId": "...", "expireAt": ..., "revoked": false, "viewCount": 17, "createdAt": ...}
]
```
按 `createdAt DESC` 取最近 50 条。**不要**返回 `snapshotJson`（太大），只返回元信息。

### 5.5 `GET /health`

无 token，返回 `{"ok": true}`。**不要**返回内部状态（DB 大小、行数等）。

---

## 六、安全/合规要点（每条都不可省）

1. **`SHARE_HMAC_KEY`**：32 字节随机串，从环境变量读，**不要硬编码、不要进 git**。本地用 `.env`，`.env` 加到 `.gitignore`。生成方式：`python -c "import secrets;print(secrets.token_urlsafe(32))"`
2. **跨用户照片引用防御**：见 §5.1 第 2 条。这是关键防线，A 能借自己的 share 把 B 的照片 leak 出去就是大事故。
3. **照片签名 URL TTL ≤ 1 小时**：即使 share 还有 6 天才过期，单次拿到的图片 URL 也很快失效。攻击者拿到一次访问后没法长期外链。
4. **PIPL 单独同意留痕**：`consentVersion` 必须落库。前端职责是弹"分享内容将对接收方公开（位置、照片、文案）"对话框，但后端要把版本号存好备查。
5. **日志脱敏**：日志里 `snapshotJson` **不打全文**，只打 `shortCode + ownerUid + size_bytes`。
6. **HTTPS**：本地原型可裸 HTTP，**部署到任何公网环境前必须 HTTPS**。AGC Hosting 默认 HTTPS。
7. **不要 retry-on-429 / retry-on-5xx**：失败语义直接交给前端处理。
8. **HMAC 算法固定 SHA-256**：不要偷懒用 MD5 / SHA1。
9. **过期清扫**：`expireAt < now - 30 days` 的脏数据每天清一次（本地阶段写个 cron 脚本，AGC 阶段用定时触发 Function）。

---

## 七、推荐技术栈与目录

### 7.1 本地原型阶段

```
backend/share_service/
├── main.py                  # FastAPI app 入口
├── routers/
│   ├── share.py             # §5.1-5.4
│   └── health.py            # §5.5
├── core/
│   ├── config.py            # 读环境变量
│   ├── security.py          # HMAC 签发/校验、shortCode 生成
│   ├── auth.py              # AGC token 验证（演示阶段可 mock）
│   └── storage.py           # AGC Cloud Storage 签名 URL（同 mock）
├── db/
│   ├── schema.sql           # ShareLink DDL
│   └── repository.py        # CRUD + 限流计数
├── models/
│   └── share.py             # pydantic 请求/响应
├── tests/
│   ├── test_security.py
│   └── test_share_api.py
├── scripts/
│   └── purge_expired.py     # cron 清扫
├── requirements.txt
├── .env.example
└── README.md                # 启动方式 + 环境变量说明
```

`requirements.txt`：
```
fastapi==0.110.*
uvicorn[standard]==0.27.*
pydantic==2.6.*
python-multipart==0.0.9
httpx==0.27.*
PyJWT==2.8.*
```

启动：
```bash
SHARE_HMAC_KEY=$(python -c "import secrets;print(secrets.token_urlsafe(32))") \
DB_PATH=./share.db \
uvicorn backend.share_service.main:app --host 0.0.0.0 --port 8001 --reload
```

> **端口选 8001**，避开 AI 服务的 8000。

### 7.2 AGC 迁移阶段

把 `routers/share.py` 每个 handler 改写成 AGC Cloud Function 入口（参考 [AGC Cloud Function 文档](https://developer.huawei.com/consumer/cn/agconnect/cloud-function/)）。**业务逻辑文件 `core/security.py` / `db/repository.py` / `models/` 不动**，只换适配层：

| 适配层 | 本地原型 | AGC 阶段 |
|---|---|---|
| Auth | 手动验 JWT | AGC Function 入参里的 `context.uid` |
| DB | SQLite | AGC Cloud Database (`@hw-agconnect/cloud-server` ObjectTypeInfo) |
| Storage 签名 URL | mock 返回 cloud key | AGC Cloud Storage SDK `getDownloadURL` |
| HTTP 入口 | FastAPI router | AGC Function HTTP trigger |

业务核心代码 90%+ 复用，迁移工作量预计 ≤ 1 天。

---

## 八、与前端 ArkTS 的对接点

**这部分前端做，但你要保证接口形态匹配前端的调用方式**：

### 8.1 [QRCodeShare.ets:34](../../frontend/entry/src/main/ets/feature/social-share/components/QRCodeShare.ets#L34) `generateShareLink()`

会改成：
1. 从 `RdbDataService` 拿 trip + nodes + photoManifest，组装 §4.2 的 snapshotJson
2. 调 `POST /api/share/create`，header 带 `Authorization: Bearer ${authService.getIdToken()}`
3. 拿到 `url` 字段直接给 systemShare 用

### 8.2 [SharePage.ets:22](../../frontend/entry/src/main/ets/feature/social-share/pages/SharePage.ets#L22)

`aboutToAppear` 里的 TODO 改成调用 §8.1 的 `generateShareLink()`，把 `expireDays` 作为 1/7/30 三档参数传进去。

### 8.3 你需要在前端 [common/api/ApiEndpoints.ets](../../frontend/entry/src/main/ets/common/api/ApiEndpoints.ets) 里新增

```ts
SHARE_SERVICE_BASE_URL = "http://172.18.x.x:8001"  // 演示阶段
SHARE_SERVICE_BASE_URL_PROD = "https://share.travelpin.app/api"  // 上架后
```

---

## 九、H5 静态分享页（前端做，你给接口配套）

**域名**：`share.travelpin.app`（先用 AGC Hosting 默认域名，正式上线再绑）
**路径**：`/s/{code}.{sig}` → SPA，从 URL 解析后调 §5.2 渲染

H5 会向你索要：
- §5.2 必须支持浏览器 CORS
- 错误状态前端要明确显示：`404` → "链接已失效"，`429` → "访问太频繁"
- 照片签名 URL **必须能直接被 `<img src>` 加载**（即 AGC 签名 URL 不要带强制下载头）

---

## 十、验收标准（DoD）

- [ ] 单元测试覆盖 `core/security.py` ≥ 90%（HMAC 签发/验证、过期判定、撤销判定、shortCode 唯一性）
- [ ] e2e 测试：create → get → revoke → get 应得 404 的完整链路
- [ ] 限流测试：连续 51 次 create，第 51 次得 429
- [ ] 跨用户防御测试：A 用户 photoManifest 里塞 B 的对象 key 应被 403
- [ ] HMAC 篡改测试：把 sig 改一个字节，GET 必须返回 404
- [ ] 本地能用 `curl` 跑通 §5.1-5.5 全部 API
- [ ] 用真实 trip 数据手动测：浏览器 `curl GET /api/share/{code}.{sig}` 看到的 photoUrls 是可访问的真实 AGC 签名 URL
- [ ] `.env.example` 列出所有必需环境变量并附说明
- [ ] `share_service/README.md` 让一个不熟悉这个项目的人 5 分钟跑起来

---

## 十一、不要做的事

- ❌ 不要把照片二进制存到本地磁盘 / DB —— 永远引用 AGC Cloud Storage
- ❌ 不要给 §5.2 加鉴权 —— 它就是设计成公开访问的
- ❌ 不要把 `revoked` 和 `expired` 的差别暴露给外部 —— 一律 404
- ❌ 不要在这个 service 里再实现一份 trip CRUD —— 只读 snapshotJson，不要触碰原 trip 表
- ❌ 不要复用 AI 服务的 8000 端口或它的数据库 —— 完全独立部署
- ❌ 不要 retry-on-429 / retry-on-5xx —— 失败语义交给前端
- ❌ 不要在 HMAC / sig 算法上偷懒 —— 必须 SHA-256，不接受 MD5/SHA1
- ❌ 不要把 `SHARE_HMAC_KEY` 写代码里 —— 永远走环境变量
- ❌ 不要在响应里返回完整 `snapshotJson` 给 §5.4（"我的分享"）—— 太大

---

## 十二、第一周建议工作顺序

| Day | 内容 |
|---|---|
| 1 | 搭骨架：`requirements.txt`、`config.py`、`schema.sql`、`core/security.py` + 单测（HMAC、shortCode 生成） |
| 2 | `db/repository.py` + SQLite + §5.1 `POST /create` |
| 3 | §5.2 `GET /:code.:sig`，照片签名 URL 先 mock 成 cloud key |
| 4 | §5.3 revoke、§5.4 mine、§5.5 health |
| 5 | 限流、跨用户防御、e2e 测试，写 `share_service/README.md` |
| 6-7 | 和前端联调，把 mock 的 storage 签名 URL 换成真实 AGC SDK 调用 |

---

## 附录 A：关键文件参考

- 前端占位：[QRCodeShare.ets:34-65](../../frontend/entry/src/main/ets/feature/social-share/components/QRCodeShare.ets#L34-L65), [SharePage.ets:22-35](../../frontend/entry/src/main/ets/feature/social-share/pages/SharePage.ets#L22-L35)
- 已有云同步架构：[references/documents/sync-architecture.md](../documents/sync-architecture.md)
- AGC Cloud Storage 路径规则：`users/{uid}/travels/{travelId}/nodes/{nodeId}/{filename}`，定义在 [common/auth/CloudStorageService.ets](../../frontend/entry/src/main/ets/common/auth/CloudStorageService.ets)
- 前端数据模型：[common/service/types.ets](../../frontend/entry/src/main/ets/common/service/types.ets) 中的 `Trip` / `MemoryNode`
- 现有 backend 目录：[backend/](../../backend/)（只有 AI 服务，分享服务建议放 `backend/share_service/`）

## 附录 B：AGC 迁移检查清单

- [ ] `core/auth.py` 改用 AGC Function `context.uid`
- [ ] `db/repository.py` 改用 `@hw-agconnect/cloud-server` ObjectTypeInfo
- [ ] `core/storage.py` 改用 AGC Storage SDK
- [ ] `main.py` 拆成多个 Function 入口
- [ ] AGC 控制台配置：HTTP 触发器、自定义域名 `share.travelpin.app`、CORS 白名单
- [ ] `SHARE_HMAC_KEY` 从 AGC 控制台环境变量配置
- [ ] 配过期清扫：定时触发 Function，每天清一次 `expireAt < now - 30d`

## 附录 C：常见问题预答

**Q：为什么 sig 只取 8 字节，不全量返回 32 字节？**
A：HMAC 截断是标准做法（参考 RFC 4226 HOTP），8 字节即 64 位熵足够防遍历，URL 也短。攻击者爆破 64 位空间不现实。

**Q：要不要支持密码保护的 share？**
A：本期不做。如果后续要加，复用 sig 字段额外存一个 `bcrypt(password)`，§5.2 检测到该字段则要求前端再传一次密码。

**Q：snapshot 里能不能塞 base64 缩略图节省一次照片请求？**
A：不要。会让 snapshotJson 暴涨突破 256KB 上限，且 §5.2 响应也会变大。坚持"元数据归元数据、二进制归 Cloud Storage"。

**Q：viewCount 并发自增会不会丢更新？**
A：用原子 SQL `UPDATE ... SET viewCount = viewCount + 1` 即可，SQLite 单写入串行天然安全；AGC Cloud DB 阶段用其原子操作 API。
