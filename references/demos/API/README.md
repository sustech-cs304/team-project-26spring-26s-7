# API 设计与调用参考

## 简介

本目录包含 3 个与 API 设计、HTTP 请求/响应、服务器端点调用相关的鸿蒙参考项目。

## 源码仓库

**官方仓库**: https://gitee.com/harmonyos-cases/cases

**案例路径**: `CommonAppDevelopment/feature/API/`

## 快速获取

```bash
# 克隆官方案例仓库
git clone https://gitee.com/harmonyos-cases/cases.git

# 进入本案例目录
cd cases/CommonAppDevelopment/feature/API/
```

## 子项目列表

| 项目 | 功能 | 适用场景 |
|------|------|---------|
| `videotrimmer` | 视频上传下载完整示例 | 文件上传下载、进度监听 |
| `networkstatusobserver` | 网络状态监听示例 | 根据网络状态调整应用行为 |
| `HttpRequest` | 简单 HTTP 请求示例 | 基础 API 调用 |

## 核心技术点

| API | 用途 |
|-----|------|
| `http.createHttp().request()` | HTTP 数据请求 |
| `request.agent` | 上传下载任务管理 |
| `connection.createNetConnection()` | 网络状态监听 |
| `preferences` | 数据持久化 |

## 推荐阅读顺序

1. **HttpRequest** - 先了解最简单的 HTTP 请求
2. **videotrimmer** - 重点学习上传下载封装
3. **networkstatusobserver** - 学习网络状态监听

## 官方文档

- [HTTP 数据请求](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-http-V5)
- [上传下载任务](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-request-V5)
- [网络管理](https://developer.huawei.com/consumer/cn/doc/best-practices-V5/bpta-network-management-V5)
