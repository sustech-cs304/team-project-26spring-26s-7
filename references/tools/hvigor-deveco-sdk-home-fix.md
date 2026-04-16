# DEVECO_SDK_HOME 错误解决方案

## 问题描述

运行 hvigor 编译命令时出现以下错误：

```
> hvigor ERROR: 00303217 Configuration Error
Error Message: Invalid value of 'DEVECO_SDK_HOME' in the system environment path.
```

## 根本原因

1. `DEVECO_SDK_HOME` 环境变量未在系统中设置
2. Git Bash（MinGW）无法继承 Windows 系统环境变量
3. hvigor 通过 node.js 运行时依赖此环境变量定位 HarmonyOS SDK

## 解决方案

### 方案一：PowerShell 启动脚本（推荐）

创建了 `frontend/build.ps1` 脚本，在调用 hvigor 之前自动设置环境变量。

**文件位置**: `frontend/build.ps1`

**使用方法**:
```powershell
# 快速编译
powershell -ExecutionPolicy Bypass -File frontend/build.ps1

# 完整编译（带清理缓存）
powershell -ExecutionPolicy Bypass -File frontend/build.ps1 --sync -p product=default

# 停止 daemon
powershell -ExecutionPolicy Bypass -File frontend/build.ps1 --stop-daemon

# 传递任意 hvigor 参数
powershell -ExecutionPolicy Bypass -File frontend/build.ps1 [hvigor 参数]
```

**脚本内容**:
```powershell
# Build script for TravelPin HarmonyOS Project
# Usage: powershell -ExecutionPolicy Bypass -File build.ps1 [--sync] [-p product=default] [other hvigor args]

# Set DEVECO_SDK_HOME environment variable (fixes "Invalid value of DEVECO_SDK_HOME" error)
$env:DEVECO_SDK_HOME = "C:\Apps\DevEco Studio\sdk"

# Change to script directory
Set-Location -Path $PSScriptRoot

# Run hvigor with all arguments passed to this script
& "C:\Apps\DevEco Studio\tools\node\node.exe" "C:\Apps\DevEco Studio\tools\hvigor\bin\hvigorw.js" $args
```

### 方案二：设置用户级环境变量（辅助）

已通过 PowerShell 设置用户级环境变量：
```powershell
[System.Environment]::SetEnvironmentVariable('DEVECO_SDK_HOME', 'C:\Apps\DevEco Studio\sdk', 'User')
```

此设置对 DevEco Studio IDE 内编译有效。

### 方案三：local.properties 配置（辅助）

在 `frontend/local.properties` 中添加：
```properties
sdk.dir=C:\\Apps\\DevEco Studio\\sdk
DEVECO_SDK_HOME=C:\\Apps\\DevEco Studio\\sdk
```

## 常用编译命令

| 场景 | 命令 |
|------|------|
| 快速编译 | `powershell -ExecutionPolicy Bypass -File frontend/build.ps1` |
| 完整编译 | `powershell -ExecutionPolicy Bypass -File frontend/build.ps1 --sync -p product=default` |
| 停止 daemon | `powershell -ExecutionPolicy Bypass -File frontend/build.ps1 --stop-daemon` |
| 清理缓存 | `cd frontend && rm -rf .hvigor intermediates build .preview` |
| Previewer 编译 | `powershell -ExecutionPolicy Bypass -File frontend/build.ps1 --mode module -p module=entry@default -p product=default -p pageType=page -p compileResInc=true -p previewMode=true -p buildRoot=.preview PreviewBuild` |

## 注意事项

1. **首次使用**：可能需要设置 PowerShell 执行策略
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

2. **Git Bash 用户**：建议将编译命令封装为 bash 函数
   ```bash
   # 添加到 ~/.bashrc
   hvigor-build() {
       powershell -ExecutionPolicy Bypass -File frontend/build.ps1 "$@"
   }
   ```

3. **DevEco Studio**：IDE 内编译使用内置配置，不受此脚本影响

## 参考资料

- SDK 路径：`C:\Apps\DevEco Studio\sdk`
- hvigor 脚本：`C:\Apps\DevEco Studio\tools\hvigor\bin\hvigorw.js`
- Node.js: `C:\Apps\DevEco Studio\tools\node\node.exe`

---

**创建日期**: 2026-04-02  
**最后更新**: 2026-04-02
