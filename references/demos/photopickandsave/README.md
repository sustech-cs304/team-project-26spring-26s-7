# 图片选择和下载保存案例

## 简介

本示例介绍图片相关场景的使用：包含访问手机相册图片、选择预览图片并显示选择的图片到当前页面，下载并保存网络图片到手机相册或到指定用户目录。

## 源码仓库

**官方仓库**: https://gitee.com/harmonyos-cases/cases

**案例路径**: `CommonAppDevelopment/feature/photopickandsave/`

## 快速获取

```bash
# 克隆官方案例仓库
git clone https://gitee.com/harmonyos-cases/cases.git

# 进入本案例目录
cd cases/CommonAppDevelopment/feature/photopickandsave/
```

## 核心功能

1. **访问手机相册**: 使用 PhotoViewPicker 拉起图库界面
2. **图片预览选择**: 支持预览并选择多个图片
3. **网络图片下载**: 下载网络图片到手机相册
4. **指定路径保存**: 保存图片到用户选择的指定路径

## 核心技术点

| API | 用途 |
|-----|------|
| `photoViewPicker.select()` | 拉起图库选择图片 |
| `request.agent` | 文件下载任务 |
| `photoAccessHelper` | 相册访问助手 |
| `filePicker` | 文件选择器 |

## 关键文件参考

- `PhotoPickerPage.ets` - 图片选择页面
- `DownloadPage.ets` - 下载保存页面

## 官方文档

- [PhotoViewPicker API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-photoaccesshelper-V5)
- [文件上传下载](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-request-V5)
