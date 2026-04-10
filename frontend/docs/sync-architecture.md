# TravelPin 同步架构说明

> 内部设计文档 | 2026-04-09

## 1. 目标

当前 TravelPin 的数据同步设计服务于两个目标：

1. **多设备同步**：同一华为账号在不同设备登录后，旅行和节点元数据可以保持一致。
2. **数据备份**：本地设备损坏、卸载或切换设备后，可以从云端恢复元数据与照片引用。

当前设计采用：

- **本地 RDB 作为离线真相源**
- **云存储保存照片文件**
- **云数据库保存旅行/节点元数据**
- **sync_queue 作为本地待同步任务队列**

---

## 2. 总体架构

```text
用户操作（新增/编辑/删除）
        │
        ▼
RdbDataService
        │
        ├─ 1. 先写本地 RDB（本地优先）
        ├─ 2. 照片走 CloudStorageService 上传到云存储
        └─ 3. 写 sync_queue，登记待同步元数据任务
                │
                ▼
            SyncManager
                │
                ├─ 上行同步：sync_queue → CloudSyncService → TravelPinZone
                └─ 下行同步：TravelPinZone → CloudSyncService → 本地 Repository 回写
```

---

## 3. 本地数据库设计

本地数据库初始化在：

- `frontend/entry/src/main/ets/common/data/RdbHelper.ets`

当前核心表有三张：

### 3.1 travels

用途：保存旅行主记录。

当前业务字段：

- `id`：本地自增主键
- `name`
- `cover_image_uri`
- `start_date`
- `end_date`
- `created_at`
- `updated_at`
- `sensitivity`

新增同步字段：

- `owner_uid`：当前登录用户 uid，用于本地数据隔离
- `cloud_id`：云端主键映射
- `sync_status`：同步状态
- `deleted_at`：软删除时间，0 表示未删除
- `last_synced_at`：最近一次同步完成时间
- `version`：版本号，用于冲突处理基础

### 3.2 memory_nodes

用途：保存节点记录。

当前业务字段：

- `id`
- `travel_id`
- `latitude`
- `longitude`
- `title`
- `poi_name`
- `description`
- `address`
- `mood`
- `tags`
- `photos`
- `node_order`
- `created_at`
- `updated_at`
- `sensitivity`

新增同步字段：

- `owner_uid`
- `cloud_id`
- `sync_status`
- `deleted_at`
- `last_synced_at`
- `version`
- `photo_manifest`：照片云端引用信息（JSON 字符串）

### 3.3 sync_queue

用途：保存待同步任务。

字段：

- `id`
- `entity_type`：如 `travel`、`memory_node`
- `entity_id`：本地主键
- `operation`：如 `upsert`、`delete`
- `payload`：同步所需 JSON 数据
- `created_at`
- `retry_count`

---

## 4. 本地 Repository / Service 分层

### 4.1 Repository 层

文件：

- `frontend/entry/src/main/ets/common/data/TravelRepository.ets`
- `frontend/entry/src/main/ets/common/data/MemoryNodeRepository.ets`

职责：

- 本地表 CRUD
- 同步字段映射
- 软删除
- 云端同步后本地状态回写
- 下行同步时回写本地记录

### 4.2 Service 层

文件：

- `frontend/entry/src/main/ets/common/service/RdbDataService.ets`

职责：

- 组织业务 CRUD
- 本地写库后登记 `sync_queue`
- 调用云存储上传/删除照片
- 对上层页面提供统一 `IDataService` 接口

关键原则：

- **先写本地，后同步云端**
- 云端失败不能阻断本地使用

---

## 5. 云端数据库设计

当前云数据库 schema 文件：

- `frontend/entry/src/main/resources/rawfile/schema.json`

当前 zone 名称：

- `TravelPinZone`

当前对象类型有两个：

### 5.1 Travel

字段：

- `cloudId`（主键）
- `ownerUid`
- `name`
- `coverPhotoObjectKey`
- `startDate`
- `endDate`
- `createdAt`
- `updatedAt`
- `deletedAt`
- `version`

### 5.2 MemoryNode

字段：

- `cloudId`（主键）
- `ownerUid`
- `travelCloudId`
- `title`
- `content`
- `latitude`
- `longitude`
- `poiName`
- `mood`
- `tagsJson`
- `nodeOrder`
- `photoManifest`
- `createdAt`
- `updatedAt`
- `deletedAt`
- `version`

### 5.3 权限策略

当前权限已经收紧为：

- `World`：无权限
- `Authenticated`：`Read / Upsert / Delete`
- `Creator`：`Read / Upsert / Delete`
- `Administrator`：`Read / Upsert / Delete`

这意味着未登录用户不能直接读取旅行数据。

---

## 6. 照片与元数据分离设计

### 6.1 云存储负责什么

文件：

- `frontend/entry/src/main/ets/common/auth/CloudStorageService.ets`

职责：

- 上传/删除节点照片
- 按 uid 隔离路径

当前路径规则：

```text
users/{uid}/travels/{travelId}/nodes/{nodeId}/{filename}
```

### 6.2 云数据库负责什么

云数据库**不存照片二进制**，只存：

- 照片 object key
- 照片引用信息
- 节点元数据

这样设计的原因：

1. 云数据库适合存结构化数据，不适合存媒体文件
2. 云存储已经具备稳定的文件上传链路
3. 元数据与媒体分离，便于多设备恢复

---

## 7. 同步逻辑设计

### 7.1 上行同步

入口：

- `frontend/entry/src/main/ets/common/sync/SyncManager.ets`

流程：

1. 本地 CRUD 完成后，`RdbDataService` 写入 `sync_queue`
2. `SyncManager.triggerNow()` 读取 `sync_queue`
3. 调用 `CloudSyncService`：
   - `upsertTravel()`
   - `deleteTravel()`
   - `upsertMemoryNode()`
   - `deleteMemoryNode()`
4. 上行成功后：
   - 回写本地 `cloud_id`
   - 回写 `sync_status = synced`
   - 回写 `last_synced_at`
   - 删除对应队列任务

### 7.2 下行同步

流程：

1. `SyncManager.triggerNow()` 在上行完成后执行 `pullFromCloud()`
2. `CloudSyncService` 按 `ownerUid` 查询：
   - `fetchTravels(ownerUid)`
   - `fetchMemoryNodes(ownerUid)`
3. 对每条云端记录：
   - 若 `deletedAt > 0`：本地标记删除
   - 否则：本地 upsert

### 7.3 当前触发时机

#### 应用启动后
文件：

- `frontend/entry/src/main/ets/entryability/EntryAbility.ets`

逻辑：

- 登录态恢复成功后，如果云能力可用，则自动触发一次 `SyncManager.triggerNow()`

#### “我的”页手动同步
文件：

- `frontend/entry/src/main/ets/feature/profile/views/ProfileView.ets`

逻辑：

- 点击“立即同步”按钮，手动调用 `SyncManager.triggerNow()`

---

## 8. 软删除为什么必要

当前删除不再直接走物理删除传播，而是先在本地打标记：

- `deleted_at = 时间戳`
- `sync_status = pending_delete`

意义：

1. A 设备删除后，云端可以知道“这条记录被删过”
2. B 设备同步云端时，也能感知删除事件
3. 从而实现“多设备删除传播”

### 8.1 当前效果

当前已经具备：

- **删除可传播**
- **同步后另一台设备会删除/隐藏对应数据**

但还不是推送式“秒级实时”。

现在更准确的行为是：

- A 删除并同步到云端
- B 启动时或点击“立即同步”后拉到删除记录
- B 本地数据消失

如果以后要做更接近实时，需要再加：

- 定时同步
- 前台轮询
- 或消息通知/推送机制

---

## 9. 当前同步状态展示

文件：

- `frontend/entry/src/main/ets/feature/profile/views/ProfileView.ets`

当前“我的”页面：

- `cloudStatusText`：来自真实云连接状态
- `pendingCount`：来自真实 `sync_queue` 数量
- “立即同步”按钮：已触发真实同步

仍然还有可以继续精修的地方：

- `lastSyncTime` 还不是完整的真实时间语义
- 还可以补充最近同步结果提示

---

## 10. 当前已完成 / 未完成

### 已完成

- 本地 RDB 增加同步字段
- 本地 CRUD 写 `sync_queue`
- 照片上传/删除走云存储
- 云数据库 schema 已引入
- Travel / MemoryNode 对象类型已接入
- 上行同步已接入
- 下行同步基础已接入
- 软删除传播链路已具备
- 启动同步、手动同步入口已接入

### 未完成

- `travelCloudId` 与本地 `travelId` 映射还可继续精修
- `nodeOrder` / `photoManifest` 仍可进一步和云存储联动
- `lastSyncTime` 还可做成真实时间记录
- 当前没有定时同步机制
- 当前没有冲突解决 UI

---

## 11. 你现在可以怎么验证

建议用两台设备、同一账号测试：

### 场景 1：新增同步
1. A 新增旅行或节点
2. A 点击“立即同步”
3. B 点击“立即同步”
4. 检查 B 是否出现对应数据

### 场景 2：编辑同步
1. A 修改节点标题/内容
2. A 点击“立即同步”
3. B 点击“立即同步”
4. 检查 B 是否更新

### 场景 3：删除传播
1. A 删除节点/旅行
2. A 点击“立即同步”
3. B 点击“立即同步”
4. 检查 B 是否消失

---

## 12. 相关关键文件

### 本地数据库
- `frontend/entry/src/main/ets/common/data/RdbHelper.ets`
- `frontend/entry/src/main/ets/common/data/TravelRepository.ets`
- `frontend/entry/src/main/ets/common/data/MemoryNodeRepository.ets`

### 业务编排
- `frontend/entry/src/main/ets/common/service/RdbDataService.ets`
- `frontend/entry/src/main/ets/common/service/IDataService.ets`

### 云能力
- `frontend/entry/src/main/ets/common/auth/AuthService.ets`
- `frontend/entry/src/main/ets/common/auth/CloudStorageService.ets`
- `frontend/entry/src/main/ets/common/sync/CloudSyncService.ets`
- `frontend/entry/src/main/ets/common/sync/SyncManager.ets`

### 云数据库对象与 schema
- `frontend/entry/src/main/ets/common/sync/CloudTravel.ets`
- `frontend/entry/src/main/ets/common/sync/CloudMemoryNode.ets`
- `frontend/entry/src/main/resources/rawfile/schema.json`

### UI 状态
- `frontend/entry/src/main/ets/feature/profile/views/ProfileView.ets`
- `frontend/entry/src/main/ets/entryability/EntryAbility.ets`
