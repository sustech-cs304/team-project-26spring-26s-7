# Map Kit 队友切换备忘录
测试pull request
> 当你需要使用队友的 Map Kit（华为 AGConnect 项目）时，按此文档逐项修改。

---

## 1. AGConnect 服务配置（最关键）

**文件**: `entry/src/main/resources/rawfile/agconnect-services.json`

直接用队友的 `agconnect-services.json` **整个替换**即可。该文件包含：
- `client_id` — 客户端 ID
- `client_secret` — 客户端密钥（加密）
- `api_key` — API 密钥（加密）
- `app_id` — 应用 ID
- `cp_id` — 开发者 ID
- `project_id` / `product_id`
- `package_name` — 必须与 bundleName 一致

---

## 2. 包名 (Bundle Name)

需要改 **2 个文件**，保持与 agconnect-services.json 中的 `package_name` 一致：

| 文件 | 字段 | 当前值 |
|------|------|--------|
| `AppScope/app.json5` | `"bundleName"` | `com.ran.login_test` |
| `build-profile.json5` (约 L42) | `"bundleName"` | `com.ran.login_test` |

---

## 3. 签名证书

**文件**: `build-profile.json5` (L3-16 signingConfigs 段)

需要替换为队友的证书路径和密码：

| 字段 | 说明 | 当前值 |
|------|------|--------|
| `storeFile` | .p12 密钥库路径 | `D:/.../certificates/1.p12` |
| `storePassword` | 密钥库密码（加密） | `0000001D...` |
| `keyAlias` | 密钥别名 | `test` |
| `keyPassword` | 密钥密码（加密） | `0000001D...` |
| `profile` | .p7b 签名文件 | `D:/.../certificates/testDebug.p7b` |
| `certpath` | .cer 证书文件 | `D:/.../certificates/test.cer` |

> **建议**: 让队友在 DevEco Studio → Project Structure → Signing Configs 中配置一次，然后把生成的 `build-profile.json5` 签名段发给你。

---

## 4. Module 元数据中的 client_id

**文件**: `entry/src/main/module.json5` (约 L37-39)

```json
"metadata": [
  {
    "name": "client_id",
    "value": "1910345568262058944"  // ← 改为队友的 client_id
  }
]
```

此值必须与 `agconnect-services.json` 中的 `client_id` 一致。

---

## 5. Map Kit Capability 配置

**文件**: `build-profile.json5` (约 L44-55)

当前已配置 `"capability": "com.huawei.service.mapkit"`，一般不需要修改。但确保队友的 AGConnect 项目已在华为开发者控制台开启了 Map Kit 服务。

---

## 快速操作清单

```
□ 1. 拿到队友的 agconnect-services.json，替换 entry/src/main/resources/rawfile/agconnect-services.json
□ 2. 从新的 agconnect-services.json 中找到 package_name，修改：
     - AppScope/app.json5 → bundleName
     - build-profile.json5 → bundleName
□ 3. 从新的 agconnect-services.json 中找到 client_id，修改：
     - entry/src/main/module.json5 → metadata.client_id
□ 4. 替换签名证书（build-profile.json5 signingConfigs 段），或让队友通过 DevEco Studio 配置
□ 5. Clean → Rebuild → 真机运行验证地图能否正常加载
```

---

## 使用 Map Kit 的源文件（无需修改，仅参考）

以下文件 import 了 `@kit.MapKit`，Map Kit 通过 AGConnect 配置自动鉴权，代码中不需要硬编码 API Key：

- `feature/map-travel/views/MapHomeView.ets`
- `feature/map-travel/pages/LocationPickerPage.ets`
- `feature/map-travel/pages/TripDetailPage.ets`
- `feature/map-travel/pages/TripReplayPage.ets`
