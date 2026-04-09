# F1 本地存储层任务分配说明

**创建日期**: 2026-03-24
**任务 ID**: F1.1, F1.2, F1.3, F1.4

---

## 一、核心设计理念（必须理解）

### 1.1 三层存储架构

```
┌─────────────────────────────────────────────────────────────┐
│ 存储层           │ 位置          │ 存储内容                  │
├─────────────────────────────────────────────────────────────┤
│ 本地存储层 (F1)   │ 设备本地       │ 元数据、结构化数据         │
│ 云端同步层        │ 华为云空间     │ 照片原图、视频、备份       │
│ 后端服务层        │ 自建服务器     │ AI 生成、分享验证          │
└─────────────────────────────────────────────────────────────┘
```

> **关键**：F1 的 RDB 是 **HarmonyOS 本地数据库**，不是华为云存储！

### 1.2 数据存储边界

| 存储 ✅ | 不存储 ❌ |
|--------|----------|
| 旅行元数据（名称、日期范围、封面 URI） | 照片原图（华为云存储） |
| 记忆节点（经纬度、描述、地址、时间戳） | 视频文件 |
| 用户草稿、标签、心情标记 | |

### 1.3 模块依赖关系

```
Repository 层 (TravelRepository, MemoryNodeRepository)
        ↓
RdbHelper 层 (底层 RDB 封装 + 数据分级)
        ↓
@kit.ArkData.RDB (HarmonyOS SDK)
```

---

## 二、技术规范要求

### 2.1 数据分级（华为鸿蒙安全合规）⚠️

**必须在 `RdbHelper.ets` 中实现 S0-S4 分级标识**：

| 级别 | 说明 | 本应用示例 |
|------|------|-----------|
| S0 | 公开数据 | 应用公开配置 |
| S1 | 一般数据 | 旅行名称、标签 |
| S2 | 敏感数据 | 经纬度、时间戳、地址 |
| S3 | 个人敏感信息 | 用户草稿、心情标记 |
| S4 | 高度敏感 | (本应用不涉及) |

### 2.2 依赖的 Kit

```typescript
import { RDB } from '@kit.ArkData';      // RDB 数据库操作
// 后续可能需要
import { ArkCrypto } from '@kit.ArkCrypto'; // 敏感数据加密
```

### 2.3 文件结构

```
common/data/
├── RdbHelper.ets              // 底层数据库助手（含数据分级机制）
├── TravelRepository.ets       // 旅行实体 CRUD 操作
├── MemoryNodeRepository.ets   // 记忆节点 CRUD 操作
└── LocalStorage.ets           // Preferences 存储（F7.3）
```

---

## 三、详细任务说明

### 3.1 F1.1 - RdbHelper.ets

**职责**: RDB 数据库助手，封装底层数据库操作

**实现要点**:
- [ ] 创建/打开 RDB 数据库
- [ ] 数据表创建（Travel 表、MemoryNode 表）
- [ ] 数据分级标识（S0-S4）的存储和管理
- [ ] 数据库版本管理（onUpgrade）

**数据表结构参考**:
```typescript
// Travel 表
{
  id: number;           // 主键
  name: string;         // S1 - 旅行名称
  startDate: number;    // S1 - 开始时间戳
  endDate: number;      // S1 - 结束时间戳
  coverUri: string;     // S1 - 封面 URI（华为云）
  sensitivity: string;  // S1 - 数据分级标识
}

// MemoryNode 表
{
  id: number;           // 主键
  travelId: number;     // S1 - 关联旅行 ID
  latitude: number;     // S2 - 纬度
  longitude: number;    // S2 - 经度
  description: string;  // S2 - 描述
  address: string;      // S2 - 地址
  timestamp: number;    // S2 - 时间戳
  mood?: string;        // S3 - 心情（可选）
  draft?: string;       // S3 - 用户草稿（可选）
  sensitivity: string;  // S2 - 数据分级标识
}
```

### 3.2 F1.2 - TravelRepository.ets

**职责**: 旅行实体的 CRUD 操作

**接口定义**:
```typescript
interface TravelRepository {
  createTravel(travel: Travel): Promise<number>;    // 返回 ID
  getTravelById(id: number): Promise<Travel | null>;
  getAllTravels(): Promise<Travel[]>;
  updateTravel(travel: Travel): Promise<boolean>;
  deleteTravel(id: number): Promise<boolean>;
}
```

### 3.3 F1.3 - MemoryNodeRepository.ets

**职责**: 记忆节点实体的 CRUD 操作

**接口定义**:
```typescript
interface MemoryNodeRepository {
  createNode(node: MemoryNode): Promise<number>;
  getNodeById(id: number): Promise<MemoryNode | null>;
  getNodesByTravelId(travelId: number): Promise<MemoryNode[]>;
  updateNode(node: MemoryNode): Promise<boolean>;
  deleteNode(id: number): Promise<boolean>;
}
```

### 3.4 F1.4 - 数据敏感度分级

**职责**: 在 `RdbHelper.ets` 中实现数据分级机制

**实现要点**:
- [ ] 定义数据分级枚举/常量
- [ ] 在数据模型中添加 `sensitivity` 字段
- [ ] 根据分级决定是否需要加密存储
- [ ] 导出时根据分级过滤数据

---

## 四、安全合规检查清单

根据 HarmonyOS Next 安全规范：

| 安全要求 | 状态 | 实现位置 |
|---------|------|----------|
| 数据分级处理（S0-S4 标识） | ⚠️ 必须实现 | RdbHelper.ets |
| 权限最小化原则 | ⚠️ 注意 | 只申请必要的 RDB 权限 |
| 敏感数据加密存储 | ⚠️ 后续 | S2+ 数据考虑加密 |
| EXIF 敏感信息剥离 | ⚠️ 后续 | F7.1 ExifStripper.ets |

---

## 五、测试验收标准

### 5.1 功能验收
- [ ] RDB 数据库正确创建和初始化
- [ ] 所有数据模型有 S0-S4 分级标识
- [ ] CRUD 操作支持离线使用（无网络时正常）
- [ ] 不存储照片原图（只存 URI）
- [ ] Repository 层接口清晰，可被上层调用

### 5.2 安全验收
- [ ] 数据分级标识正确应用到所有字段
- [ ] S2+ 敏感数据有标识
- [ ] 无硬编码的敏感信息

### 5.3 代码验收
- [ ] 遵循 ArkTS 语法规范
- [ ] 使用类型提示（Type Hints）
- [ ] 错误处理完善

---

## 六、实现建议

### 6.1 实现顺序
```
1. RdbHelper.ets (基础框架 + 数据分级)
        ↓
2. TravelRepository.ets (依赖 RdbHelper)
        ↓
3. MemoryNodeRepository.ets (依赖 RdbHelper)
        ↓
4. 集成测试
```

### 6.2 参考代码结构

```typescript
// RdbHelper.ets
export enum SensitivityLevel {
  S0 = 'S0',  // 公开
  S1 = 'S1',  // 一般
  S2 = 'S2',  // 敏感
  S3 = 'S3',  // 个人敏感
  S4 = 'S4'   // 高度敏感
}

export class RdbHelper {
  private static instance: RdbHelper;
  private rdb: RDB;

  private constructor() {}

  static getInstance(): RdbHelper {
    if (!RdbHelper.instance) {
      RdbHelper.instance = new RdbHelper();
    }
    return RdbHelper.instance;
  }

  async init(): Promise<void> {
    // 初始化数据库
  }

  async createTable(): Promise<void> {
    // 创建数据表
  }
}

// TravelRepository.ets
export class TravelRepository {
  private rdbHelper: RdbHelper;

  constructor() {
    this.rdbHelper = RdbHelper.getInstance();
  }

  // CRUD 实现...
}
```

---

## 七、与其他模块的集成点

### 7.1 云端同步
```
RDB 数据 → LocalStorage.ets → 华为云备份
```

### 7.2 AI 功能
```
MemoryNodeRepository → MetadataAggregator → AI Gateway
(本地数据聚合)         (脱敏后发送)
```

### 7.3 安全模块
```
ExifStripper.ets → 照片去 EXIF → 上传华为云
ShareLinkSigner.ets → HMAC 签名 → 分享验证
```

---

## 八、常见问答

### Q1: 为什么要用 RDB 而不是 Preferences？
**A**: Preferences 适合存储简单的键值对（如用户设置），RDB 适合存储结构化的关系型数据（如旅行、记忆节点），支持查询和关联。

### Q2: 数据分级是必须的吗？
**A**: 是的，这是华为鸿蒙的安全合规要求。在应用审核时可能会检查。

### Q3: 照片原图存储在哪里？
**A**: 照片原图存储在华为云空间，本地 RDB 只存储 URI 引用。

### Q4: 需要实现数据加密吗？
**A**: 本期可以先实现分级标识，加密可以在后续迭代中使用 `@kit.ArkCrypto` 实现。

---

## 九、参考文档

- [HarmonyOS ArkData RDB](https://developer.huawei.com/consumer/cn/doc/)
- [HarmonyOS 安全规范](https://developer.huawei.com/consumer/cn/doc/)
- 项目文档：`memory/01_project_state.md`
- 项目文档：`memory/03_task_backlog.md`

---

## 十、任务分配模板

```markdown
### 任务：F1 - 本地存储层实现
- **负责人**: [姓名]
- **截止日期**: [YYYY-MM-DD]

#### 子任务：
1. F1.1: RdbHelper.ets - 基础 RDB 封装 + 数据分级
2. F1.2: TravelRepository.ets - 旅行 CRUD
3. F1.3: MemoryNodeRepository.ets - 记忆节点 CRUD
4. F1.4: 数据分级 (S0-S4) - 集成到 RdbHelper

#### 验收标准：
- [ ] RDB 数据库正确创建
- [ ] 所有字段有 S0-S4 分级标识
- [ ] CRUD 操作支持离线使用
- [ ] 不存储照片原图（只存 URI）
```

---

**最后更新**: 2026-03-24
