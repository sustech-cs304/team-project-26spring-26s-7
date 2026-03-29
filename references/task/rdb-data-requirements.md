# RDB 数据库需求分析

**文档版本**: 1.0
**创建日期**: 2026-03-29
**最后更新**: 2026-03-29

---

## 一、概述

本文档列出项目中所有需要与本地 RDB 数据库交互的功能组件，明确数据流向和职责边界。

### 1.1 三层存储架构

```
┌─────────────────────────────────────────────────────────────┐
│ 存储层           │ 位置          │ 存储内容                  │
├─────────────────────────────────────────────────────────────┤
│ 本地存储层 (RDB)  │ 设备本地       │ 元数据、结构化数据         │
│ 云端同步层        │ 华为云空间     │ 照片原图、视频、备份       │
│ 后端服务层        │ 自建服务器     │ AI 生成、分享验证          │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 数据存储边界

| 存储 ✅ (RDB) | 不存储 ❌ |
|--------------|----------|
| 旅行元数据（名称、日期范围、封面 URI） | 照片原图（华为云存储） |
| 记忆节点（经纬度、描述、地址、时间戳） | 视频文件 |
| 用户草稿、标签、心情标记 | 用户身份信息（华为账号） |
| 同步状态、待同步队列 | Session Token（Preferences） |

---

## 二、数据表结构

### 2.1 travels 表（旅行元数据）

| 字段名 | 类型 | 必填 | 敏感度 | 说明 |
|--------|------|------|--------|------|
| id | INTEGER | PK | S1 | 主键，自增 |
| name | TEXT | ✓ | S1 | 旅行名称 |
| cover_image_uri | TEXT | | S1 | 封面图片 URI（华为云） |
| start_date | INTEGER | ✓ | S1 | 开始日期（时间戳） |
| end_date | INTEGER | ✓ | S1 | 结束日期（时间戳） |
| created_at | INTEGER | ✓ | S1 | 创建时间戳 |
| updated_at | INTEGER | ✓ | S1 | 更新时间戳 |
| sensitivity | TEXT | ✓ | S1 | 数据分级标识 |

### 2.2 memory_nodes 表（记忆节点）

| 字段名 | 类型 | 必填 | 敏感度 | 说明 |
|--------|------|------|--------|------|
| id | INTEGER | PK | S1 | 主键，自增 |
| travel_id | INTEGER | ✓ | S1 | 外键，关联 travels.id |
| latitude | REAL | ✓ | S2 | 纬度 |
| longitude | REAL | ✓ | S2 | 经度 |
| poi_name | TEXT | | S2 | 地点名称 |
| description | TEXT | | S3 | 描述/正文 |
| address | TEXT | | S2 | 地址 |
| mood | TEXT | | S3 | 心情表情 |
| tags | TEXT | | S1 | 标签（JSON 数组） |
| photos | TEXT | | S1 | 照片 URI 列表（JSON 数组） |
| "order" | INTEGER | | S1 | 排序序号 |
| created_at | INTEGER | ✓ | S1 | 创建时间戳 |
| updated_at | INTEGER | ✓ | S1 | 更新时间戳 |
| sensitivity | TEXT | ✓ | S2 | 数据分级标识 |

### 2.3 sync_queue 表（同步队列）- 预留

| 字段名 | 类型 | 必填 | 敏感度 | 说明 |
|--------|------|------|--------|------|
| id | INTEGER | PK | S1 | 主键，自增 |
| entity_type | TEXT | ✓ | S1 | 实体类型（travel/node） |
| entity_id | INTEGER | ✓ | S1 | 实体 ID |
| operation | TEXT | ✓ | S1 | 操作类型（CREATE/UPDATE/DELETE） |
| payload | TEXT | ✓ | S1 | 数据 payload（JSON） |
| created_at | INTEGER | ✓ | S1 | 入队时间戳 |
| retry_count | INTEGER | | S1 | 重试次数 |

---

## 三、功能组件与 RDB 交互矩阵

### 3.1 功能模块总览

| 模块 | 文件路径 | RDB 操作 | 说明 |
|------|----------|---------|------|
| MapHomeView | `feature/map-travel/views/MapHomeView.ets` | 读取节点 | 地图展示记忆节点 |
| NodeDetailPage | `feature/map-travel/pages/NodeDetailPage.ets` | 读取/删除节点 | 节点详情展示 |
| NodeEditPage | `feature/map-travel/pages/NodeEditPage.ets` | 创建/更新节点 | 节点编辑 |
| TripListView | `feature/map-travel/views/TripListView.ets` | 读取旅行列表 | 旅行列表展示 |
| TripDetailPage | `feature/map-travel/pages/TripDetailPage.ets` | 读取旅行 + 节点 | 旅行详情 + 时间轴 |
| TripReplayPage | `feature/map-travel/pages/TripReplayPage.ets` | 读取旅行 + 节点 | 轨迹回放 |
| ProfileView | `feature/profile/views/ProfileView.ets` | 读取同步状态 | 个人中心 |
| AiCopyGenerator | `feature/ai-copy/components/AiCopyGenerator.ets` | 读取元数据 | AI 文案生成 |
| QRCodeShare | `feature/social-share/components/QRCodeShare.ets` | 读取旅行元数据 | 分享链接生成 |
| TravelRepository | `common/data/TravelRepository.ets` | CRUD 旅行 | 数据仓库层 |
| MemoryNodeRepository | `common/data/MemoryNodeRepository.ets` | CRUD 节点 | 数据仓库层 |
| RdbHelper | `common/data/RdbHelper.ets` | 底层数据库操作 | 数据库助手 |

---

## 四、各组件详细需求

### 4.1 MapHomeView（地图首页）

**文件路径**: `frontend/entry/src/main/ets/feature/map-travel/views/MapHomeView.ets`

**RDB 操作**:
| 操作 | 调用 Repository | SQL 说明 |
|------|----------------|---------|
| 加载所有节点 | `MemoryNodeRepository.getNodesByTravelId()` | `SELECT * FROM memory_nodes ORDER BY created_at DESC` |
| 按时间筛选 | `MemoryNodeRepository.getNodesByTravelId()` + 过滤 | `WHERE created_at >= ?` |
| 按标签筛选 | `MemoryNodeRepository.getNodesByTravelId()` + 过滤 | `WHERE tags LIKE ?` |

**当前状态**: 使用模拟数据（mockNodes），待替换为真实 RDB 查询

---

### 4.2 NodeDetailPage（节点详情页）

**文件路径**: `frontend/entry/src/main/ets/feature/map-travel/pages/NodeDetailPage.ets`

**RDB 操作**:
| 操作 | 调用 Repository | SQL 说明 |
|------|----------------|---------|
| 加载节点详情 | `MemoryNodeRepository.getNodeById(id)` | `SELECT * FROM memory_nodes WHERE id = ?` |
| 删除节点 | `MemoryNodeRepository.deleteNode(id)` | `DELETE FROM memory_nodes WHERE id = ?` |

**当前状态**: 使用模拟数据，待替换为真实 RDB 查询（见第 27 行 TODO）

---

### 4.3 NodeEditPage（节点编辑页）

**文件路径**: `frontend/entry/src/main/ets/feature/map-travel/pages/NodeEditPage.ets`

**RDB 操作**:
| 操作 | 调用 Repository | SQL 说明 |
|------|----------------|---------|
| 加载编辑数据（编辑模式） | `MemoryNodeRepository.getNodeById(id)` | `SELECT * FROM memory_nodes WHERE id = ?` |
| 保存新节点 | `MemoryNodeRepository.createNode(input)` | `INSERT INTO memory_nodes (...) VALUES (...)` |
| 更新节点 | `MemoryNodeRepository.updateNode(id, input)` | `UPDATE memory_nodes SET ... WHERE id = ?` |

**当前状态**: 表单功能已完成，保存逻辑待实现（见第 33 行 TODO）

---

### 4.4 TripListView（旅行列表页）

**文件路径**: `frontend/entry/src/main/ets/feature/map-travel/views/TripListView.ets`

**RDB 操作**:
| 操作 | 调用 Repository | SQL 说明 |
|------|----------------|---------|
| 加载旅行列表 | `TravelRepository.getAllTravels()` | `SELECT * FROM travels ORDER BY created_at DESC` |
| 删除旅行 | `TravelRepository.deleteTravel(id)` | `DELETE FROM travels WHERE id = ?`（级联删除节点） |

**当前状态**: 需要实现

---

### 4.5 TripDetailPage（旅行详情页）

**文件路径**: `frontend/entry/src/main/ets/feature/map-travel/pages/TripDetailPage.ets`

**RDB 操作**:
| 操作 | 调用 Repository | SQL 说明 |
|------|----------------|---------|
| 加载旅行详情 | `TravelRepository.getTravelById(id)` | `SELECT * FROM travels WHERE id = ?` |
| 加载关联节点 | `MemoryNodeRepository.getNodesByTravelId(id)` | `SELECT * FROM memory_nodes WHERE travel_id = ? ORDER BY "order" ASC` |
| 删除旅行 | `TravelRepository.deleteTravel(id)` | 级联删除 |
| 更新旅行 | `TravelRepository.updateTravel(id, input)` | `UPDATE travels SET ... WHERE id = ?` |

**当前状态**: 使用模拟数据，待替换为真实 RDB 查询（见第 88 行 TODO）

---

### 4.6 TripReplayPage（旅行回放页）

**文件路径**: `frontend/entry/src/main/ets/feature/map-travel/pages/TripReplayPage.ets`

**RDB 操作**:
| 操作 | 调用 Repository | SQL 说明 |
|------|----------------|---------|
| 加载旅行轨迹 | `TravelRepository.getTravelById(id)` + `MemoryNodeRepository.getNodesByTravelId(id)` | 按顺序加载节点 |

**当前状态**: 使用模拟数据，待替换（见第 78 行 TODO）

---

### 4.7 ProfileView（个人中心页）

**文件路径**: `frontend/entry/src/main/ets/feature/profile/views/ProfileView.ets`

**RDB 操作**:
| 操作 | 调用 Repository | SQL 说明 |
|------|----------------|---------|
| 获取同步状态 | 待实现 `SyncRepository.getStatus()` | 查询 sync_queue 表 |
| 获取待同步数量 | 待实现 `SyncRepository.getPendingCount()` | `SELECT COUNT(*) FROM sync_queue` |

**当前状态**: 使用模拟状态数据，待集成真实同步状态

---

### 4.8 AiCopyGenerator（AI 文案生成器）

**文件路径**: `frontend/entry/src/main/ets/feature/ai-copy/components/AiCopyGenerator.ets`

**RDB 操作**:
| 操作 | 调用 Repository | SQL 说明 |
|------|----------------|---------|
| 获取旅行元数据 | `TravelRepository.getTravelById(id)` | 用于 AI 请求 |
| 获取节点 POI 列表 | `MemoryNodeRepository.getNodesByTravelId(id)` | 脱敏后发送给 AI |

**数据流**:
```
RDB → MetadataAggregator → AiCopyGenerator → AI Gateway API
        (聚合脱敏)          (组装请求)
```

**当前状态**: 占位实现，待集成真实数据

---

### 4.9 QRCodeShare（二维码分享）

**文件路径**: `frontend/entry/src/main/ets/feature/social-share/components/QRCodeShare.ets`

**RDB 操作**:
| 操作 | 调用 Repository | SQL 说明 |
|------|----------------|---------|
| 获取旅行元数据 | `TravelRepository.getTravelById(id)` | 生成分享链接 |

**当前状态**: 需要实现

---

### 4.10 TravelRepository（旅行数据仓库）

**文件路径**: `frontend/entry/src/main/ets/common/data/TravelRepository.ets`

**职责**: 封装 travels 表的所有 CRUD 操作

**接口定义**:
```typescript
interface TravelRepository {
  getAllTravels(): Promise<Trip[]>
  getTravelById(id: string): Promise<Trip | undefined>
  createTravel(input: CreateTravelInput): Promise<string>
  updateTravel(id: string, input: UpdateTravelInput): Promise<boolean>
  deleteTravel(id: string): Promise<boolean>
}
```

**当前状态**: 占位实现（STUB），所有方法返回空数据

---

### 4.11 MemoryNodeRepository（记忆节点数据仓库）

**文件路径**: `frontend/entry/src/main/ets/common/data/MemoryNodeRepository.ets`

**职责**: 封装 memory_nodes 表的所有 CRUD 操作

**接口定义**:
```typescript
interface MemoryNodeRepository {
  getNodesByTravelId(travelId: string): Promise<MemoryNode[]>
  getNodeById(id: string): Promise<MemoryNode | undefined>
  createNode(input: CreateNodeInput): Promise<string>
  updateNode(id: string, input: UpdateNodeInput): Promise<boolean>
  deleteNode(id: string): Promise<boolean>
  reorderNodes(travelId: string, nodeIds: string[]): Promise<void>
}
```

**当前状态**: 占位实现（STUB），所有方法返回空数据

---

### 4.12 RdbHelper（数据库助手）

**文件路径**: `frontend/entry/src/main/ets/common/data/RdbHelper.ets`

**职责**:
- 管理 RDB 数据库连接
- 提供表创建、升级迁移
- 封装基础 SQL 操作
- 数据分级标识（S0-S4）管理

**当前状态**: 占位实现（STUB），待实现真实数据库操作

**依赖**: `@kit.ArkData.relationalStore`

---

## 五、数据流图

### 5.1 典型用户旅程：创建记忆节点

```
用户操作 (NodeEditPage)
    ↓
点击保存
    ↓
NodeEditPage.handleSave()
    ↓
MemoryNodeRepository.createNode(input)
    ↓
RdbHelper.execute("INSERT INTO memory_nodes ...")
    ↓
写入本地 RDB
    ↓
触发同步队列（待实现）
    ↓
返回成功 → 路由返回
```

### 5.2 典型用户旅程：查看旅行详情

```
用户操作 (TripListView)
    ↓
点击旅行卡片
    ↓
router.pushUrl(TripDetailPage, { tripId })
    ↓
TripDetailPage.aboutToAppear()
    ↓
TravelRepository.getTravelById(id)
MemoryNodeRepository.getNodesByTravelId(id)
    ↓
RdbHelper.query("SELECT * FROM ...")
    ↓
读取本地 RDB
    ↓
UI 渲染展示
```

### 5.3 AI 文案生成数据流

```
用户操作 (AiCopyPage)
    ↓
点击生成文案
    ↓
MetadataAggregator.aggregate(tripId)
    ↓
从 RDB 读取 → 脱敏处理 → 聚合元数据
    ↓
AiCopyGenerator.generate({ poiList, distance, duration, tags })
    ↓
POST /api/v1/ai/generate → 自建服务器
    ↓
返回生成文案 → UI 展示
```

---

## 九、参考实现案例：operaterdbintaskpool

### 9.1 案例简介

**路径**: `references/operaterdbintaskpool/`

本案例是一个完整的通讯录应用，展示了在 HarmonyOS 中操作 RDB 数据库的最佳实践。涵盖了以下核心内容：

- 关系型数据库的创建和初始化
- CRUD 操作封装（单条插入、批量插入、删除、更新、查询）
- 使用 TaskPool 在子线程中执行数据库操作，避免阻塞 UI 线程
- 数据源与 UI 的回调更新机制

**效果图**:
![](../operaterdbintaskpool/product/entry/src/main/resources/base/media/operate_rdb_in_taskpool.gif)

---

### 9.2 核心代码结构

```
operaterdbintaskpool/
├── constant/
│   ├── CommonConstant.ets          // 通用常量
│   └── RdbConstant.ets             // RDB 配置常量（STORE_CONFIG、SQL 语句）
├── model/
│   ├── Contact.ets                 // 联系人数据结构
│   ├── DataSource.ets              // JSON 数据解析
│   └── WorkListDataSource.ets      // 列表数据模型
└── view/
    ├── AddressBookDetail.ets       // 通讯录详情页
    ├── AddressBookEdit.ets         // 编辑/新增页
    ├── AddressBookList.ets         // 列表页
    ├── DatabaseConnection.ets      // 数据库操作封装
    ├── OperateRDBInTaskPool.ets    // 主页面
    └── TaskPool.ets                // TaskPool 任务封装
```

---

### 9.3 关键实现步骤

#### 步骤 1：初始化数据库

```typescript
// DatabaseConnection.ets
import { relationalStore as rdb, common } from '@kit.ArkData'

const STORE_CONFIG = {
  name: 'Contact.db',
  securityLevel: rdb.SecurityLevel.S1
}

const SQL_CREATE_TABLE = `
  CREATE TABLE IF NOT EXISTS contact(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT,
    phone TEXT,
    email TEXT,
    address TEXT,
    avatar TEXT,
    category TEXT
  )
`

export class DatabaseConnection {
  private static instance: DatabaseConnection
  private rdbStore: rdb.RdbStore | null = null

  private constructor() {}

  static getInstance(): DatabaseConnection {
    if (!DatabaseConnection.instance) {
      DatabaseConnection.instance = new DatabaseConnection()
    }
    return DatabaseConnection.instance
  }

  // 初始化数据库
  async initRdbStore(context: common.Context): Promise<void> {
    this.rdbStore = await rdb.getRdbStore(context, STORE_CONFIG)
    await this.createTable()
  }

  // 创建表
  private async createTable(): Promise<void> {
    await this.rdbStore!.executeSql(SQL_CREATE_TABLE)
  }
}
```

**本项目对应位置**: `common/data/RdbHelper.ets`

---

#### 步骤 2：封装 CRUD 操作

**单条插入**:
```typescript
async insertData(context: common.Context, contact: Contact): Promise<void> {
  const valueBucket: rdb.ValuesBucket = {
    'name': contact.name,
    'phone': contact.phone,
    'email': contact.email,
    'address': contact.address,
    'avatar': contact.avatar,
    'category': contact.category
  }
  if (this.rdbStore) {
    await this.rdbStore.insert('contact', valueBucket, rdb.ConflictResolution.ON_CONFLICT_REPLACE)
  }
}
```

**批量插入**:
```typescript
async batchInsertData(context: common.Context, array: Contact[]): Promise<void> {
  const valueBuckets: rdb.ValuesBucket[] = []
  for (const item of array) {
    valueBuckets.push({
      'name': item.name,
      'phone': item.phone,
      'email': item.email,
      'address': item.address,
      'avatar': item.avatar,
      'category': item.category
    })
  }
  if (this.rdbStore) {
    await this.rdbStore.batchInsert('contact', valueBuckets)
  }
}
```

**删除**:
```typescript
async deleteData(context: common.Context, contact: Contact): Promise<void> {
  const predicates = new rdb.RdbPredicates('contact')
  predicates.equalTo('id', contact.id)
  await this.rdbStore!.delete(predicates)
}
```

**更新**:
```typescript
async updateData(context: common.Context, contact: Contact): Promise<void> {
  const valueBucket: rdb.ValuesBucket = {
    'name': contact.name,
    'phone': contact.phone,
    'email': contact.email,
    'address': contact.address,
    'avatar': contact.avatar,
    'category': contact.category
  }
  const predicates = new rdb.RdbPredicates('contact')
  predicates.equalTo('id', contact.id)
  await this.rdbStore!.update(valueBucket, predicates, rdb.ConflictResolution.ON_CONFLICT_REPLACE)
}
```

**查询**:
```typescript
async query(context: common.Context): Promise<Contact[]> {
  const predicates = new rdb.RdbPredicates('contact')
  predicates.orderByAsc('category')
  const resultSet = await this.rdbStore!.query(predicates)
  return this.getListFromResultSet(resultSet)
}
```

**本项目对应位置**: `common/data/TravelRepository.ets`、`common/data/MemoryNodeRepository.ets`

---

#### 步骤 3：使用 TaskPool 在子线程执行

```typescript
// TaskPool.ets
import { taskPool } from '@kit.ArkJS'

@Concurrent
async function insertItem(context: common.Context, contact: Contact): Promise<void> {
  return await DatabaseConnection.getInstance().insertData(context, contact)
}

export async function taskPoolExecuteInsert(context: common.Context, contact: Contact): Promise<void> {
  try {
    const task: taskPool.Task = new taskPool.Task(insertItem, context, contact)
    await taskPool.execute(task)
  } catch (err) {
    console.error('insert error:', err)
  }
}

@Concurrent
async function queryItem(context: common.Context): Promise<Contact[]> {
  return await DatabaseConnection.getInstance().query(context)
}

export async function taskPoolExecuteQuery(context: common.Context): Promise<Contact[]> {
  try {
    const task: taskPool.Task = new taskPool.Task(queryItem, context)
    return await taskPool.execute(task) as Contact[]
  } catch (err) {
    console.error('query error:', err)
    return []
  }
}
```

**关键点**:
- 使用 `@Concurrent` 装饰器标记可在 TaskPool 中执行的函数
- 通过 `taskPool.Task` 创建任务，`taskPool.execute()` 执行
- 异步回调处理结果，更新 UI 数据源

---

#### 步骤 4：UI 层调用

```typescript
// AddressBookEdit.ets - 新增联系人
private handleSave() {
  taskPoolExecuteInsert(context, this.result).then(() => {
    DynamicsRouter.popAppRouter()
    this.addCallback(this.result)  // 回调更新列表
  })
}

// AddressBookList.ets - 查询加载
queryRDB() {
  taskPoolExecuteQuery(context).then((contacts: Contact[]) => {
    this.dataArray = contacts.reduce((acc, item) => {
      if (!acc[item.category]) {
        acc[item.category] = []
      }
      acc[item.category].push(item)
      return acc
    }, {} as Record<string, Contact[]>)
    this.updateUI()
  })
}
```

---

### 9.4 对本项目的指导意义

| 参考点 | operaterdbintaskpool 实现 | 本项目应用 |
|--------|--------------------------|-----------|
| 数据库初始化 | `DatabaseConnection.initRdbStore()` | `RdbHelper.initDatabase()` |
| 表创建 | `executeSql(SQL_CREATE_TABLE)` | `RdbHelper.createTables()` |
| 单条插入 | `insert(valuesBucket, ON_CONFLICT_REPLACE)` | `TravelRepository.createTravel()` |
| 批量插入 | `batchInsert(valueBuckets[])` | 通讯录同步场景 |
| 删除 | `delete(predicates)` | `TravelRepository.deleteTravel()` |
| 更新 | `update(valuesBucket, predicates)` | `TravelRepository.updateTravel()` |
| 查询 | `query(predicates)` → `ResultSet` | `TravelRepository.getAllTravels()` |
| 多线程 | `taskPool.execute()` + `@Concurrent` | 大量数据操作时使用 |

---

### 9.5 本项目与参考案例的差异

| 维度 | 通讯录案例 | TravelPin 项目 |
|------|-----------|---------------|
| 数据表 | 单表（contact） | 双表（travels + memory_nodes） |
| 关联关系 | 无 | 外键关联（travel_id） |
| 数据分级 | 无 | S0-S4 敏感度分级 |
| 线程模型 | TaskPool 多线程 | 初期可单线程，后续优化 |
| 云端同步 | 无 | 需与华为云同步集成 |

---

### 9.6 推荐实现顺序

```
1. 参考 RdbConstant.ets → 定义本项目常量（DB_NAME, DB_VERSION, SQL 语句）
         ↓
2. 参考 DatabaseConnection.ets → 实现 RdbHelper 单例和初始化
         ↓
3. 参考 CRUD 封装 → 实现 TravelRepository 和 MemoryNodeRepository
         ↓
4. 参考 AddressBookList.ets → UI 组件调用 Repository 加载数据
         ↓
5. （可选）参考 TaskPool → 大批量数据操作时优化性能
```

---

### 9.7 可复用的代码片段

**STORE_CONFIG 配置**（需根据本项目调整）:
```typescript
const STORE_CONFIG = {
  name: 'TravelPin.db',
  securityLevel: rdb.SecurityLevel.S2  // 本应用到 S2 级别
}
```

**SQL 创建表语句**:
```typescript
const SQL_CREATE_TRAVELS = `
  CREATE TABLE IF NOT EXISTS travels(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    cover_image_uri TEXT,
    start_date INTEGER NOT NULL,
    end_date INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    sensitivity TEXT NOT NULL DEFAULT 'S1'
  )
`

const SQL_CREATE_MEMORY_NODES = `
  CREATE TABLE IF NOT EXISTS memory_nodes(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    travel_id INTEGER NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    poi_name TEXT,
    description TEXT,
    address TEXT,
    mood TEXT,
    tags TEXT,
    photos TEXT,
    "order" INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    sensitivity TEXT NOT NULL DEFAULT 'S2',
    FOREIGN KEY (travel_id) REFERENCES travels(id) ON DELETE CASCADE
  )
`
```

**RdbPredicates 查询条件**:
```typescript
// 按旅行 ID 查询节点
const predicates = new rdb.RdbPredicates('memory_nodes')
predicates.equalTo('travel_id', travelId)
predicates.orderByDesc('created_at')
const resultSet = await rdbStore.query(predicates)

// 删除节点
const deletePredicates = new rdb.RdbPredicates('memory_nodes')
deletePredicates.equalTo('id', nodeId)
await rdbStore.delete(deletePredicates)

// 更新节点
const updatePredicates = new rdb.RdbPredicates('memory_nodes')
updatePredicates.equalTo('id', nodeId)
await rdbStore.update(valueBucket, updatePredicates, rdb.ConflictResolution.ON_CONFLICT_REPLACE)
```

---

### 9.8 注意事项

1. **Context 参数**: 参考案例中所有数据库操作都需要传入 `common.Context` 参数，本项目在 `EntryAbility` 中获取 context 后传递

2. **ResultSet 处理**: 查询返回的 `ResultSet` 需要遍历获取每一列的值，参考案例的 `getListFromResultSet()` 方法

3. **错误处理**: 所有数据库操作都应使用 try-catch 包裹，避免未捕获异常导致应用崩溃

4. **资源释放**: 使用完 `ResultSet` 后应调用 `resultSet.close()` 释放资源

5. **TaskPool 使用**: 仅当数据量大或操作耗时时使用 TaskPool，简单查询可直接在主线程执行

---

## 十一、安全合规要求

### 11.1 数据分级（S0-S4）

| 级别 | 说明 | 本应用示例 | 处理方式 |
|------|------|-----------|----------|
| S0 | 公开数据 | 应用公开配置 | 无需特殊处理 |
| S1 | 一般数据 | 旅行名称、标签、POI 名称 | 正常存储 |
| S2 | 敏感数据 | 经纬度、时间戳、地址 | 标识 + 加密传输 |
| S3 | 个人敏感信息 | 用户草稿、心情标记 | 加密存储 |
| S4 | 高度敏感 | (本应用不涉及) | N/A |

### 11.2 数据脱敏规则

**AI 文案生成时**：
- ✅ 发送：POI 名称（脱敏后）、距离、时长、标签
- ❌ 不发送：精确经纬度、用户身份信息、照片原图

**分享链接生成时**：
- ✅ 发送：旅行元数据（名称、封面、节点摘要）
- ❌ 不发送：精确经纬度、用户草稿

---

## 十二、待实现任务清单

| 优先级 | 任务 | 相关文件 | 状态 |
|--------|------|----------|------|
| P0 | 实现 RdbHelper 基础框架 | `common/data/RdbHelper.ets` | ⏳ |
| P0 | 实现 TravelRepository CRUD | `common/data/TravelRepository.ets` | ⏳ |
| P0 | 实现 MemoryNodeRepository CRUD | `common/data/MemoryNodeRepository.ets` | ⏳ |
| P1 | MapHomeView 集成真实数据 | `feature/map-travel/views/MapHomeView.ets` | ⏳ |
| P1 | NodeDetailPage 集成真实数据 | `feature/map-travel/pages/NodeDetailPage.ets` | ⏳ |
| P1 | NodeEditPage 保存逻辑 | `feature/map-travel/pages/NodeEditPage.ets` | ⏳ |
| P1 | TripDetailPage 集成真实数据 | `feature/map-travel/pages/TripDetailPage.ets` | ⏳ |
| P2 | 同步队列机制 | 待创建 `common/sync/` | ⏳ |
| P2 | ProfileView 同步状态集成 | `feature/profile/views/ProfileView.ets` | ⏳ |
| P2 | AiCopyGenerator 数据集成 | `feature/ai-copy/components/AiCopyGenerator.ets` | ⏳ |

---

## 十三、参考文档

- [HarmonyOS ArkData RDB](https://developer.huawei.com/consumer/cn/doc/)
- [F1 本地存储层任务分配](../F1_local_storage_assignment.md)
- [任务清单](../任务清单.md)
- [HarmonyOS Next 安全规范](../HarmonyOS_Next_Security_Rules.pdf)
- [operaterdbintaskpool 参考案例](../operaterdbintaskpool/README.md)

---

**最后更新**: 2026-03-29
