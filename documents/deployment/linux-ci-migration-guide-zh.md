# TravelPin Linux CI/CD 迁移指南（中文）

## 背景

当前项目的 CI/CD 流水线完全基于 Windows 环境：

- GitHub Actions 使用 Windows 自托管 Runner
- Jenkins 运行在 Windows 上，Jenkinsfile 中全是 `bat`、`powershell` 调用
- 构建脚本 `build.ps1` 硬编码了 `C:\Apps\DevEco Studio\...` 路径
- Jenkins 桥接脚本 `watch-jenkins-build.ps1` 是 PowerShell 实现的

迁移目标是将整个 CI/CD 链搬到一台 Linux 服务器上，使流水线在 Linux 上完整运行。

---

## 当前架构（Windows）

```
git push
  → GitHub Actions（Windows self-hosted runner）
    → scripts/watch-jenkins-build.ps1（PowerShell）
      → Jenkins job "travelpin-ci"（Windows，bat/powershell）
        → frontend/build.ps1（PowerShell，硬编码 C:\ 路径）
          → 产物输出到 D:\...\ci-artifacts\build-N
  → GitHub Actions 上传 .ci-logs + ci-artifacts
```

### 涉及文件

| 文件 | 问题 |
|---|---|
| `Jenkinsfile` | `bat` 块、`powershell` 块、Windows 路径、`rmdir /s /q` |
| `frontend/build.ps1` | 仅 PowerShell，硬编码 `C:\Apps\DevEco Studio\*` |
| `scripts/watch-jenkins-build.ps1` | 仅 PowerShell |
| `.github/workflows/jenkinsfile-check.yml` | `runs-on: [self-hosted, windows]`，`shell: powershell` |

---

## 目标架构（Linux）

```
git push
  → GitHub Actions（Linux self-hosted runner）
    → scripts/watch-jenkins-build.sh（Bash + cURL）
      → Jenkins job "travelpin-ci"（Linux，sh）
        → frontend/build.sh（Bash，环境变量驱动）
          → 产物输出到 ~/ci-server/ci-artifacts/build-N
  → GitHub Actions 上传 .ci-logs + ci-artifacts
```

### Linux 目录规划

所有 CI 相关文件统一放置在 `/data2/cse12310817/ci-server` 下。

| 用途 | 路径 |
|---|---|
| CI 基准目录 | `~/ci-server` |
| 仓库参考克隆 | `~/ci-server/team-project-26spring-26s-7`（`test/ci-cd` 分支） |
| Jenkins 主目录 | `/var/lib/jenkins`（系统包默认路径） |
| GitHub Runner | `~/ci-server/actions-runner` |
| HarmonyOS 命令行工具 | `~/ci-server/harmony-commandline-tools` |
| 构建产物根目录 | `~/ci-server/ci-artifacts` |

---

## 迁移分步计划

### 阶段 A：准备 Linux 服务器基础设施

#### 1. 服务器要求

- Ubuntu LTS（或其他主流发行版）
- 最低 4 GB 内存
- 最低 20 GB 可用磁盘
- 能访问 GitHub 和华为鸿蒙工具下载地址

#### 2. 安装 Java 21+

Jenkins 要求 Java 21 或更高版本：

```bash
sudo apt update
sudo apt install -y fontconfig openjdk-21-jre
java -version
```

#### 3. 安装 Jenkins

按照 Jenkins 官方文档安装。Ubuntu 示例：

```bash
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc]" \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt update
sudo apt install -y jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins
```

如果 8080 端口被占用，改为 8081：

```bash
sudo sed -i 's/--httpPort=8080/--httpPort=8081/' /etc/default/jenkins
sudo systemctl restart jenkins
```

获取初始管理员密码：

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

安装推荐插件后，确保安装：**Pipeline、Git、Credentials Binding、Workspace Cleanup**。

#### 4. 安装 GitHub Self-Hosted Runner

在 GitHub 仓库 **Settings → Actions → Runners → New self-hosted runner** 中注册，选择 Linux。

```bash
mkdir -p ~/ci-server/actions-runner
cd ~/ci-server/actions-runner
# 按 GitHub 页面指引下载、解压

./config.sh --url https://github.com/sustech-cs304/team-project-26spring-26s-7 --token <TOKEN>
# 标签设置为：self-hosted, linux, travelpin

sudo ./svc.sh install   # 注册为系统服务需要 root 权限
sudo ./svc.sh start
```

#### 5. 安装鸿蒙命令行工具

从华为开发者网站下载 Linux 版命令行工具：

https://developer.huawei.com/consumer/cn/deveco-studio/archive/

找到 `commandline-tools-linux-*.zip`。

```bash
mkdir -p ~/ci-server/harmony-commandline-tools
unzip commandline-tools-linux-*.zip -d ~/ci-server/harmony-commandline-tools
```

解压后定位以下工具的实际路径（后续需要配置为环境变量）：

```bash
find ~/ci-server/harmony-commandline-tools -name 'ohpm' -type f
find ~/ci-server/harmony-commandline-tools -name 'hvigorw.js' -type f
find ~/ci-server/harmony-commandline-tools -name 'node' -type f
find ~/ci-server/harmony-commandline-tools -name 'sdkmgr' -type f
```

#### 6. 安装 Node.js（如果 hvigor 需要）

当前构建使用 Node 执行 hvigorw.js，Linux 上同样需要：

```bash
# 如果系统自带的 Node 版本不够，可用 nvm 或直接安装 LTS
node -v
npm -v
```

#### 7. 创建产物目录

```bash
mkdir -p ~/ci-server/ci-artifacts
```

#### 8. 拉取参考分支

将 `test/ci-cd` 分支克隆到 `~/ci-server` 目录下，供服务器端 Claude Code 参考：

```bash
cd ~/ci-server
git clone -b test/ci-cd https://github.com/sustech-cs304/team-project-26spring-26s-7.git
```

克隆后目录结构为 `~/ci-server/team-project-26spring-26s-7/`，包含所有 Windows 源文件和迁移指南文档。

---

### 阶段 B：创建 Linux 兼容的构建文件

在仓库中新增以下文件，**不删除任何现有 Windows 文件**。

#### 新增 `frontend/build.sh`

替代 `frontend/build.ps1`，通过环境变量获取工具路径：

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${HARMONY_SDK_HOME:?HARMONY_SDK_HOME is required}"
: "${HARMONY_NODE:?HARMONY_NODE is required}"
: "${HARMONY_HVIGOR:?HARMONY_HVIGOR is required}"

export DEVECO_SDK_HOME="$HARMONY_SDK_HOME"
cd "$(dirname "$0")"

"$HARMONY_NODE" "$HARMONY_HVIGOR" "$@"
```

#### 新增 `scripts/watch-jenkins-build.sh`

替代 `scripts/watch-jenkins-build.ps1`，使用 Bash + cURL + python3 实现 HTTP 触发 + 轮询 + 日志采集。

完整内容见 `references/documents/linux-ci-handoff-for-claude-code.md` 的 Step 6。

#### 新增 `Jenkinsfile.linux`

替代当前 `Jenkinsfile`，所有 `bat` 替换为 `sh`、`powershell` 替换为 `sh`、Windows 路径替换为环境变量、`rmdir /s /q` 替换为 `rm -rf`。

完整内容见 `references/documents/linux-ci-handoff-for-claude-code.md` 的 Step 7。

---

### 阶段 C：修改 GitHub Actions 工作流

修改 `.github/workflows/jenkinsfile-check.yml`：

**关键改动：**

1. `runs-on` 改为 `[self-hosted, linux, travelpin]`
2. `shell` 从 `powershell` 改为 `bash`
3. 调用 `watch-jenkins-build.sh` 替代 `.ps1`
4. 路径解析改用 `python3` 替代 PowerShell
5. `LOCAL_CI_ARTIFACT_ROOT` 改为绝对路径（如 `/data2/cse12310817/ci-server/ci-artifacts`）

完整内容见 `references/documents/linux-ci-handoff-for-claude-code.md` 的 Step 8。

---

### 阶段 D：配置 Jenkins 任务

#### Jenkins 环境变量

在 **Manage Jenkins → System** 或任务配置中设置：

| 变量名 | 示例值 | 说明 |
|---|---|---|
| `HARMONY_SDK_HOME` | `/data2/cse12310817/ci-server/harmony-commandline-tools/sdk` | 鸿蒙 SDK 根路径 |
| `HARMONY_NODE` | `/data2/cse12310817/ci-server/harmony-commandline-tools/tools/node/bin/node` | Node 路径 |
| `HARMONY_OHPM` | `/data2/cse12310817/ci-server/harmony-commandline-tools/tools/ohpm/bin/ohpm` | ohpm 路径 |
| `HARMONY_HVIGOR` | `/data2/cse12310817/ci-server/harmony-commandline-tools/tools/hvigor/bin/hvigorw.js` | hvigor 路径 |
| `LOCAL_ARTIFACT_ROOT` | `/data2/cse12310817/ci-server/ci-artifacts` | 产物根目录 |

**注意**：
- Jenkins **不展开** `~`，必须使用绝对路径 `/data2/cse12310817/ci-server/...`。
- 以上路径是示例，实际值取决于阶段 A 第 5 步 `find` 命令的结果。

#### 创建 Jenkins Pipeline 任务

1. 新建 Pipeline 任务，名称 `travelpin-ci`
2. 选择 "Pipeline script from SCM"
3. 指向 Git 仓库
4. Script Path 设为 `Jenkinsfile.linux`
5. 分支设为 `test/ci-cd`

#### 配置凭证

1. 在 Jenkins 中创建 API Token
2. 在 GitHub 仓库 Settings → Secrets 中添加：
   - `JENKINS_USERNAME`
   - `JENKINS_API_TOKEN`

---

## 验证清单

### Jenkins 独立验证

```bash
# 手动触发构建
curl -X POST http://127.0.0.1:8081/job/travelpin-ci/build \
  --user "<username>:<api_token>"
```

在 Jenkins 界面确认：
- [ ] `checkout scm` 成功
- [ ] `ohpm install` 成功
- [ ] 编译成功，生成 `.hap` 文件
- [ ] 测试运行完成
- [ ] `~/ci-server/ci-artifacts/build-N/` 包含完整产物

### 参考分支验证

确认 `test/ci-cd` 分支已克隆到基准目录下：

```bash
ls ~/ci-server/team-project-26spring-26s-7/
# 应包含：Jenkinsfile, frontend/, scripts/, .github/, references/documents/
```

### GitHub Actions 端到端验证

```bash
git push origin test/ci-cd
```

确认：
- [ ] Linux Runner 接收到任务
- [ ] `watch-jenkins-build.sh` 成功触发 Jenkins
- [ ] 日志流式输出到 GitHub Actions 控制台
- [ ] 构建结果为 SUCCESS
- [ ] `.ci-logs` artifact 成功上传
- [ ] `ci-artifacts-build-N` artifact 成功上传，包含 `.hap` 和报告

---

## 常见问题

### ohpm install 失败

- 检查 `HARMONY_OHPM` 路径是否正确且有执行权限
- 手动在 `frontend/` 目录下运行 `ohpm install` 看具体错误
- 确认服务器能访问鸿蒙包注册表

### 编译失败

- 确认 `HARMONY_NODE` 和 `HARMONY_HVIGOR` 路径正确
- 手动运行 `build.sh` 查看实际错误
- 确认 `HARMONY_SDK_HOME` 指向有效 SDK 且 API 版本匹配

### GitHub Actions 无法触发 Jenkins

- 确认 Runner 和 Jenkins 在同一台机器（否则 `127.0.0.1` 不对）
- 检查 GitHub Secrets 中的 `JENKINS_USERNAME` 和 `JENKINS_API_TOKEN` 是否正确
- 如果 Runner 和 Jenkins 不在同一台机器，需修改 `JENKINS_BASE_URL` 为实际 IP 或域名

### 测试报告找不到

- `frontend/entry/.test/default/...` 路径在 Linux 上可能不同
- 先手动运行一次测试，检查实际输出路径
- 根据实际情况调整 Jenkinsfile 中 `dir()` 块的路径

---

## 迁移原则

1. **渐进式迁移**：先证明最小 Linux 编译可行，再迁移完整流水线
2. **保留 Windows 文件**：在新文件验证通过之前，不删除 `build.ps1`、`watch-jenkins-build.ps1`、`Jenkinsfile`
3. **先在 `test/ci-cd` 分支验证**：确认完全通过后才考虑合入 `main`
4. **环境变量驱动**：不在仓库文件中硬编码服务器路径，全部通过环境变量配置

---

## 文件变更总结

| 文件 | 操作 |
|---|---|
| `frontend/build.sh` | 新增 — Linux 构建入口 |
| `scripts/watch-jenkins-build.sh` | 新增 — Linux Jenkins 桥接脚本 |
| `Jenkinsfile.linux` | 新增 — Linux 兼容 Jenkinsfile |
| `.github/workflows/jenkinsfile-check.yml` | 修改 — Linux Runner + Bash |
| `Jenkinsfile` | 保留 — Windows 版本不动 |
| `frontend/build.ps1` | 保留 — Windows 版本不动 |
| `scripts/watch-jenkins-build.ps1` | 保留 — Windows 版本不动 |

---

## 参考资源

- 详细的交接文档（给服务器端 Claude Code）：`references/documents/linux-ci-handoff-for-claude-code.md`
- 原 Windows 迁移指南：`references/documents/linux-jenkins-github-actions-migration-guide.md`
- GitHub Self-Hosted Runner Linux 安装：https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/configuring-the-self-hosted-runner-application-as-a-service?platform=linux
- Jenkins Linux 安装：https://www.jenkins.io/doc/book/installing/linux/
- 华为 DevEco 下载页（含 Linux 命令行工具）：https://developer.huawei.com/consumer/cn/deveco-studio/archive/
