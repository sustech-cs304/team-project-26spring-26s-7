# Test Checklist - 测试清单

**Last Updated**: 2026-05-06
**Project**: TravelPin - HarmonyOS Travel Journal App

---

## 测试策略说明

**目标**: 确保后续增广 AI、分享、跨设备功能开发安全

**优先级定义**:
- **P0**: 阻塞性测试，必须通过才能继续开发
- **P1**: 重要测试，影响核心功能稳定性
- **P2**: 优化测试，提升用户体验

**测试分层**:
```
┌─────────────────────────────────────────────────────────────┐
│  P0 关键 Feature 集成测试 (端到端数据流)                      │
│  ├── 照片选择 → 节点创建流程                                 │
│  ├── 地图选点 → 数据保存流程                                 │
│  └── 服务层接口一致性                                        │
├─────────────────────────────────────────────────────────────┤
│  P1 数据层单元测试 (数据完整性)                               │
│  ├── 数据库初始化                                            │
│  ├── Repository CRUD                                         │
│  └── 数据模型验证                                            │
├─────────────────────────────────────────────────────────────┤
│  P2 UI 自动化测试 (界面交互)                                  │
│  ├── 页面导航                                                │
│  └── 组件交互                                                │
└─────────────────────────────────────────────────────────────┘
```

---

## 测试概览

| 测试类型 | 数量 | P0 | P1 | P2 | 通过率 | 状态 |
|---------|------|----|----|----|----|------|
| Feature 集成测试 | 12 | 12 | - | - | 0/12 | 🔴 阻塞 |
| 数据层单元测试 | 10 | - | 10 | - | 0/10 | 🔴 待开始 |
| 服务层接口测试 | 5 | 5 | - | - | 0/5 | 🔴 阻塞 |
| UI 自动化测试 | 6 | - | - | 6 | 0/6 | 🟡 低优先级 |
| **总计** | **33** | **17** | **10** | **6** | **0/33** | - |

---

## P0: 关键 Feature 集成测试 (阻塞后续开发)

### F1. 照片选择 → 节点创建流程 (影响分享功能)

| ID | 测试用例 | 验证点 | 状态 | 日期 |
|----|---------|--------|------|------|
| **T-F001** | 选择照片 → 沙箱存储 → URI 记录 | 照片文件正确保存到应用沙箱 | ⬜ | - |
| **T-F002** | 创建节点 → 关联照片 → 数据库写入 | MemoryNode.photos 数组正确存储 | ⬜ | - |
| **T-F003** | 查询节点 → 读取照片 → 显示正确 | 照片能从沙箱正确读取并显示 | ⬜ | - |
| **T-F004** | 删除节点 → 清理照片文件 | 沙箱中的照片文件被正确清理 | ⬜ | - |

**失败影响**: 无法分享照片、照片丢失风险

---

### F2. 地图选点 → 数据保存流程 (影响跨设备同步)

| ID | 测试用例 | 验证点 | 状态 | 日期 |
|----|---------|--------|------|------|
| **T-F005** | 地图点击 → AppStorage 传值 → NodeEdit 接收 | 经纬度数据正确传递 | ⬜ | - |
| **T-F006** | 保存节点 → 数据库写入 → 地图刷新显示 | 新节点出现在地图上 | ⬜ | - |

**失败影响**: 跨设备数据同步失败、节点丢失

---

### F3. 服务层接口一致性 (影响 AI 文案生成)

| ID | 测试用例 | 验证点 | 状态 | 日期 |
|----|---------|--------|------|------|
| **T-F007** | `IDataService` 接口定义完整性 | 所有 CRUD 方法签名正确 | ⬜ | - |
| **T-F008** | `RdbDataService` 实现与 `MockDataService` 行为一致 | 相同输入产生相同结构输出 | ⬜ | - |

**失败影响**: AI 服务调用失败、数据不一致

---

### F4. 社交分享图片打包发布流程 (影响 H5 海报分享)

| ID | 测试用例 | 验证点 | 状态 | 日期 |
|----|---------|--------|------|------|
| **T-F009** | 本地照片分享 → EXIF 清洗 → multipart 上传 | 上传的是清洗后临时 JPEG，`photoCount` 与 `photo_N` 数量一致 | ⬜ | - |
| **T-F010** | cloud-only / 本地缺图 / 清洗失败 | 前端阻止发布并显示可理解错误，不静默丢图 | ⬜ | - |
| **T-F011** | 切换有效期重新发布 | 新请求重新打包图片，旧链接通过 replace 流程撤销 | ⬜ | - |
| **T-F012** | 5 分钟测试有效期 | 前端发送 `expiryMinutes=5`，后端返回的链接按分钟级过期 | ⬜ | - |

**失败影响**: 分享照片可能丢失、EXIF 泄露、链接有效期不符合预期或旧链接堆积

---

## P1: 数据层单元测试 (核心稳定性)

### D1. RdbHelper 数据库初始化

| ID | 测试用例 | 验证点 | 状态 | 日期 |
|----|---------|--------|------|------|
| T-D001 | 数据库初始化成功 | RdbStore 对象非空 | ⬜ | - |
| T-D002 | 表结构创建正确 | MemoryNode、Trip、ReplayRoute 表存在 | ⬜ | - |
| T-D003 | 数据库版本升级 | 升级脚本正确执行 | ⬜ | - |

### D2. TravelRepository CRUD

| ID | 测试用例 | 验证点 | 状态 | 日期 |
|----|---------|--------|------|------|
| T-D004 | insert() 返回有效 ID | ID > 0 | ⬜ | - |
| T-D005 | queryById() 返回正确数据 | 字段值与插入一致 | ⬜ | - |
| T-D006 | update() 修改生效 | 查询结果为新值 | ⬜ | - |
| T-D007 | delete() 数据移除 | 查询返回空 | ⬜ | - |

### D3. MemoryNodeRepository 关联查询

| ID | 测试用例 | 验证点 | 状态 | 日期 |
|----|---------|--------|------|------|
| T-D008 | queryByTripId() 返回该路线所有节点 | 节点数量正确 | ⬜ | - |
| T-D009 | 级联删除：删除 Trip 时删除关联节点 | 孤儿节点清理 | ⬜ | - |
| T-D010 | photos JSON 序列化/反序列化 | 数组正确存储和读取 | ⬜ | - |

---

## P2: UI 自动化测试 (用户体验)

### U1. 页面导航测试

| ID | 测试用例 | 验证点 | 状态 | 日期 |
|----|---------|--------|------|------|
| T-UI001 | 地图主页 → 节点详情页 | 页面正确跳转 | ⬜ | - |
| T-UI002 | 节点详情 → 编辑页 → 返回 | 数据保持一致 | ⬜ | - |
| T-UI003 | LocationPicker → 返回 → 位置显示 | 选点结果正确显示 | ⬜ | - |

### U2. 旅程回放测试

| ID | 测试用例 | 验证点 | 状态 | 日期 |
|----|---------|--------|------|------|
| T-UI004 | 回放动画启动 | 地图视角正确移动 | ⬜ | - |
| T-UI005 | 照片卡片随节点显示 | 照片在正确时机出现 | ⬜ | - |
| T-UI006 | 进度条与动画同步 | 进度百分比正确 | ⬜ | - |

---

## 状态标记说明

| 标记 | 含义 | 优先级处理 |
|------|------|-----------|
| ⬜ | 待测 | 按优先级排队 |
| 🔄 | 进行中 | 当前正在执行 |
| ✅ | 通过 | 可继续后续开发 |
| ❌ | 失败 | **P0 必须修复后再继续** |
| ⏭️ | 跳过 | P2 可延后 |

---

## 测试执行计划

### Week 1: P0 Feature 集成测试 (阻塞级)

**目标**: 通过所有 P0 测试，解除后续开发阻塞

| 日期 | 测试内容 | 预期结果 |
|------|---------|---------|
| Day 1-2 | F1 照片选择流程 | 4/4 通过 |
| Day 3-4 | F2 地图选点流程 | 2/2 通过 |
| Day 5 | F3 服务层接口 | 2/2 通过 |

### Week 2: P1 数据层单元测试

**目标**: 确保数据完整性

| 日期 | 测试内容 | 预期结果 |
|------|---------|---------|
| Day 1-2 | D1 数据库初始化 | 3/3 通过 |
| Day 3-4 | D2 Repository CRUD | 4/4 通过 |
| Day 5 | D3 关联查询 | 3/3 通过 |

### Week 3: P2 UI 自动化测试

**目标**: 用户体验验证

---

## 测试执行记录

### 2026-04-09

- 初始化测试清单

### 2026-05-06

- 增加 social-share 图片打包发布流程 P0 测试项，覆盖 EXIF 清洗、cloud-only 阻断、切档 replace、5 分钟有效期。
- 制定优先级策略
- 暂无测试执行

---

## 关键测试脚本示例

### T-F001: 照片选择 → 沙箱存储

```typescript
// entry/src/main/ets/test/integration/PhotoFlowTest.ets
import { describe, it, assert, beforeAll, afterAll } from '@ohos/hypium';
import { PhotoPickerUtil } from '../../common/utils/PhotoPickerUtil';
import { MemoryNodeRepository } from '../../common/data/MemoryNodeRepository';
import fs from '@ohos.file.fs';

describe('PhotoFlowIntegrationTest', () => {
  it('T-F001: 照片选择后正确保存到沙箱', async () => {
    // 1. 选择照片 (Mock)
    const uris = await PhotoPickerUtil.pickImages(1);
    assert.assertEqual(uris.length, 1);

    // 2. 复制到沙箱
    const sandboxPath = await PhotoPickerUtil.copyToSandbox(uris[0]);
    assert.assertNotNull(sandboxPath);

    // 3. 验证文件存在
    const exists = fs.accessSync(sandboxPath);
    assert.assertTrue(exists);
  });
});
```

### T-F005: 地图选点数据传递

```typescript
// entry/src/main/ets/test/integration/LocationPickerFlowTest.ets
describe('LocationPickerFlowTest', () => {
  it('T-F005: AppStorage 正确传递经纬度', async () => {
    // 1. 设置 AppStorage
    AppStorage.setOrCreate('selectedLatitude', 22.5);
    AppStorage.setOrCreate('selectedLongitude', 114.0);

    // 2. 模拟 NodeEditPage 读取
    const lat = AppStorage.get<number>('selectedLatitude');
    const lng = AppStorage.get<number>('selectedLongitude');

    // 3. 验证
    assert.assertEqual(lat, 22.5);
    assert.assertEqual(lng, 114.0);
  });
});
```

### T-D001: 数据库初始化

```typescript
// entry/src/main/ets/test/unit/RdbHelperTest.ets
import { RdbHelper } from '../../common/data/RdbHelper';

describe('RdbHelperTest', () => {
  it('T-D001: 数据库初始化成功', async () => {
    const helper = new RdbHelper();
    const rdbStore = await helper.init();
    assert.assertNotNull(rdbStore);
  });

  it('T-D002: 表结构创建正确', async () => {
    const helper = new RdbHelper();
    await helper.init();

    // 验证表存在
    const tables = await helper.queryTables();
    assert.assertTrue(tables.includes('MemoryNode'));
    assert.assertTrue(tables.includes('Trip'));
    assert.assertTrue(tables.includes('ReplayRoute'));
  });
});
```

---

## 测试框架参考

- **Test Kit 文档**: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/test-kit-overview
- **@ohos.UiTest API**: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-uitest
- **单元测试框架**: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/unittest-guidelines
- **关系型数据库测试**: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-data-persistence-by-rdb-store
