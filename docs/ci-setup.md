# Jenkins CI/CD Setup Guide

本项目使用 Jenkins 实现 Windows 本地 CI/CD 流水线，满足 Sprint 2 要求。

## 前置要求

### 1. 环境要求

- **操作系统**: Windows 10/11
- **DevEco Studio**: 必须安装在 `C:\Apps\DevEco Studio`
- **Git**: 已安装并配置
- **PowerShell**: Windows 自带

### 2. DevEco Studio 路径要求

**重要**: 本 CI/CD 配置假设 DevEco Studio 安装在以下固定路径：

```
C:\Apps\DevEco Studio\
```

如果你的 DevEco 安装在其他位置，需要修改 `Jenkinsfile` 中的环境变量：

```groovy
environment {
    DEVECO_SDK_HOME = 'C:\\Apps\\DevEco Studio\\sdk'
    DEVECO_NODE = 'C:\\Apps\\DevEco Studio\\tools\\node\\node.exe'
    DEVECO_OHPM = 'C:\\Apps\\DevEco Studio\\tools\\ohpm\\bin\\ohpm.cmd'
}
```

---

## 安装 Jenkins

### 方法 1: Windows 安装包（推荐）

1. 下载 Jenkins Windows 安装包: https://www.jenkins.io/download/

2. 运行安装程序，选择默认安装路径

3. 安装完成后，浏览器会自动打开 `http://localhost:8080`

4. 按照向导完成初始设置：
   - 解锁 Jenkins（查看初始密码位置）
   - 安装推荐插件
   - 创建管理员账户

### 方法 2: 使用 Chocolatey

```powershell
choco install jenkins
```

---

## 配置 Jenkins

### 1. 安装必要的插件

打开 `Manage Jenkins` -> `Manage Plugins`，安装以下插件：

- **Git Plugin**: Git 支持
- **Pipeline Plugin**: Pipeline 支持（通常已预装）
- **Timestamper Plugin**: 日志时间戳（可选）

### 2. 配置 Git

打开 `Manage Jenkins` -> `Global Tool Configuration`:

- **Git**: 配置 Git 安装路径（如 `C:\Program Files\Git\bin\git.exe`）
- 如果 Git 已在 PATH 中，可跳过此步骤

### 3. 配置 Jenkins 服务权限

Jenkins 服务需要以下权限：
- 读写项目目录的权限
- 执行 `C:\Apps\DevEco Studio\tools\node\node.exe` 的权限
- 执行 PowerShell 的权限

如果遇到权限问题，可以：
- 以管理员身份运行 Jenkins 服务
- 或将 Jenkins 服务账户添加到本地管理员组

---

## 创建 Jenkins 任务

### 1. 新建 Pipeline 任务

1. 点击 `New Item`
2. 输入任务名称，如 `travelpin-ci`
3. 选择 `Pipeline`，点击 `OK`

### 2. 配置 Pipeline

在任务配置页面：

- **Definition**: 选择 `Pipeline script from SCM`
- **SCM**: 选择 `Git`
- **Repository URL**: 输入本地仓库路径
  ```
  file:///D:/Mydata/1University/3Junior/Software_Engineering/project/frontendv1/team-project-26spring-26s-7
  ```
- **Script Path**: `Jenkinsfile`
- **Branches to build**: `*/incremental-dev-20260423` (或你的主分支)

点击 `Save` 保存。

---

## 配置 Git Push 触发

### 方法 1: 使用 Git Hook（本地仓库）

1. 在项目根目录创建 `.git/hooks/post-commit`:

```bash
#!/bin/bash
# 触发 Jenkins 构建
curl -X POST http://localhost:8080/job/travelpin-ci/build --user admin:1135b19f89ad2b92e92917b2d64c88f46a
```

2. 获取 Jenkins API Token:
   - 登录 Jenkins
   - 点击右上角用户名 -> `Configure`
   - API Token 部分点击 `Add new Token`

3. 将 `USERNAME:API_TOKEN` 替换为你的实际值

### 方法 2: 使用 Jenkins 轮询

在任务配置中：
- **Build Triggers**: 勾选 `Poll SCM`
- **Schedule**: 输入 cron 表达式，如 `*/5 * * * *`（每 5 分钟检查一次）

---

## 流水线阶段说明

| 阶段 | 说明 | 关键命令 |
|------|------|----------|
| Checkout | 拉取最新代码 | `git pull` |
| Clean | 清理构建产物 | 删除 `frontend/entry/build` 等 |
| Install Dependencies | 安装 ohpm 依赖 | `ohpm install` |
| Compile | 编译 ArkTS 代码 | `build.ps1 assembleHap` |
| Test | 运行单元测试 | `build.ps1 test` |
| Archive | 归档构建产物 | 保存 `*.hap` 文件 |
| Metrics | 收集代码指标 | 统计 LOC、文件数等 |

---

## 查看构建结果

### 1. 构建日志

- 点击具体构建编号
- 查看 `Console Output` 查看详细日志

### 2. 构建产物

- 构建成功后，点击 `Build Artifacts`
- 下载 `entry-default-signed.hap` 文件

### 3. 测试报告

- 测试报告会自动归档（如果存在）
- 在 `Build Artifacts` 中查找 `.html` 或 `.xml` 文件

---

## 故障排查

### 问题 1: "Access is denied" 运行 Node.exe

**原因**: Jenkins 服务账户权限不足

**解决**:
```powershell
# 1. 检查文件权限
Get-Acl "C:\Apps\DevEco Studio\tools\node\node.exe"

# 2. 修改 Jenkins 服务账户（如需要）
# 打开 services.msc，找到 Jenkins 服务，修改 "Log On" 账户
```

### 问题 2: "DevEco SDK not found"

**原因**: `DEVECO_SDK_HOME` 环境变量路径错误

**解决**: 修改 `Jenkinsfile` 中的环境变量，指向正确的 SDK 路径

### 问题 3: Git 凭证未配置

**原因**: Jenkins 无法访问 Git 仓库

**解决**:
1. 在 Jenkins 中配置 Git 凭证: `Manage Jenkins` -> `Credentials` -> `System` -> `Global credentials`
2. 或在本地配置 Git 自动保存凭证: `git config --global credential.helper store`

### 问题 4: 构建超时

**原因**: 编译时间过长（正常情况）

**解决**:
- 在 `Jenkinsfile` 中调整超时时间
- 或跳过某些耗时阶段（如测试）

---

## 指标统计

流水线会自动收集以下指标（在 Metrics 阶段）：

- **Lines of Code**: ArkTS 源代码总行数
- **Number of Source Files**: `.ets` 文件数量
- **Dependencies**: 依赖列表（从 `oh-package.json5` 读取）

这些指标可用于 Team Report 中的 "Metrics" 部分。

---

## 课程要求对照

### Part I. CI/CD Pipeline (3 points)

| 要求 | 实现状态 |
|------|----------|
| compile the source code | ✅ Compile 阶段 |
| run tests | ✅ Test 阶段 |
| package into runnable artifact | ✅ Archive 阶段 (.hap) |
| triggered by commits | ✅ Git Hook / Poll SCM |
| provides feedback/logs | ✅ Jenkins Console Output |

### Part II. Team Report - CI/CD Pipeline Description (2 points)

报告内容建议：
1. **Steps in the pipeline**: 参考本文档的"流水线阶段说明"
2. **Tools/technologies**:
   - Jenkins (CI/CD 工具)
   - PowerShell (脚本执行)
   - hvigor (构建工具)
   - ohpm (包管理器)
   - @ohos/hypium (测试框架)
3. **Access to pipeline configuration**: 项目根目录 `Jenkinsfile`
4. **Proof of successful execution**: Jenkins 构建截图 + 下载的 .hap 文件

---

## 参考资料

- [Jenkins 官方文档](https://www.jenkins.io/doc/)
- [HarmonyOS 构建指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/)
- 项目 Sprint 2 需求: `references/documents/sprint2.md`
