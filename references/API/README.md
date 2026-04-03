# API 设计与调用参考项目导读

本目录包含 3 个与 API 设计、HTTP 请求/响应、服务器端点调用相关的鸿蒙参考项目。

---

## 📁 项目结构

```
API/
├── README.md                      # 本导读文件
├── videotrimmer/                  # 视频上传下载完整示例 ⭐ 推荐
│   ├── src/main/ets/
│   │   ├── uploadanddownload/
│   │   │   ├── RequestUpload.ets    # 文件上传封装
│   │   │   └── RequestDownload.ets  # 文件下载封装
│   │   ├── utils/
│   │   │   └── UrlUtils.ets         # 服务器地址管理
│   │   └── pages/
│   │       ├── VideoUpload.ets      # 上传页面
│   │       └── VideoTrimmer.ets     # 主页面
│   ├── environment/                 # 服务器配置目录
│   └── README.md                    # 详细文档
│
├── networkstatusobserver/           # 网络状态监听示例
│   ├── src/main/ets/
│   │   ├── utils/
│   │   │   └── NetUtils.ets         # 网络监听工具类
│   │   └── pages/
│   │       ├── VideoPage.ets        # 视频播放页面
│   │       └── SettingPage.ets      # 设置页面
│   └── README.md
│
└── HttpRequest/                     # 简单 HTTP 请求示例
    └── NetRequest.ets               # HTTP GET 请求封装
```

---

## 📚 项目简介

### 1. videotrimmer ⭐ 重点参考

**功能**: 完整的视频下载、剪辑、上传到服务器的实现

**核心技术**:
- `@kit.BasicServicesKit` - `request.agent` 上传/下载任务管理
- `@kit.NetworkKit` - HTTP 网络请求
- 支持前台/后台模式
- 支持进度监听、断点续传

**关键文件**:
| 文件 | 说明 |
|------|------|
| `RequestUpload.ets` | 文件上传封装，包含进度/完成/失败回调 |
| `RequestDownload.ets` | 文件下载封装 |
| `UrlUtils.ets` | 服务器地址持久化管理 |
| `CustomSetServerDlg.ets` | 服务器配置对话框 |

**适用场景**: 需要实现文件上传下载、进度显示、服务器端点配置的功能

---

### 2. networkstatusobserver

**功能**: 监听手机网络状态（WiFi/蜂窝数据），根据网络状态自动播放/暂停视频

**核心技术**:
- `@kit.NetworkKit` - `connection.createNetConnection()`
- `emitter` - 事件通知机制

**监听事件**:
- `netAvailable` - 网络可用
- `netLost` - 网络丢失
- `netUnavailable` - 网络不可用
- `netBlockStatusChange` - 网络阻塞
- `weakNet` - 弱网检测

**适用场景**: 需要根据网络状态调整应用行为的场景

---

### 3. HttpRequest

**功能**: 简单的 HTTP GET 请求示例

**核心技术**:
- `@kit.NetworkKit` - `http.createHttp().request()`

**适用场景**: 简单的 API 调用、数据请求

---

## 🔧 常用 API 速查

### HTTP 请求

```typescript
import { http } from '@kit.NetworkKit';

http.createHttp().request(
  'https://api.example.com/data',
  (error, data) => {
    if (data.responseCode === 200) {
      console.log(data.result);
    }
  }
);
```

### 文件上传

```typescript
import { request } from '@kit.BasicServicesKit';

const config: request.agent.Config = {
  action: request.agent.Action.UPLOAD,
  url: 'https://api.example.com/upload',
  method: 'POST',
  mode: request.agent.Mode.FOREGROUND,
  data: [/* 文件列表 */]
};

const task = await request.agent.create(context, config);
task.on('progress', (progress) => { /* 进度回调 */ });
task.on('completed', (progress) => { /* 完成回调 */ });
await task.start();
```

### 文件下载

```typescript
const config: request.agent.Config = {
  action: request.agent.Action.DOWNLOAD,
  url: 'https://api.example.com/file.mp4',
  saveas: './downloads/file.mp4',
  overwrite: true
};

const task = await request.agent.create(context, config);
await task.start();
```

### 服务器地址管理

```typescript
import { preferences } from '@kit.ArkData';

// 保存
const pref = await preferences.getPreferences(context, 'server_url');
await pref.put('url', 'https://api.example.com');
await pref.flush();

// 读取
const url = await pref.get('url', '') as string;
```

---

## 📖 推荐阅读顺序

1. **HttpRequest** - 先了解最简单的 HTTP 请求
2. **videotrimmer** - 重点学习上传下载封装和服务器配置
3. **networkstatusobserver** - 根据需要学习网络状态监听

---

## 🔗 官方文档参考

- [HTTP 数据请求](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-http-V5)
- [上传下载任务](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-request-V5)
- [网络管理](https://developer.huawei.com/consumer/cn/doc/best-practices-V5/bpta-network-management-V5)
- [数据持久化](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-preferences-V5)
