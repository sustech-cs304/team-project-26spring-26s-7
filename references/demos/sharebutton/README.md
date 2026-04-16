# 分享二维码按钮案例

## 简介

本示例介绍如何在应用中通过 URL 自动生成二维码，并通过 Share Kit 的接口拉起系统分享。

## 源码仓库

**官方仓库**: https://gitee.com/harmonyos-cases/cases

**案例路径**: `CommonAppDevelopment/feature/sharebutton/`

## 快速获取

```bash
# 克隆官方案例仓库
git clone https://gitee.com/harmonyos-cases/cases.git

# 进入本案例目录
cd cases/CommonAppDevelopment/feature/sharebutton/
```

## 核心功能

1. **二维码生成**: 通过 URL 自动生成二维码图片
2. **系统分享**: 使用 Share Kit 拉起系统分享框
3. **多渠道分享**: 支持微信、微博、短信等渠道

## 核心技术点

| API | 用途 |
|-----|------|
| `generateBarcode.createBarcode()` | 生成二维码图片 |
| `systemShare.share()` | 拉起系统分享 |
| `canIUse()` | 检查系统能力 |

## 关键文件参考

- `ShareButtonPage.ets` - 分享页面
- `QRCodeGenerator.ets` - 二维码生成工具

## 官方文档

- [二维码生成 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-generatebarcode-V5)
- [Share Kit](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/sharesdk-V5)
