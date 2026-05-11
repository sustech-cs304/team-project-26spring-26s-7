# Team Report - TravelPin

**Team ID**: team26s-7
**Project**: TravelPin - 智能旅行路线规划与社交分享应用
**Date**: 2026-05-11

### 1. Metrics

| 指标 | 数值 |
|-----|------|
| **Lines of Code** | 22,326 |
| **Number of Source Files** | 82 |
| **Cyclomatic Complexity** | 4,961 (近似值) |
| **Number of Dependencies** | 3 |
| **Total Tests** | 52 |
| **Test Pass Rate** | 100% (52/52) |
| **Test Failures** | 0 |
| **Test Errors** | 0 |

**Dependencies Details**:
```json
{
  "@hw-agconnect/auth-component": "^1.0.0",
  "@hw-agconnect/cloud": "^1.0.0",
  "@hw-agconnect/hmcore": "^1.0.0"
}
```

**Test Results Summary**:
```
Tests run: 52
Failure: 0
Error: 0
Pass: 52
Ignore: 0
```

**Test Coverage Report**:
- 生成路径: `frontend/entry/.test/default/outputs/test/reports/`
- 包含文件: `index.html`, `coverageReport.json`, `etsCoverageData.json`
- [截图占位 - 测试覆盖率报告]

---

### 2. CI/CD Pipeline Description

#### Pipeline 架构

项目采用 **GitHub Actions + Jenkins** 的混合 CI/CD 架构：
- GitHub Actions 负责代码检出和触发 Jenkins 任务
- Jenkins 负责实际构建、测试和打包流程

#### Pipeline 阶段

| 阶段 | 说明 | 工具/技术 |
|-----|------|----------|
| **1. Checkout** | 拉取最新代码 | Jenkins `checkout scm` |
| **2. Prepare Outputs** | 创建构建产物目录 | PowerShell |
| **3. Clean** | 清理构建缓存 | Windows `rmdir` |
| **4. Install Dependencies** | 安装项目依赖 | OHPM (OpenHarmony Package Manager) |
| **5. Compile** | 编译源代码 | Hvigor `build.ps1 assembleHap` |
| **6. Test** | 运行单元测试 | Hypium (HarmonyOS 单元测试框架) |
| **7. Archive** | 打包应用产物 | Jenkins `archiveArtifacts` |
| **8. Metrics** | 收集代码指标 | PowerShell 自定义脚本 |

#### 触发方式

- **触发条件**: 推送到 `test/ci-cd` 分支
- **并发控制**: 同一分支的新构建会取消进行中的构建

#### 工具版本

| 工具 | 版本 | 来源 |
|-----|------|------|
| DevEco Studio | 6.0.2.642 | IDE 版本 |
| HarmonyOS SDK | 6.0.2(22) | 编译 SDK |
| 工具链版本 | 6.0.2.130 | Toolchains |
| Node.js (构建用) | v18.20.1 | 构建日志 |
| Hvigor | 6.22.3 | `.hvigor/cache/meta.json` |
| Hypium | 1.0.24 | `oh-package.json5` |
| OHPM | DevEco Studio 内置 | 依赖管理 |

#### 构建产物

- **HAP 包路径**: `frontend/entry/build/default/outputs/default/*.hap`
- **测试报告**: `frontend/entry/.test/default/outputs/test/reports/`
- **覆盖率数据**: `frontend/entry/.test/default/intermediates/test/coverage_data/`
- **本地产物目录**: `ci-artifacts/build-{BUILD_NUMBER}/`

#### Pipeline 成功证明

[截图占位 - Jenkins 构建成功日志]

[截图占位 - 测试运行结果]

#### Pipeline 配置文件

- **Jenkinsfile**: [`Jenkinsfile`](../Jenkinsfile)
- **GitHub Actions Workflow**: [`.github/workflows/jenkinsfile-check.yml`](../.github/workflows/jenkinsfile-check.yml)

*报告生成日期: 2026-05-11*
