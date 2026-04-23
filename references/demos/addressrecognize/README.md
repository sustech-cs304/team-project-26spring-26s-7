# AI 图片文字智能识别

## 简介

本示例使用 CoreVisionKit 智能识别图片中的文字，并使用 NaturalLanguageKit 自然语言处理工具集将识别的文字智能转换为姓名、手机、地址等信息。

## 源码仓库

**官方仓库**: https://gitee.com/harmonyos-cases/cases

**案例路径**: `CommonAppDevelopment/feature/addressrecognize/`

## 快速获取

```bash
# 克隆官方案例仓库
git clone https://gitee.com/harmonyos-cases/cases.git

# 进入本案例目录
cd cases/CommonAppDevelopment/feature/addressrecognize/
```

## 核心功能

1. **图片文字识别**: 使用 CoreVisionKit 识别图片中的文字
2. **自然语言处理**: 使用 NaturalLanguageKit 提取姓名、手机、地址
3. **图片裁剪**: 支持拖动裁剪框截取关键区域

## 核心技术点

| API | 用途 |
|-----|------|
| `textRecognition.recognizeText()` | 图片文字识别 |
| `textProcessing.textProcessing()` | 自然语言处理 |
| `photoViewPicker` | 图片选择器 |

## 关键文件参考

- `AddressRecognitionPage.ets` - 主页面
- `AddressRecognitionViewModel.ets` - 视图模型

## 官方文档

- [文字识别 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/core-vision-text-recognition-api-V5)
- [自然语言处理 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/natural-language-api-V5)
