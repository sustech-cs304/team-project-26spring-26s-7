# 团队报告 - ItsMapPin

**团队 ID**: team26s-7

**项目**: ItsMapPin - HarmonyOS 旅行日记应用

**日期**: 2026-05-14

## 1. 指标

我们分别报告前端和后端指标，因为它们使用不同的语言实现，并由不同的 CI 工具进行测量。项目级别的总计仅合并直接可比较的指标：源文件数量、代码行数和直接依赖项数量。圈复杂度按各端分别显示，而不是跨语言相加。

### 1.1 指标来源

前端 CI 构件：

- 仓库相对路径：`log/ci-artifacts-frontend/metrics/summary.txt`
- CI 构建：前端 Jenkins 构建 21

后端 CI 构件：

- 仓库相对路径：`backend/metrics/summary.txt`
- CI 构建：后端 Jenkins 构建 27，提交 `8497f59f`

### 1.2 项目摘要

| 指标 | 前端 | 后端 | 项目总计 | 备注 |
|---|---:|---:|---:|---|
| 源文件 | 89 `.ets` | 38 `.py` | 127 | CI 源文件计数 |
| 代码行数（总行数） | 27,868 | 6,705 | 34,573 | 前端总行数 + 后端服务行数 |
| 圈复杂度（总计/平均） | 3,057 / 3.46 | 1,123 / 3.54 | N/A | 函数级 CCN；按各端统计，非跨语言汇总 |
| 直接依赖项 | 6 | 11 | 17 | 前端包清单 + 后端服务依赖 |

### 1.3 前端指标

| 指标 | 数值 | 来源 / 备注 |
|---|---:|---|
| 源文件 | 89 | 前端 CI 统计的 `.ets` 文件 |
| 代码行数（总行数） | 27,868 | `LOC (total lines)` |
| 检测到的函数 | 883 | PowerShell 大括号匹配扫描 |
| 文件级圈复杂度 | 2,652 总计 / 平均每个文件 29.8 | 基于正则的文件级 CCN |
| 函数级圈复杂度 | 3,057 总计 / 平均每个函数 3.46 | PowerShell 每函数解析器 |
| 直接依赖项 | 6 | 4 个运行时 + 2 个开发依赖 |

前端直接依赖项：

- 运行时：`@hw-agconnect/auth`、`@hw-agconnect/auth-component`、`@hw-agconnect/cloud`、`@hw-agconnect/hmcore`
- 开发：`@ohos/hamock`、`@ohos/hypium`

前端复杂度热点：

| CCN | 文件 | 代码行数 |
|---:|---|---:|
| 226 | `feature/map-travel/views/MapHomeView.ets` | 1,975 |
| 147 | `feature/map-travel/pages/TripReplayPage.ets` | 1,351 |
| 121 | `common/service/RdbDataService.ets` | 914 |
| 110 | `feature/ai-copy/pages/AiCopyPage.ets` | 1,094 |
| 107 | `common/sync/SyncManager.ets` | 550 |
| 105 | `feature/social-share/pages/SharePage.ets` | 916 |
| 99 | `common/data/MemoryNodeRepository.ets` | 664 |
| 98 | `feature/map-travel/pages/NodeDetailPage.ets` | 980 |
| 97 | `common/data/TravelRepository.ets` | 561 |
| 90 | `common/api/AiGatewayClient.ets` | 646 |

### 1.4 后端指标

| 指标 | 数值 | 来源 / 备注 |
|---|---:|---|
| 源文件 | 38 | 各后端服务目标下的 Python 文件 |
| 代码行数（总行数） | 6,705 | 后端 Jenkins `loc.txt` |
| Radon CC 条目 | 317 | 从 `cyclomatic-complexity.txt` 解析 |
| Radon CC 总计 | 1,123 | 报告的 Radon CC 条目之和 |
| Radon CC 平均值 | 3.54 | 从 Radon CC 条目计算得出 |
| 直接依赖项 | 11 | 唯一的后端服务依赖 |

后端服务级指标：

| 服务 | 文件数 | 代码行数 | 平均 Radon CC |
|---|---:|---:|---|
| `ai-relay` | 1 | 611 | A, 4.86 |
| `sensitive-filter` | 1 | 300 | A, 3.85 |
| `picture-check` | 3 | 441 | A, 2.00 |
| `share-service` | 33 | 5,353 | A, 3.52 |

后端直接依赖项：

- `fastapi`
- `httpx`
- `Pillow`
- `pydantic`
- `PyJWT`
- `pytest`
- `python-multipart`
- `qrcode`
- `requests`
- `slowapi`
- `uvicorn`

来自 Radon 的后端复杂度热点：

| CCN | 函数 | 文件 |
|---:|---|---|
| 48 | `publish` | `share-service/share_service/routers/publish.py` |
| 23 | `chat_completions_image` | `ai-relay/siliconflow_relay.py` |
| 17 | `test_viewer_html_has_og_meta_tags` | `share-service/share_service/tests/test_publish_api.py` |
| 16 | `audit_share` | `share-service/share_service/core/audit_task.py` |
| 15 | `chat_completions` | `ai-relay/siliconflow_relay.py` |
| 15 | `_verify_token` | `share-service/share_service/core/auth.py` |
| 14 | `SensitiveWordFilter.__init__` | `sensitive-filter/sensitive_filter_service.py` |
| 13 | `find_all_hits` | `sensitive-filter/sensitive_filter_service.py` |

## 2. CI/CD 流水线描述

ItsMapPin 使用 GitHub Actions 和 Jenkins 桥接来实现前端 CI 流水线。GitHub Actions 在 Windows 自托管运行器上运行，触发本地 Jenkins 任务，将 Jenkins 日志流式传输回 GitHub Actions 任务，并上传 Jenkins 输出目录作为 GitHub Actions 构件。Jenkins 执行实际的 HarmonyOS 构建、测试、打包、归档和指标收集阶段。

后端在独立的 Jenkins 任务上运行，地址为 `http://139.159.143.195:8080/job/team-project-backend-ci/`。它使用 `backend/Jenkinsfile` 并直接执行 Python 后端流水线：依赖安装、代码检查报告、语法编译、冒烟测试、pytest、覆盖率生成、指标收集和构件打包。

### 前端流水线步骤

| 步骤 | 作用 | 工具 / 技术 |
|---|---|---|
| 检出代码 | 获取 CI 运行的最新仓库状态。 | GitHub Actions `actions/checkout@v4`、Jenkins `checkout scm` |
| 触发 Jenkins | 启动本地 Jenkins 任务并将日志流式传输到 GitHub Actions。 | PowerShell、`scripts/watch-jenkins-build.ps1`、Jenkins HTTP API |
| 准备输出 | 在 `ci-artifacts/build-{BUILD_NUMBER}` 下创建每个构建的构件文件夹。 | Jenkins、PowerShell |
| 清理 | 清理构建缓存和之前生成的输出。 | Windows shell / PowerShell |
| 安装依赖项 | 安装 HarmonyOS 前端依赖项。 | OHPM |
| 编译 | 构建 HarmonyOS HAP 包。 | `frontend/build.ps1 --mode module -p module=entry@default assembleHap`、Hvigor |
| 测试 | 运行业务测试套件并收集每个测试的结果以及 ETS 级覆盖率数据。 | `frontend/build.ps1 test`、Hypium |
| 归档 | 归档生成的 HAP 包和测试/覆盖率报告。 | Jenkins `archiveArtifacts`、GitHub Actions 构件上传 |
| 指标 | 计算源文件数量、代码行数、CCN、函数数量和依赖项数量。 | Jenkinsfile PowerShell 指标脚本 |

**注意 — 前端代码检查**：前端在流水线中不包含专门的代码检查阶段。ArkTS 是 HarmonyOS 专用语言，其类型检查和代码检查基础设施深度集成到 DevEco Studio 中（由 Hvigor 构建系统和 ArkTS 编译器提供支持）。与拥有独立可触发 CLI 代码检查工具的主流语言（例如 JavaScript 的 ESLint、Python 的 Ruff）不同，ArkTS 没有成熟的、可在 DevEco IDE 环境之外独立运行的代码检查工具。因此，ArkTS 代码质量检查在开发过程中于 DevEco Studio 内执行，而非作为 CI 阶段。前端编译阶段会显示编译器警告，这些警告会被过滤并显示在构建日志中。

### 后端 Jenkins 流水线步骤

| 步骤 | 作用 | 工具 / 技术 |
|---|---|---|
| 检出代码 | 检出团队项目仓库并记录简短的 Git 提交 SHA。 | Jenkins `checkout scm`、Git |
| 准备输出 | 创建外部 CI 构件目录和工作区暂存目录，然后写入构建元数据。 | Jenkins、Bash、`/var/lib/jenkins/ci-artifacts/team-project-backend/build-{BUILD_NUMBER}` |
| 清理 | 删除 Python 缓存目录和之前的后端构建/测试输出。 | Bash、`find`、`rm` |
| 安装依赖项 | 创建或重用 `backend/.ci-venv`，安装 CI 工具和服务依赖项（使用基于哈希的依赖缓存），并写入 `pip-freeze.txt`。 | Python venv、pip、华为云 PyPI 镜像、TUNA 回退 |
| 代码检查 | 对 `ai-relay`、`sensitive-filter`、`picture-check`、`share-service` 和 `ci` 运行 Ruff；代码检查仅为警告并写入 `reports/lint-ruff.txt`。 | `ruff==0.6.9` |
| 编译 | 对后端服务和 CI 模块执行 Python 语法编译。 | `python -m compileall -q` |
| 测试 | 运行 `ai-relay`、`sensitive-filter` 和 `picture-check` 的导入冒烟检查，然后使用 JUnit XML 和覆盖率报告运行 `share-service` pytest 套件。 | `backend/ci/smoke_imports.py`、`pytest`、`pytest-cov` |
| 指标 | 统计 Python 文件和代码行数；计算 Radon 圈复杂度、可维护性指数和原始统计信息；还生成文档级报告（`metrics/summary.txt`、`cyclomatic-complexity.txt`、`maintainability-index.txt`、`raw-stats.txt`、`loc.txt`），这些报告作为每次构建的自动化代码质量文档。 | `radon cc`、`radon mi`、`radon raw`、Bash |
| 归档 | 将后端源代码、报告、指标、元数据和日志打包成带有校验和的 tarball，然后在 Jenkins 中归档它们。 | `tar`、`sha256sum`、Jenkins `archiveArtifacts` |

### 生成的测试报告和文档

两条流水线都生成结构化的测试报告和代码质量文档作为 CI 构件。下表列出了关键报告、其用途以及在 `log/` 目录下的路径。

**前端报告**（在 `log/ci-artifacts-frontend/` 下）：

| 报告 | 路径 | 用途 |
|---|---|---|
| 每测试结果 | `reports/coverage/coverage_data/test_result.txt` | 列出来自 Hypium 的每个测试用例名称、类和通过/失败状态。 |
| 每源代码覆盖率 HTML | `reports/test/index.html` 和每包子目录 | 按包和文件可浏览的 ETS 行级覆盖率报告（例如 `test/common/api/AiGatewayClient.ets.html`）。 |
| 覆盖率 JSON | `reports/test/coverageReport.json` | 整个测试套件的机器可读行覆盖率摘要。 |
| ETS 覆盖率数据 | `reports/coverage/etsCoverageData.json`、`reports/coverage/init_coverage.json` | HTML 报告生成器使用的原始 ETS 行覆盖率数据。 |
| JS 覆盖率数据 | `reports/coverage/coverage_data/js_coverage.json` | 在测试执行期间收集的 JavaScript 级覆盖率数据。 |
| 指标摘要 | `metrics/summary.txt` | 聚合指标：源文件数量、代码行数、函数数量、文件级和函数级 CCN、依赖列表。 |

**后端报告**（在 `log/ci-artifacts-backend/` 下）：

| 报告 | 路径 | 用途 |
|---|---|---|
| JUnit 测试结果 | `reports/junit-share-service.xml` | 来自 pytest 的 JUnit XML 报告；由 Jenkins 消耗以进行测试结果趋势分析。 |
| 覆盖率 XML（Cobertura） | `reports/coverage-share-service.xml` | Cobertura 格式的机器可读覆盖率报告，用于 CI 集成。 |
| 覆盖率 HTML | `reports/coverage-share-service-html/index.html` | 可浏览的每文件覆盖率报告，带有行级命中/未命中高亮。 |
| 代码检查发现 | `reports/lint-ruff.txt` | GitHub 注释格式的 Ruff 代码检查输出；仅为警告，不会导致构建失败。 |
| 圈复杂度 | `metrics/cyclomatic-complexity.txt` | 按复杂度排名的 Radon CC 每函数报告。 |
| 可维护性指数 | `metrics/maintainability-index.txt` | 每模块的 Radon MI 分数，指示整体代码可维护性。 |
| 原始统计 | `metrics/raw-stats.txt` | Radon 原始指标：每个文件的代码行数、逻辑代码行数、源代码行数、注释、多行统计信息。 |
| 按服务的代码行数 | `metrics/loc.txt` | 按后端服务细分的源文件数量和代码行数。 |
| 指标摘要 | `metrics/summary.txt` | 聚合后端指标，包含按服务的细分和依赖列表。 |
| 依赖快照 | `metrics/pip-freeze.txt` | 完整的 pip freeze 快照，用于可复现性。 |

### 触发和反馈

- 前端触发：推送到 `main` 和 `test/ci-cd` 会启动 GitHub Actions 桥接，该桥接会触发本地前端 Jenkins 任务 `travelpin-ci`。
- 后端触发：推送到团队项目仓库会被传递到 `http://139.159.143.195:8080/github-webhook/`；Jenkins 任务 `team-project-backend-ci` 会检出配置的分支并运行 `backend/Jenkinsfile`。
- 前端反馈：GitHub Actions 显示桥接状态并上传 Jenkins 日志/构件；前端 Jenkins 任务显示阶段级构建状态。
- 后端反馈：后端 Jenkins 任务显示阶段级状态并发布 GitHub 提交状态上下文 `jenkins/team-project-backend-ci`。

### 流水线配置

- 前端 GitHub Actions 工作流：[`.github/workflows/jenkinsfile-check.yml`](.github/workflows/jenkinsfile-check.yml)
- 前端 Jenkins 流水线：[`Jenkinsfile`](Jenkinsfile)
- Jenkins 桥接脚本：[`scripts/watch-jenkins-build.ps1`](scripts/watch-jenkins-build.ps1)
- 后端 Jenkins 流水线：[`backend/Jenkinsfile`](backend/Jenkinsfile)

### 成功执行证明

以下截图显示了一个提交同时接收前端和后端 CI 检查。GitHub 用状态图标显示每个检查，因此贡献者可以直接在提交上看到成功或失败的反馈。

![一个提交上的前端和后端 CI 检查](documents/screenshots/front_back_allpass_example.jpg)

前端证明：

- GitHub Actions 运行 URL：
  <https://github.com/sustech-cs304/team-project-26spring-26s-7/actions/runs/25851795537/job/75959874734>
- 打包的 HAP 构件：
  - `log/ci-artifacts-frontend/packages/entry-default-signed.hap`
  - `log/ci-artifacts-frontend/packages/entry-default-unsigned.hap`
- 打包的日志：
  - `log\ci-artifacts-frontend\logs`

![前端 GitHub Actions 成功](documents/screenshots/frontend_jenkins_github_success_total.jpg)

![前端 Jenkins 状态](documents/screenshots/frontend_jenkins_status.jpg)

![前端 Jenkins 阶段视图](documents/screenshots/frontend_jenkins_stages.jpg)

![前端 GitHub Actions 上传的构件](documents/screenshots/frontend_jenkins_github_artifact.jpg)

后端证明：

- 后端 Jenkins URL：
  <http://139.159.143.195:8080/job/team-project-backend-ci/>
- 打包的日志：
  - `log\ci-artifacts-backend\logs`

![后端 Jenkins 状态](documents/screenshots/backend_jenkins_status.jpg)

![后端 Jenkins 阶段视图](documents/screenshots/backend_jenkins_stages.jpg)