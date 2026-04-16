# 在 TaskPool 线程中操作关系型数据库

## 简介

本示例通过通讯录场景实例，介绍了在 TaskPool 线程中操作关系型数据库的方法，涵盖了单条插入、批量插入、删除、修改和查询等基本操作。

## 源码仓库

**官方仓库**: https://gitee.com/harmonyos-cases/cases

**案例路径**: `CommonAppDevelopment/feature/operaterdbintaskpool/`

## 快速获取

```bash
# 克隆官方案例仓库
git clone https://gitee.com/harmonyos-cases/cases.git

# 进入本案例目录
cd cases/CommonAppDevelopment/feature/operaterdbintaskpool/
```

## 核心功能

1. **数据库初始化**: 使用 `rdb.getRdbStore()` 创建数据库
2. **单条插入**: 新增联系人
3. **批量插入**: 通讯录同步
4. **删除/修改**: 联系人管理
5. **查询操作**: 联系人列表展示

## 核心技术点

| API | 用途 |
|-----|------|
| `rdb.getRdbStore()` | 初始化关系型数据库 |
| `rdbStore.insert()` | 插入数据 |
| `rdbStore.update()` | 更新数据 |
| `rdbStore.delete()` | 删除数据 |
| `rdbStore.query()` | 查询数据 |
| `taskpool` | 多线程操作数据库 |

## 关键步骤

1. 初始化数据库并创建表
2. 封装 CRUD 操作方法
3. 使用 TaskPool 执行数据库操作
4. 通过Promise 异步回调处理结果

## 官方文档

- [关系型数据库](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-data-relationships-V5)
- [TaskPool](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-taskpool-V5)
