# TravelPin 测试概述

本文档基于 `test-handoff-for-claude-code.md` 交接文档与实际落地的测试代码编写，记录当前测试全貌。

## 总览

| 统计项 | 数量 |
|--------|------|
| 测试套件 | 8 |
| 用例总数 | 35 |
| 测试入口 | `frontend/entry/src/test/List.test.ets` |

所有测试均通过 Hypium 框架运行，分为**单元测试**和**轻量集成测试**两大类。

---

## 一、单元测试

单元测试位于 `frontend/entry/src/test/unit/` 目录下，聚焦于可独立运行的纯逻辑验证，不依赖真实数据库或网络 I/O。

### 1.1 MultipartFormDataTest

- **测试名称**: `MultipartFormDataTest`
- **对应文件**: `frontend/entry/src/test/unit/common/MultipartFormData.test.ets`
- **被测模块**: `MultipartFormData`
- **测试内容**:
  - 验证生成的 `Content-Type` 头包含 `multipart/form-data; boundary=` 前缀
  - 验证仅含文本字段时能正确构建 multipart payload

### 1.2 ShareErrorMapperTest

- **测试名称**: `ShareErrorMapperTest`
- **对应文件**: `frontend/entry/src/test/unit/social-share/ShareErrorMapper.test.ets`
- **被测模块**: `ShareErrorMapper`
- **测试内容**:
  - 格式化云端照片 preflight 错误，确认输出包含详情行
  - 格式化无效过期时间的发布错误，确认输出包含详情行
  - 验证通用 preflight 错误能透传 `message` 和 `detail` 字段
  - 验证通用发布错误能透传 `errorMessage` 和 `errorDetail` 字段

### 1.3 SharePreflightTest

- **测试名称**: `SharePreflightTest`
- **对应文件**: `frontend/entry/src/test/unit/social-share/SharePreflight.test.ets`
- **被测模块**: `SharePreflight`
- **测试内容**:
  - 空节点列表时拦截并返回 `EMPTY_NODES`
  - 无效过期时间时拦截并返回 `INVALID_EXPIRY`
  - 照片数量不匹配时拦截并返回 `INVALID_PHOTO_COUNT`
  - 云端引用照片在文件大小检查之前拦截，返回 `CLOUD_ONLY_PHOTO`
  - 本地文件缺失时拦截，返回 `LOCAL_PHOTO_MISSING`
  - 合法发布载荷通过验证，确认 `totalPhotoCount` 和 `totalBytes` 正确

### 1.4 SharePhotoHelperTest

- **测试名称**: `SharePhotoHelperTest`
- **对应文件**: `frontend/entry/src/test/unit/social-share/SharePhotoHelper.test.ets`
- **被测模块**: `SharePhotoHelper`
- **测试内容**:
  - 过滤云端引用路径和缺失的本地文件路径
  - 忽略空路径条目
  - `prepareSharePhotos` 阶段收集云端引用、文件缺失、清洗失败三类问题，并仅保留成功清洗的照片
  - `toSanitizedSharePhotos` 验证清洗后的 JPEG 输出包含正确的 `filePath`、`filename`、`contentType` 和 `cleanupPath`
  - `cleanupTemporaryPhotos` 仅清理携带 `cleanupPath` 的照片

### 1.5 ShareServiceTest

- **测试名称**: `ShareServiceTest`
- **对应文件**: `frontend/entry/src/test/unit/social-share/ShareService.test.ets`
- **被测模块**: `ShareService`
- **测试内容**:
  - 照片数量不匹配时在发送请求前拒绝，确认无网络请求发出
  - 构建发布请求时验证 `expiryMinutes`、`replaceLink` 字段（`replaceShortCode`、`replaceExpiry`、`replaceSig`）、`replayPrefs` 字段（`styleKitId`、`bgmId`、`filterId`、`transitionType`、`enableBlurOverlay`、`enableRouteAnimation`、`enableRipple`）均正确写入表单
  - 当未提供 `expiryMinutes` 时回退到 `expiryHours`，未提供可选字段时省略对应表单项
  - 后端返回 400 错误时正确解析错误码、错误消息和错误详情
  - 网络异常（如 socket closed）映射为 `NETWORK_ERROR`
  - 成功解析分享状态查询（`status`）的成功响应信封
  - 正确映射分享状态查询的错误信封
  - 成功解析按旅行撤销（`revokeByTrip`）的成功响应信封

---

## 二、轻量集成测试

轻量集成测试位于 `frontend/entry/src/test/integration/` 目录下，通过注入 fake store、fake predicates 和 fake time provider 来模拟数据库操作，验证数据层完整行为链路。

### 2.1 RdbHelperTest

- **测试名称**: `RdbHelperTest`
- **对应文件**: `frontend/entry/src/test/integration/data/RdbHelper.test.ets`
- **被测模块**: `RdbHelper`
- **测试内容**:
  - 未初始化时调用 `getStore()` 抛出异常，`isInitialized()` 返回 `false`
  - 作用域同步状态（`sync_state`）的写入与更新，确认不同 `owner_uid` 之间隔离
  - 同步队列入队、按用户过滤、按时间排序、以及按实体移除的完整流程
  - `wipeAllUserData()` 跨 `memory_nodes`、`travels`、`sync_queue`、`app_sync_state`、`user_profile` 五张表清除数据

### 2.2 TravelRepositoryTest

- **测试名称**: `TravelRepositoryTest`
- **对应文件**: `frontend/entry/src/test/integration/data/TravelRepository.test.ets`
- **被测模块**: `TravelRepository`
- **测试内容**:
  - 创建旅行并读回，验证 `owner_uid` 作用域、replay 偏好字段（`styleKitId`、`bgmId`、`filterId`、`transitionType`、`enableRipple`、`enableRouteAnimation`、`enableBlurOverlay`）、`syncStatus` 为 `pending_create`
  - 更新已同步到云端的旅行，验证 `syncStatus` 转为 `pending_update`、`version` 递增、`updatedAt` 更新
  - 删除旅行前先清理关联的子节点（`memory_nodes`），确认旅行和子节点均被移除

### 2.3 MemoryNodeRepositoryTest

- **测试名称**: `MemoryNodeRepositoryTest`
- **对应文件**: `frontend/entry/src/test/integration/data/MemoryNodeRepository.test.ets`
- **被测模块**: `MemoryNodeRepository`
- **测试内容**:
  - 创建节点时自动分配下一个 `nodeOrder`，验证 `syncStatus` 为 `pending_create`、`visitedAt` 注入正确
  - 将节点移动到另一旅行时，`nodeOrder` 追加到目标旅行的末尾，`syncStatus` 转为 `pending_update`，`version` 递增
  - 节点重排序后确认顺序符合指定顺序，所有被移动节点的 `syncStatus` 标记为 `pending_reorder`

---

## 三、公共测试基础设施

| 文件 | 用途 |
|------|------|
| `frontend/entry/src/test/integration/data/FakeRdbSupport.ets` | 提供 `FakeStore`、`FakePredicates`、`FakeResultSet`、`TimeSequence` 等类，模拟 RDB 操作 |
| `frontend/entry/src/test/List.test.ets` | 测试入口，注册并执行全部 8 个测试套件 |

---

## 四、测试分类总表

| 大类 | 测试名称 | 用例数 | 文件路径 |
|------|---------|--------|----------|
| 单元测试 | MultipartFormDataTest | 2 | `frontend/entry/src/test/unit/common/MultipartFormData.test.ets` |
| 单元测试 | ShareErrorMapperTest | 4 | `frontend/entry/src/test/unit/social-share/ShareErrorMapper.test.ets` |
| 单元测试 | SharePreflightTest | 6 | `frontend/entry/src/test/unit/social-share/SharePreflight.test.ets` |
| 单元测试 | SharePhotoHelperTest | 5 | `frontend/entry/src/test/unit/social-share/SharePhotoHelper.test.ets` |
| 单元测试 | ShareServiceTest | 8 | `frontend/entry/src/test/unit/social-share/ShareService.test.ets` |
| 轻量集成测试 | RdbHelperTest | 4 | `frontend/entry/src/test/integration/data/RdbHelper.test.ets` |
| 轻量集成测试 | TravelRepositoryTest | 3 | `frontend/entry/src/test/integration/data/TravelRepository.test.ets` |
| 轻量集成测试 | MemoryNodeRepositoryTest | 3 | `frontend/entry/src/test/integration/data/MemoryNodeRepository.test.ets` |
