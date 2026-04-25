# TravelPin 云同步系统 Code Review

> 生成日期：2026/04/25
> 代码版本：incremental-dev-20260423 分支（已应用修改）
> 审核范围：前端云同步相关所有代码

---

## 一、架构总览

### 1.1 数据分层

```
Page Layer
  NodeEditPage / TripEditPage / ProfileView
        │
        ▼
RdbDataService（业务逻辑 + 同步编排）
  ├─ nodeRepo / travelRepo  ──→  RdbHelper  ──→  RDB 数据库
  ├─ enqueueSync / enqueueSyncSilently  ──→  RdbHelper（sync_queue 表）
  ├─ uploadNodePhotosToCloud / migrateNodePhotosToNewTravel  ──→  CloudStorageService
  └─ SyncManager（云端同步编排）
        │
        ├─ CloudSyncService  ──→  AGC CloudDB（实体元数据）
        └─ CloudStorageService  ──→  AGC Cloud Storage（照片文件）
```

### 1.2 两套同步路径

**路径 A（sync queue）：**
每次 CRUD 操作的元数据变化写入 `sync_queue` 表。`pushLocalNow()` 顺序处理队列记录，依次同步到云端。适合增量同步。

**路径 B（syncAllLocalToCloud）：**
遍历所有本地数据，全量推送到云端。包含：先 upsert（含空 manifest）、上传照片、re-upsert（含正确 manifest）。适合兜底同步。

---

## 二、核心数据结构

### 2.1 数据库表（travels / memory_nodes）

| 关键字段 | 说明 |
|---------|------|
| `cloud_id` | 云端 ID（如 `node_123`），创建时为空，上传后写入 |
| `sync_status` | `pending_create` / `pending_update` / `pending_delete` / `synced` |
| `photo_manifest` | JSON 数组，云端文件相对路径列表，用于下载照片 |
| `deleted_at` | 软删除时间戳（毫秒），> 0 表示已删除 |
| `version` | 乐观锁版本号 |

### 2.2 sync_queue 表

| 字段 | 说明 |
|------|------|
| `entity_type` | `travel` 或 `memory_node` |
| `entity_id` | 本地 RDB ID |
| `operation` | `upsert` 或 `delete` |
| `payload` | JSON 字符串，包含完整的实体数据和 `photoManifest` |
| `created_at` | 入队时间（毫秒），按 FIFO 顺序处理 |

### 2.3 照片 cloud path 格式

```
travels/{travelId}/nodes/{nodeId}/{filename}
```

`travelId = -1` 表示 UNCATEGORIZED（未分类）节点。

---

## 三、各层函数详解

### 3.1 RdbHelper — 数据库基础层

| 函数 | 作用 |
|------|------|
| `initDatabase(context)` | 初始化 RDB Store；返回后数据库才可用 |
| `getStore()` | 获取 RDBStore；未初始化时触发 initDatabase 并 await |
| `getPendingSyncQueueItems()` | 按 `created_at` ASC 读取 sync_queue |
| `enqueueSyncItem(entity, id, op, payload)` | 写入 sync_queue |
| `removeSyncItems(entity, id)` | 删除某实体的旧记录（保证同一实体只有一条） |
| `clearSyncQueue()` | 清空 sync_queue（拉取云端前调用） |
| `setSyncState(key, value)` | 写入 app_sync_state（用于记录 last_push_at / last_pull_at） |

### 3.2 RdbDataService — 业务逻辑层

#### 3.2.1 `enqueueSync` vs `enqueueSyncSilently`

```typescript
enqueueSync(entity, id, op, payload):
  1. removeSyncItems(entity, id)      // 删除旧记录
  2. enqueueSyncItem(entity, id, op, payload)  // 写入新记录
  3. 如果 online → pushLocalNow()    // fire-and-forget

enqueueSyncSilently(entity, id, op, payload):
  1. removeSyncItems(entity, id)
  2. enqueueSyncItem(entity, id, op, payload)
  // 不触发 pushLocalNow（用于 deleteTravel 等批量操作）
```

#### 3.2.2 照片相关

```typescript
syncNodePhotosToCloud(travelId, nodeId, photos, previousTravelId?):
  → fire-and-forget 调用 uploadNodePhotosToCloud

uploadNodePhotosToCloud(travelId, nodeId, photos, previousTravelId?):
  如果是迁移（previousTravelId !== travelId）：
    → 直接上传本地文件到新云目录（不下载）
    → 上传完成后 fire-and-forget 删除旧目录照片
  否则（普通上传）：
    → 逐张上传到当前云目录
  返回是否全部成功

migrateNodePhotosToNewTravel(travelId, nodeId, photos, oldTravelId):
  → fire-and-forget 调用 uploadNodePhotosToCloud
```

#### 3.2.3 `buildPhotoManifest`

```typescript
buildPhotoManifest(travelId, nodeId, photos): string
  → 构造 cloud paths 数组：`travels/{travelId}/nodes/{nodeId}/{filename}`
  → 返回 JSON.stringify(cloudPaths[])
```

### 3.3 CloudSyncService — 云数据库（AGC CloudDB）

使用 `cloudDatabase.DatabaseZone`：

| 函数 | 作用 |
|------|------|
| `ensureReady()` | 初始化 zone（TravelPinZone） |
| `upsertTravel(payload)` | 写入/更新云端路线元数据 |
| `upsertMemoryNode(payload)` | 写入/更新云端节点（含 `photoManifest`） |
| `deleteTravel / deleteMemoryNode` | 软删除（upsert deletedAt） |
| `hardDeleteTravelByCloudId / hardDeleteMemoryNodeByCloudId` | 永久删除（query → delete） |
| `fetchTravels / fetchMemoryNodes` | 拉取用户全部数据（含 photoManifest） |

### 3.4 CloudStorageService — 云文件存储（AGC Cloud Storage）

使用 `cloudStorage.StorageBucket`：

| 函数 | 作用 |
|------|------|
| `ensureReady()` | 初始化 bucket，AGC hwid 登录 |
| `uploadFile(localPath, cloudPath)` | 上传到云端（B BACKGROUND 模式） |
| `downloadFile(cloudPath, localPath)` | 下载到本地（B BACKGROUND 模式） |
| `deleteFile(cloudPath)` | 删除云端文件 |
| `deleteDirectoryRecursively(cloudPath)` | 递归删除目录 |
| `listFiles(cloudPath)` | 列出目录下文件 |
| `uploadNodePhoto(travelId, nodeId, localPath)` | 上传节点照片 |
| `deleteNodePhoto(travelId, nodeId, localPath)` | 删除节点照片 |
| `copyNodePhoto(fromTravelId, toTravelId, nodeId, localPath)` | 云端迁移照片（下载→上传→删除源） |
| `downloadNodePhotoToSandbox(cloudPath)` | 下载云端照片到沙箱，返回 `file://` 路径 |
| `buildNodePhotoPath(travelId, nodeId, localPath)` | 构造 cloud path：`travels/{travelId}/nodes/{nodeId}/{filename}` |

---

## 四、各操作函数调用链

### 4.1 创建节点（在线）

```
NodeEditPage.handleSave()
  → RdbDataService.createNode({ travelId, title, photos, ... })

RdbDataService.createNode():
  1. nodeRepo.createNode()     → 写入 DB（photo_manifest='[]'，sync_status='pending_create'）
  2. buildPhotoManifest()       → 构建正确 cloud paths（travelId + nodeId + filename）
  3. enqueueSync()            → 写入 sync_queue（payload.photoManifest = 正确 cloud paths）
  4. 如果 online: syncNodePhotosToCloud()  → fire-and-forget（上传照片，不更新 manifest）

最终效果：
  ✓ sync_queue payload 的 photoManifest 从一开始就是正确的 cloud paths
  ✓ pushLocalNow → handleItem → upsertMemoryNode → cloudDB 的 manifest 正确
  ✓ 照片异步上传
```

### 4.2 编辑节点（含换路线）

```
NodeEditPage.handleSave() with changed travelId
  → RdbDataService.updateNode(nodeId, { travelId: newTravelId, ... })

RdbDataService.updateNode():
  1. repo.updateNode()        → 写 DB（travelId → newTravelId）
  2. 如果改了 travelId:
       a. reorderNodes(oldTravelId)        → 重排原路线节点顺序
       b. 如果有新路线+有照片:
            buildPhotoManifest()            → 新 cloud paths
            await updatePhotoManifest()    → 立即写入本地 DB  ← 关键！
            migrateNodePhotosToNewTravel() → fire-and-forget（上传到新目录）
  3. buildPhotoManifest()    → enqueueSync 的 payload 含正确的 manifest
  4. enqueueSync()           → 写入 sync_queue

最终效果：
  ✓ 本地 DB photo_manifest 立即更新为新 cloud paths（await updatePhotoManifest）
  ✓ sync_queue payload 的 manifest 也是正确的新 cloud paths
  ✓ pushLocalNow → handleItem → cloudDB manifest 正确
```

### 4.3 创建/编辑节点（离线）

```
离线时：步骤 3 enqueueSync 完成（写入 sync_queue）
       步骤 4 syncNodePhotosToCloud 跳过（不上传照片）

重联网后 triggerNow():
  pushLocalNow():
    handleItem → upsertMemoryNode → cloudDB manifest 正确
    syncNodePhotosForUpload → 上传照片 → 更新 manifest → re-upsert → manifest 双重正确
```

### 4.4 删除路线

```
TripEditPage.deleteCurrentTrip()
  → RdbDataService.deleteTravel(tripId)

RdbDataService.deleteTravel():
  1. softDeleteTravel():  travel deleted_at=now，节点 travelId → -1（UNCATEGORIZED）
  2. 对每个节点:
       如果有照片: migrateNodePhotosToNewTravel()  → 上传到新目录（-1），fire-and-forget 删除旧目录
       enqueueSyncSilently()                   → 写入 sync_queue（payload 含新 manifest）
  3. enqueueSyncSilently('travel', 'delete', payload)
  4. 如果 online: pushLocalNow()（fire-and-forget）

最终效果：
  ✓ 节点迁移到 -1 后，payload 的 manifest 指向新目录（-1），不是旧目录
  ✓ pushLocalNow → handleItem → cloudDB manifest 指向 -1 目录
  ✓ 旧目录照片的删除是 fire-and-forget，不阻塞主流程
```

### 4.5 删除节点

```
handleDelete()
  → RdbDataService.deleteNode(nodeId)

RdbDataService.deleteNode():
  1. PhotoPickerUtil.deletePhotos()     → 删本地沙箱文件
  2. softDeleteNode(): deleted_at=now，sync_status='pending_delete'
  3. reorderNodes()                    → 重排同路线节点顺序
  4. 如果 online+有照片: syncDeletedNodePhotosToCloud()  → fire-and-forget 删除云端文件
  5. enqueueSync / enqueueSyncSilently  → 写入 sync_queue

handleItem（delete 操作）:
  → 从 node.travelId 对应的云目录删除照片
  → hardDeleteMemoryNodeByCloudId()
```

### 4.6 ProfileView「上传本地」

```
runPushSync()
  → SyncManager.pushAllLocalToCloud()
  → syncAllLocalToCloud()

syncAllLocalToCloud():
  对每个 local node（非 deleted）:
    upsertMemoryNode()              ← 先写 metadata（此时 manifest 可能='[]'）
    syncNodePhotosForUpload(node) ← 上传照片 + 更新 manifest
    upsertMemoryNode(updatedPayload)  ← 再次写 metadata（manifest=正确 cloud paths）
    updateSyncMetadata()          ← sync_status='synced'
```

### 4.7 ProfileView「下载云端」

```
runPullSync()
  → SyncManager.pullAllCloudToLocal()
  → clearSyncQueue()  ← ⚠ 先清空 sync_queue！
  → replaceLocalWithCloud()

replaceLocalWithCloud():
  拉取云端 travels → upsertFromCloud
  拉取云端 nodes → syncNodePhotosForDownload → upsertFromCloud
  清理本地多余数据
```

---

## 五、SyncManager 关键函数

### 5.1 `triggerNow()` — 已废弃

`triggerNow()` 已被移除（登录不再触发自动同步）。原逻辑：

```typescript
// 已删除：EntryAbility.onCreate 中不再调用
static async triggerNow(): Promise<void> {
  await pushLocalNow()           // ① 先推送本地到云端
  await replaceLocalWithCloud()  // ② 再拉取云端到本地
}
```

手动同步入口：
- **上传本地**：`SyncManager.pushAllLocalToCloud()` → `syncAllLocalToCloud()`
- **下载云端**：`SyncManager.pullAllCloudToLocal()` → `replaceLocalWithCloud()`

### 5.2 `pushLocalNow()` — 处理 sync queue

```typescript
while ((items = getPendingSyncQueueItems()).length > 0) {
  for (each item) {
    await handleItem(item)   // upsert 或 delete
  }
  items = getPendingSyncQueueItems()  // 处理期间新增的记录
}
```

### 5.3 `handleItem()` — 处理单条记录

| entityType | operation | 处理 |
|-----------|-----------|------|
| travel | upsert | upsertTravel → updateSyncMetadata |
| travel | delete | 删除云端照片 → hardDeleteTravelByCloudId → updateSyncMetadata |
| memory_node | upsert | upsertMemoryNode → updateSyncMetadata |
| memory_node | delete | 删除云端照片 → hardDeleteMemoryNodeByCloudId → updateSyncMetadata |

### 5.4 `syncNodePhotosForUpload()` — 上传节点照片

```typescript
// 遍历本地 photos，构建 cloud paths
expectedCloudFiles = {}   // 应该存在于云端的文件集合
manifestPaths = []       // manifest 路径列表

for (each localPhoto):
  cloudPath = buildNodePhotoPath(travelId, nodeId, localPhoto)
  expectedCloudFiles.add(cloudPath)
  manifestPaths.push(cloudPath)
  uploadFile(localPhoto, cloudPath)  // 逐张上传

// 清理云端多余文件（不在 expectedCloudFiles 中的）
cloudFiles = listFiles(cloudDir)
for (each cloudFile):
  if NOT in expectedCloudFiles: deleteFile(cloudFile)

// 上传完成后：manifest 写入本地 DB + 更新 node.photoManifest
manifest = JSON.stringify(manifestPaths)
updatePhotoManifest(node.id, manifest)
node.photoManifest = manifest
```

### 5.5 `syncNodePhotosForDownload()` — 下载节点照片

```typescript
manifestPaths = parsePhotoManifest(node.photoManifest)
// 如果 manifest 为空，fallback 到 listFiles(cloudDir)

for (each cloudPath in manifestPaths or listFiles):
  localPath = downloadNodePhotoToSandbox(cloudPath)  // 下载到沙箱
  downloadedPhotos.push(localPath)

node.photos = downloadedPhotos   // 本地路径（file://...）
```

**注意：** `node.photoManifest` 保持为 cloud paths（相对路径），`node.photos` 为本地沙箱路径。这是正常设计，cloudDB 存 cloud paths，本地存本地路径。

### 5.6 `replaceLocalWithCloud()` — 拉取云端到本地

```
① 云端 travels:
  deletedAt > 0 → 物理删除本地
  否则 → upsertFromCloud

② 本地 travels:
  云端没有且非 deleted → 物理删除本地

③ 云端 nodes:
  UNCATEGORIZED (travelId=-1) → 不查本地 travel 映射，直接进入下载流程
  有 travelId → 查本地是否有对应 travel
    → 无 → skip（本地无对应路线，跳过）
    → 有 → syncNodePhotosForDownload → upsertFromCloud
  deletedAt > 0 → 物理删除本地

④ 本地 nodes:
  云端没有 且 非 UNCATEGORIZED → 物理删除本地
```

---

## 六、问题分析（最终结论）

经过逐一讨论，以下是最终结论：

### 6.1 ✅ 已修复：登录不再触发自动同步

**设计决策：** 离线改动不自动上传是设计意图，登录不应触发自动同步。

**修改内容：**
- 移除了 `EntryAbility.onCreate()` 中 `restoreSession().then()` 里的 `void SyncManager.triggerNow()` 调用
- 移除了 EntryAbility 中不再使用的 `SyncManager` import

**修改后行为：**
- 登录只建立云端连接 + 更新状态文字，不触发任何同步
- `enqueueSync` 中的 `if (online) pushLocalNow()` 保留，用于**在线时的增量自动同步**（正常体验）
- 离线改动保留在 sync queue，由用户在个人页手动点「上传本地」推送

### 6.2 ✅ manifest 在所有主流程中均正确

经过详细代码分析，manifest 在各流程中均保持正确：

**createNode：** `buildPhotoManifest()` 在 `enqueueSync()` 之前调用，sync queue payload 从一开始即包含正确的 cloud paths。`handleItem` → `upsertMemoryNode` 将正确的 manifest 写入 cloudDB。✓

**updateNode（换路线）：** 迁移时 `buildPhotoManifest()` 后 `await updatePhotoManifest()` 立即将正确的 manifest 写入本地 DB。sync queue payload 也包含正确的 manifest。✓

**结论：** manifest 在 sync queue + cloudDB 的主流程中始终正确。`syncNodePhotosToCloud` 的 fire-and-forget 异步上传不影响 manifest 的正确性。

### 6.3 ✅ deleteTravel 迁移方向正确

节点从旧路线迁移到 UNCATEGORIZED（travelId=-1）后，manifest 指向新目录（-1），而非旧目录。`handleItem` 删除时从 -1 目录删除照片，逻辑正确。

### 6.4 ✅ UNCATEGORIZED 节点正常下载

之前认为 UNCATEGORIZED 节点被跳过不下载是错误的。

实际行为（`replaceLocalWithCloud` 第 316-363 行）：

```typescript
if (travelCloudId === TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID) {
  node.travelId = TravelSpecialValues.UNCATEGORIZED_TRAVEL_ID
} else {
  // 有 travelId → 查本地 travelId 映射
}
// ↓ 以下对所有节点都会执行（包括 UNCATEGORIZED）：
activeCloudNodeIds.add(node.cloudId)
syncNodePhotosForDownload(node)  // 用 travelId=-1 构造云目录路径，正常下载
upsertFromCloud(node)            // 元数据写入本地 DB
```

UNCATEGORIZED 节点和其他节点一样，能够正常下载元数据和照片。`syncNodePhotosForDownload` 没有对 UNCATEGORIZED 做任何特殊跳过处理，只是用 `travelId=-1` 去找云端目录。

### 6.5 ⚠️ clearSyncQueue 符合设计意图，但缺 UX 提示

`pullAllCloudToLocal()` 会先 `clearSyncQueue()` 清空所有待同步记录。这是符合设计意图的——用户选择用云端数据覆盖本地，离线改动应该先手动上传。

**但缺 UX 确认：** 如果 sync queue 非空（有待推送的本地改动），用户点击「下载云端」时没有确认对话框，离线改动会**静默丢失**。

**建议：** 在 `pullAllCloudToLocal` 执行前检查 sync queue 是否为空，非空则弹出确认框：

```
"本地有 N 项未同步改动。下载云端会覆盖这些本地改动。
  - 先上传再下载（推荐）
  - 仅下载（本地改动会丢失）
  - 取消"
```

### 6.6 🐛 死代码：`pullCloudNow`

`SyncManager.pullCloudNow()`（第 45-58 行）从未被任何地方调用，是死代码，可以安全删除。



---

## 七、函数依赖图

```
页面调用
    │
    ▼
RdbDataService
    │
    ├─ nodeRepo / travelRepo  ──→  RdbHelper ──→ RDB
    │
    ├─ buildPhotoManifest()     → cloud paths
    │
    ├─ enqueueSync()           ──→ RdbHelper（sync_queue）
    │                                 │
    ├─ enqueueSyncSilently()   ──→ RdbHelper（sync_queue）
    │                                 │
    └─ uploadNodePhotosToCloud  ──→  CloudStorageService
            │
            └── uploadFile / deleteFile

SyncManager
    │
    ├─ pushLocalNow
    │      │
    │      └─ handleItem  ──→  CloudSyncService
    │                              │
    │                              └── upsertMemoryNode（写 cloudDB，含 photoManifest）
    │
    ├─ replaceLocalWithCloud
    │      │
    │      ├─ syncNodePhotosForDownload  ──→  CloudStorageService.downloadFile
    │      │
    │      └─ upsertFromCloud  ──→  RdbHelper（写本地 DB）
    │
    └─ syncAllLocalToCloud
           │
           ├─ upsertMemoryNode  ──→  CloudSyncService
           ├─ syncNodePhotosForUpload  ──→  CloudStorageService.uploadFile
           └─ re-upsertMemoryNode  ──→  CloudSyncService（写入含正确 manifest 的 payload）
```

---

## 八、测试建议

1. **离线创建节点 + 重联网**：验证离线改动是否保留在 sync queue，不会自动上传
2. **创建带照片节点后立即查看 sync queue**：验证 manifest 是否正确（应为 cloud paths，不是空数组）
3. **空置节点加入路线 + 查看本地 DB**：验证本地 photo_manifest 是否立即更新为新 cloud paths
4. **本地有未同步改动时点「下载云端」**：验证是否有确认提示（目前暂无，属于已知 UX 缺陷，见 6.5）
5. **UNCATEGORIZED 节点加照片 + 点下载云端**：验证元数据 + 照片是否正常下载到本地
