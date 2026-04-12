# TravelPin 登录、账号资料授权与云同步架构说明

> 内部设计文档 | 2026-04-12
>
> 适用范围：HarmonyOS 前端当前实现（登录、云数据库、云存储、自动增量同步、手动全量纠偏）

---

## 1. 目标

当前 TravelPin 的登录与云同步设计服务于 4 个目标：

1. **同账号多设备同步**：同一华为账号在不同设备登录后，`travel`、`node`、图片都能保持一致。
2. **离线优先**：无网时先写本地，联网后自动补同步。
3. **手动纠偏**：用户可以主动执行“以本地为准”或“以云端为准”的全量对齐。
4. **媒体与元数据分离**：图片走云存储，结构化数据走云数据库，便于恢复与扩展。

当前已经采用：

- **本地 RDB 作为离线真相源**
- **华为账号登录 + AGC 鉴权**
- **登录后追加 profile 资料授权（昵称 / 头像）**
- **云存储保存图片文件**
- **云数据库保存 travel / node 元数据**
- **sync_queue 作为自动增量同步队列**

---

## 2. 整体架构

```text
┌────────────────────────────────────────────────────────────┐
│                        Huawei ID 登录                      │
│  AuthenticationController → AGC Auth → AuthService        │
└────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────┐
│                    Cloud Foundation 初始化                 │
│  CloudStorageService / CloudSyncService                    │
│  - Cloud Storage                                           │
│  - Cloud Database (TravelPinZone)                          │
└────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────┐
│                    本地优先数据写入层                      │
│  UI → RdbDataService → Repository → RDB                   │
│                                                            │
│  travel / node CRUD 先写本地                               │
│  图片先落本地 sandbox(filesDir/photos)                     │
└────────────────────────────────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
┌─────────────────────────┐      ┌──────────────────────────┐
│ 自动增量同步（默认）        │      │ 手动全量同步（按钮）         │
│ sync_queue              │      │ 上传本地 / 下载云端         │
│ SyncManager.pushLocalNow│      │ SyncManager.pushAll...   │
│                         │      │ SyncManager.pullAll...   │
└─────────────────────────┘      └──────────────────────────┘
              │                             │
              └──────────────┬──────────────┘
                             ▼
┌────────────────────────────────────────────────────────────┐
│                        云端目标层                            │
│  Cloud Database: Travel / MemoryNode                       │
│  Cloud Storage: users/{uid}/travels/.../nodes/...          │
└────────────────────────────────────────────────────────────┘
```

---

## 3. 登录架构

### 3.1 关键文件

- `frontend/entry/src/main/ets/common/auth/AuthService.ets`
- `frontend/entry/src/main/ets/common/auth/CloudStorageService.ets`
- `frontend/entry/src/main/ets/common/sync/CloudSyncService.ets`
- `frontend/entry/src/main/ets/entryability/EntryAbility.ets`
- `frontend/entry/src/main/ets/feature/profile/views/ProfileView.ets`

### 3.2 登录链路

当前登录流程：

1. 前端通过 `AuthenticationController` 拉起华为账号登录。
2. 登录成功后，交给 `@hw-agconnect/auth` 建立 AGC 用户会话。
3. `AuthService` 统一暴露当前用户：
   - `uid`
   - `displayName`
   - `avatarUrl`
   - `unionId`（如果可取到）
4. `CloudStorageService` / `CloudSyncService` 使用 AGC `authProvider` 初始化云能力。
5. 当前登录实现分两段：
   - 先通过 `createLoginWithHuaweiIDRequest()` 建立登录态与 AGC 会话
   - 再通过 `createAuthorizationWithHuaweiIDRequest()` + `scopes=['profile']` 请求昵称/头像资料授权

### 3.3 当前登录展示

当前“我的”页展示的是：

- 当前用户资料：
  - `displayName`
  - `avatarUrl`（如果授权成功且可加载）
- 云存储连接状态
- 同步状态（最近上传 / 最近下载 / 待同步数量）

头像显示策略：

- 优先显示华为账号资料授权返回的 `avatarUrl`
- 若未授权、无头像或远程加载失败，则回退为本地占位头像 `👤`

### 3.5 头像昵称授权说明

当前实现已经验证：

- 仅使用 `createLoginWithHuaweiIDRequest()` 时，登录响应通常只包含：
  - `authorizationCode`
  - `idToken`
  - `openID`
  - `unionID`
- 这条链路**不能稳定拿到**华为账号昵称与头像
- `@hw-agconnect/auth` 当前用户对象中的：
  - `getDisplayName()`
  - `getPhotoUrl()`
  在本项目当前登录模式下也可能为空或回落默认值

因此当前采用的正确做法是：

1. 先执行登录请求，建立 AGC 会话
2. 再执行 `createAuthorizationWithHuaweiIDRequest()`
3. 设置：
   - `scopes = ['profile']`
   - `forceAuthorization = true`
4. 从资料授权响应中提取：
   - `nickName`
   - `avatarUri`
5. 回写到 `AuthService.currentUser`，供 Profile 页面显示

注意：

- 资料授权是否每次都弹出，最终由系统授权状态决定，客户端即使设置 `forceAuthorization = true`，也不一定每次都重新弹窗
- 对个人开发者而言，**获取昵称与头像资料授权是可行的**，不属于企业专属能力


本地与云端隔离都依赖当前登录用户 `uid`：

- 本地表使用 `owner_uid`
- 云存储路径按 `users/{uid}/...` 隔离
- 云数据库对象使用 `ownerUid`

这意味着：

- A 账号和 B 账号在本地查询层是隔离的
- A 的云数据不会直接展示给 B

---

## 4. 本地数据库设计

### 4.1 关键文件

- `frontend/entry/src/main/ets/common/data/RdbHelper.ets`
- `frontend/entry/src/main/ets/common/data/TravelRepository.ets`
- `frontend/entry/src/main/ets/common/data/MemoryNodeRepository.ets`

### 4.2 核心表

#### travels

用途：旅行主记录。

主要字段：

- `id`：本地自增主键
- `name`
- `cover_image_uri`
- `start_date`
- `end_date`
- `created_at`
- `updated_at`
- `owner_uid`
- `cloud_id`
- `sync_status`
- `deleted_at`
- `last_synced_at`
- `version`

#### memory_nodes

用途：旅行节点记录。

主要字段：

- `id`
- `travel_id`
- `latitude`
- `longitude`
- `title`
- `poi_name`
- `description`
- `mood`
- `tags`
- `photos`
- `photo_manifest`
- `node_order`
- `created_at`
- `updated_at`
- `owner_uid`
- `cloud_id`
- `sync_status`
- `deleted_at`
- `last_synced_at`
- `version`

#### sync_queue

用途：本地自动增量同步队列。

字段：

- `entity_type`
- `entity_id`
- `operation`
- `payload`
- `created_at`
- `retry_count`

#### app_sync_state

用途：保存同步状态时间。

当前保存：

- `last_push_at`
- `last_pull_at`

---

## 5. 云端模型设计

### 5.1 云数据库

关键文件：

- `frontend/entry/src/main/resources/rawfile/schema.json`
- `frontend/entry/src/main/ets/common/sync/CloudTravel.ets`
- `frontend/entry/src/main/ets/common/sync/CloudMemoryNode.ets`
- `frontend/entry/src/main/ets/common/sync/CloudSyncService.ets`

当前 Zone：

- `TravelPinZone`

#### Travel

字段：

- `cloudId`
- `ownerUid`
- `name`
- `coverPhotoObjectKey`
- `startDate`
- `endDate`
- `createdAt`
- `updatedAt`
- `deletedAt`
- `version`

#### MemoryNode

字段：

- `cloudId`
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

### 5.2 云存储

关键文件：

- `frontend/entry/src/main/ets/common/auth/CloudStorageService.ets`

当前路径规则：

```text
users/{uid}/travels/{travelId}/nodes/{nodeId}/{filename}
```

设计原则：

- 图片二进制永远走云存储
- 云数据库只存图片引用信息

---

## 6. 图片元数据设计

这是当前实现里最关键的一条约定。

### 6.1 本地 `photos`

`photos` 保存：

- **本地可显示路径**
- 例如：`file:///data/storage/.../files/photos/xxx.jpg`

也就是说，`photos` 是 UI 直接显示用的字段。

### 6.2 云端 / 同步用 `photoManifest`

`photoManifest` 保存：

- **云端对象路径数组**
- 例如：

```json
[
  "travels/21/nodes/28/photo_1775929705919_156.jpg"
]
```

这意味着：

- 上传时：根据本地 `photos` 生成云端 object key，写入 `photoManifest`
- 下载时：优先按 `photoManifest` 的云端路径下载图片
- 下载完成后，再把本地 sandbox 路径写回 `photos`

### 6.3 为什么必须这样分离

如果把本地 `file://...` 路径直接上传到云数据库：

- 同设备看起来可能还能凑合工作
- 但跨设备恢复一定失败

因此现在的正确分工是：

- `photos` = 本地路径
- `photoManifest` = 云端路径

---

## 7. 自动增量同步逻辑

### 7.1 关键文件

- `frontend/entry/src/main/ets/common/service/RdbDataService.ets`
- `frontend/entry/src/main/ets/common/sync/SyncManager.ets`
- `frontend/entry/src/main/ets/common/sync/CloudSyncService.ets`

### 7.2 当前产品语义

这是当前已经确认下来的设计：

- **新建 / 编辑 / 删除** `travel`、`node`、图片：默认自动同步到云端
- **同步本地**：只是“以本地为准”的全量纠偏 / 调试入口
- **下载云端**：是“以云端为准”的全量覆盖入口

### 7.3 自动同步流程

```text
用户新增 / 编辑 / 删除
        │
        ▼
RdbDataService 先写本地 RDB
        │
        ├─ 图片上传/删除：CloudStorageService
        └─ 元数据任务入 sync_queue
                │
                ▼
         SyncManager.pushLocalNow()
                │
                ▼
         CloudSyncService 上行到云数据库
```

### 7.4 当前行为

#### 自动同步到云端（默认）

- 新建 `travel`：自动上传元数据
- 编辑 `travel`：自动上传元数据
- 删除 `travel`：自动删除云数据库记录，并清理云存储目录
- 新建 `node`：自动上传元数据 + 自动上传图片
- 编辑 `node`：自动上传元数据 + 补传新增图片 + 删除移除图片
- 删除 `node`：自动删除云数据库记录，并删除对应云存储图片

#### 当前自动同步实现细节

1. `RdbDataService.enqueueSync()` 在本地写入成功后会立即：
   - 先按 `entity_type + entity_id` 清掉旧队列项
   - 再插入新的 `sync_queue` 任务
   - 最后触发 `SyncManager.pushLocalNow()`
2. 这意味着自动增量同步当前是“**同一实体仅保留最后一条待上传任务**”的模型
3. `pushLocalNow()` 负责顺序消费 `sync_queue`，并根据任务类型调用：
   - `CloudSyncService.upsertTravel()` / `hardDeleteTravelByCloudId()`
   - `CloudSyncService.upsertMemoryNode()` / `hardDeleteMemoryNodeByCloudId()`
4. `memory_node delete` 分支除了删除云数据库记录，还会：
   - 删除 `photoCloudPaths` 中的明确对象
   - 再按 `travels/{travelId}/nodes/{nodeId}/` 目录递归清理残留图片

#### 当前已知约束

- `sync_queue` 的去重粒度是 `entity_type + entity_id`，不是操作级别
- 因此同一实体离线期间若发生多次不同操作，最终只保留最后一条任务
- 该行为目前是既定实现，不是文档层面的目标能力，需要在后续冲突策略设计中继续评估

---

## 8. 手动全量同步逻辑

### 8.1 “上传本地”

入口：

- `ProfileView` → `SyncManager.pushAllLocalToCloud()`

语义：

- **以本地为准**
- 云端最终变成本地当前状态

行为：

- 本地存在的 `travel/node` 上传到云数据库
- 本地不存在的云端多余 `travel/node` 物理删除
- 本地图片与云存储对象做差异对齐
- 被整段删除的 `travel/node` 也会清理对应云存储目录

### 8.2 “下载云端”

入口：

- `ProfileView` → `SyncManager.pullAllCloudToLocal()`

语义：

- **以云端为准**
- 本地最终变成云端当前状态

行为：

- 执行前先清空本地 `sync_queue`
- 云端 `travel/node` 回写本地 RDB
- 本地多余记录删除
- node 图片优先按 `photoManifest` 下载到本地 sandbox
- 下载完成后，`photos` 写本地路径，供 UI 直接显示

为什么要先清空 `sync_queue`：

- 用户断网时本地删除/编辑操作会先进入队列
- 如果随后选择“下载云端”，产品语义已经变成“云端覆盖本地”
- 这时保留旧队列会导致下载成功后，旧 delete / upsert 又被自动同步回云端，造成刚恢复的数据再次丢失

---

## 9. 下载云端后的本地回写链路

### 9.1 travel 回写

链路：

- `CloudSyncService.fetchTravels()`
- `SyncManager.replaceLocalWithCloud()`
- `TravelRepository.upsertFromCloud()`
- `RdbDataService.getAllTravels()` / `getTravelById()`

注意：

- `RdbDataService` 不能在重新组装 `Trip` 时丢掉同步字段
- 否则列表显示与后续同步状态会出问题

### 9.2 node 图片回写

链路：

- `CloudSyncService.fetchMemoryNodes()`
- `SyncManager.replaceLocalWithCloud()`
- 先通过 `cloudId` 查回本地 `node.id`
- `SyncManager.syncNodePhotosForDownload()`
- `CloudStorageService.downloadNodePhotoToSandbox()`
- `MemoryNodeRepository.upsertFromCloud()`

当前正确行为：

1. 读取 `photoManifest`
2. 如果 `photoManifest` 有值，优先按 manifest 中的**完整云端对象路径**下载图片
3. 仅当 manifest 不可用时，才回退到 `travels/{travelId}/nodes/{nodeId}/` 目录枚举
4. 下载时先落 cache，再复制到 `filesDir/photos`
5. 最终把 `file://{filesDir}/photos/...` 写回 `photos`
6. `photoManifest` 保持为云端路径数组，不再改写成本地 `file://...` 路径
7. `NodeDetailPage` / `NodeEditPage` / `PhotoSelector` 继续直接读 `photos`

这条链路当前特别依赖两个约定：

- `node.id` 必须在下载图片前先从 `cloudId` 映射回真实本地 id，避免拼出错误的 `nodes/0/` 目录
- `photoManifest` 必须始终代表云端路径，而不能混入本地路径

---

## 10. 同步状态展示

关键文件：

- `frontend/entry/src/main/ets/feature/profile/views/ProfileView.ets`
- `frontend/entry/src/main/ets/common/data/RdbHelper.ets`
- `frontend/entry/src/main/ets/common/service/RdbDataService.ets`

当前“我的”页显示：

- 登录状态
- 云存储状态
- 待同步数量
- 最近上传时间
- 最近下载时间
- “上传本地” / “下载云端”按钮

这些状态已经不是纯占位，而是读取真实本地状态。

---

## 11. 当前验证结论（截至 2026-04-12）

### 已通过的关键场景

- 华为账号登录成功
- Profile 可显示昵称（资料授权成功时）
- Profile 可显示头像（资料授权成功且图片可加载时）
- 云存储上传成功
- 新建 `travel/node` 自动同步到云端
- 删除 `node/travel` 自动清理云数据库
- 删除 `node/travel` 自动清理云存储
- “上传本地”可作为全量纠偏入口
- “下载云端”后 travel 已能显示
- `photoManifest` 已改为云端对象路径格式

### 最近修复过的问题

1. **云数据库 delete 不生效**
   - 已切到物理删除链路并修正 delete 分支入口
2. **云存储 delete 路径重复拼接**
   - 已修正 `users/{uid}` 重复前缀问题
3. **离线删除后云存储残留**
   - 已把 node 删除补偿改成按明确 cloud path 删除
4. **download 云端后 travel 不显示**
   - 已修 service 层字段丢失问题
5. **download 云端后 node 图片消失**
   - 已修 `photoManifest` 错误写成本地路径的问题
   - 已改成按 manifest 完整 cloud path 下载
   - 已修下载时 `node.id=0` 导致 fallback 指向错误目录的问题
6. **下载云端后旧 delete 队列再次上行，导致节点重新被云端删除**
   - 已在“下载云端”前清空 `sync_queue`
7. **断网 / 恢复联网时用户无感知，容易误触发旧队列自动同步**
   - 已补充网络状态监听、断网/联网弹窗与个人页同步提醒条

### 仍建议继续验证的场景

- 旧历史数据的 `photoManifest` 可能仍是旧 `file://...` 格式
- 如果云端存在旧数据，最好通过“编辑后再保存”或后续迁移逻辑把 manifest 升级到新格式

---

## 12. 推荐测试清单

### 场景 A：自动同步
1. 新建一个 travel
2. 新建一个带图 node
3. 不点任何手动按钮
4. 验证云数据库 / 云存储是否自动更新

### 场景 B：自动删除
1. 删除一个带图 node
2. 验证云数据库 node 是否自动删除
3. 验证云存储图片是否自动删除
4. 删除整个 travel，再验证 travel 目录是否清理

### 场景 C：上传本地
1. 本地保留一套完整数据
2. 云端故意制造差异
3. 点“上传本地”
4. 验证云数据库 + 云存储最终与本地一致

### 场景 D：下载云端
1. 云端保留一套完整数据（含图片）
2. 本地清空或制造差异
3. 点“下载云端”
4. 验证：
   - travel 显示
   - node 显示
   - node 图片显示
   - 重启 app 后图片仍可显示

---

## 13. 后续可继续优化的方向

1. **旧 `photoManifest` 迁移**
   - 把历史 `file://...` manifest 升级为云端对象路径
2. **更明确的同步结果提示**
   - Profile 页增加最近一次成功 / 失败提示
3. **冲突策略 UI**
   - 当前是“按钮决定方向”，后续可补更友好的冲突说明
4. **下载云端逻辑继续精修**
   - 包括异常提示、历史数据兼容、批量恢复反馈

---

## 14. 关键文件索引

### 登录与云能力
- `frontend/entry/src/main/ets/common/auth/AuthService.ets`
- `frontend/entry/src/main/ets/common/auth/CloudStorageService.ets`
- `frontend/entry/src/main/ets/common/sync/CloudSyncService.ets`
- `frontend/entry/src/main/ets/entryability/EntryAbility.ets`

### 本地数据库
- `frontend/entry/src/main/ets/common/data/RdbHelper.ets`
- `frontend/entry/src/main/ets/common/data/TravelRepository.ets`
- `frontend/entry/src/main/ets/common/data/MemoryNodeRepository.ets`

### 服务与同步
- `frontend/entry/src/main/ets/common/service/RdbDataService.ets`
- `frontend/entry/src/main/ets/common/sync/SyncManager.ets`

### 页面与展示
- `frontend/entry/src/main/ets/feature/profile/views/ProfileView.ets`
- `frontend/entry/src/main/ets/feature/map-travel/views/TripListView.ets`
- `frontend/entry/src/main/ets/feature/map-travel/views/MapHomeView.ets`
- `frontend/entry/src/main/ets/feature/map-travel/pages/NodeDetailPage.ets`
- `frontend/entry/src/main/ets/feature/map-travel/pages/NodeEditPage.ets`
- `frontend/entry/src/main/ets/feature/map-travel/components/PhotoSelector.ets`
