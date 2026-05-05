# Social Share Module 1 Codex Tasklist

目标：完成“前端收集并打包路线的图文信息发送”，优先打通安全、可预检的图片打包链路。

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
  说明：个人页默认有效期通过 `AppStorage` 接到 `SharePage`，发布时真实影响 `expiryHours`。
- [x] 前端体量预检骨架
  说明：发布前检查节点数、图片数、单图大小、预计总请求体大小、有效期范围，并统一返回错误提示模型。
- [x] 细化错误码映射与交互文案
  说明：统一映射前端预检错误和后端 `publish` 错误码，页面不再直接显示原始错误码或后端英文常量。

## Next

1. 增加分享发布阶段提示
2. 做 `cloud-only` 自动下载回源
3. 为 `SharePhotoHelper` / `ShareService` 补测试
