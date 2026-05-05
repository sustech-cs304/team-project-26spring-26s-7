# Social Share Module 1 Codex Tasklist

目标：完成“前端收集并打包路线的图文信息发送”，优先打通安全、可预检、可解释错误的图片打包发布链路。

## Done

- [x] 盘点当前 `feature/social-share` 已有的请求组装与上传链路
- [x] 对照 `feature/ai` 学习并复用 EXIF 清洗思路
- [x] 接入分享前图片 EXIF 清洗
  说明：对分享图片生成临时 JPEG 副本，移除 EXIF 后再参与 `photo_N` 上传。
- [x] 清理分享链路产生的临时图片
  说明：请求结束后立即删除，应用启动时也兜底清理异常残留。
- [x] 显式阻止静默丢图
  说明：遇到 `cloud-only`、本地文件丢失、清洗失败时直接阻止发布，不再静默减少 `photoCount`。
- [x] 用户默认分享有效期接线
  说明：个人页默认有效期通过 `AppStorage` 接到 `SharePage`，发布时真实影响默认有效期。
- [x] 前端体量预检骨架
  说明：发布前检查节点数、图片数、单图大小、预计总请求体大小、有效期范围，并统一返回错误提示模型。
- [x] 细化错误码映射与交互文案
  说明：统一映射前端预检错误和后端 `publish` 错误码，页面不再直接显示原始错误码或后端英文常量。
- [x] 合并远端多档有效期与自动撤销旧链接方案
  说明：吸收远端 4 档有效期选择器、`expiryMinutes`、`ReplaceLink` 和 `replaceShortCode/replaceExpiry/replaceSig` 流程，同时保留本地 EXIF 清洗、预检和错误映射。

## Merge Strategy: 2026-05-06

本次合并的关键冲突是“远端缓存清洗后照片用于切档重发”和“本地发布后立即清理清洗临时文件”之间的生命周期冲突。最终方案是缓存源数据，不跨发布缓存清洗后的 `SharePhoto[]`。

保留内容：

- 保留本地 `ImageSanitizer`、`SharePhotoHelper.prepareSharePhotos`、`SharePreflight`、`ShareErrorMapper`。
- 保留远端 `expiryOptions`、`selectedExpiryIdx`、`ReplaceLink`、`lastLink` 和切档自动撤销旧链接能力。
- `ShareService.publish()` 同时支持 `cleanupPath?: string`、`expiryMinutes?: number`、`replace?: ReplaceLink`。
- `ShareTypes.ets` 同时保留预检模型和远端 `PublishOk.sig / ReplaceLink` 契约。

缓存策略：

- 缓存 `cachedReq: SharePublishRequest | null`。
- 缓存 `cachedNodes: MemoryNode[]`，用于切档时重新生成上传照片。
- 不缓存跨发布复用的清洗后临时文件。
- `photos: SharePhoto[]` 只作为单次 `publishShare()` 的局部变量存在，上传结束后立即清理。

新的上传流程：

1. 进入 `SharePage` 后解析 `tripId`。
2. 第一次发布时从 RDB 读取 `trip + nodes`，生成并缓存 `cachedReq + cachedNodes`。
3. 根据个人页默认 `shareLinkExpiryDays` 初始化页面有效期档位。
4. 每次发布前基于 `cachedNodes` 调用 `SharePhotoHelper.prepareSharePhotos()`。
5. `prepareSharePhotos()` 对本地照片生成清洗 JPEG 临时副本；遇到 `cloud-only`、本地缺图、清洗失败时返回 issue。
6. `SharePreflight.validatePublish()` 检查 issue、节点数、照片数、单图大小、总请求体大小和有效期。
7. 通过预检后调用 `ShareService.publish(req, photos, hours, minutes, replace)`。
8. 首次发布不传 `replace`；切换有效期后传上一条成功链接的 `ReplaceLink`，后端在新链接成功后撤销旧链接。
9. 发布成功后记录新的 `lastLink`，用于下一次切档 replace。
10. 无论成功失败，`finally` 都清理本次生成的清洗临时图片。

后端契约状态：

- 最新后端已支持 `expiryMinutes` 优先于 `expiryHours`。
- 最新后端已支持 `replaceShortCode/replaceExpiry/replaceSig`。
- 最新后端 `PublishOk` 已返回 `sig`，前端不需要解析 URL。

## Next

1. 增加分享发布阶段提示
2. 做 `cloud-only` 自动下载回源
3. 为 `SharePhotoHelper` / `ShareService` 补测试
