# CI/CD 架构总览 —— team-project-26spring-26s-7

本仓库同时托管前端（HarmonyOS / ArkTS）和后端（Python FastAPI 服务），
对应**两条独立但并行的 CI 流水线**。一次 `git push` 到 `main` 会同时触发
两侧，构建产物分别在各自的 Jenkins 控制台 + commit 状态检查里可见。

## 一图看懂

```
                       git push to main
                              │
                              ▼
                         GitHub repo
                       (sustech-cs304/
                  team-project-26spring-26s-7)
                              │
            ┌─────────────────┴─────────────────┐
            │                                   │
            ▼ (path filter)                     ▼ (any push, webhook)
   GH Action 'Jenkinsfile Check'      Linux Jenkins (root@139.159.143.195:8080)
   runs on self-hosted Windows         job: team-project-backend-ci
   runner (zzh's laptop)                       │
            │                                   │ Pipeline script:
            │ curl Jenkins API                  │   backend/Jenkinsfile
            ▼                                   │
   zzh laptop Jenkins (localhost:8081)         9 stages：Checkout → Prepare →
   job: travelpin-ci                            Clean → Install Deps → Lint
            │                                   → Compile → Test → Metrics →
            │ Pipeline script:                  Archive
            │   Jenkinsfile (repo root)         │
            ▼                                   ▼
   ArkTS HAP 构建 + 单元/集成测试 →     pytest + ruff + radon →
   /D:\...\ci-artifacts\build-N\        /var/lib/jenkins/ci-artifacts/
                                        team-project-backend/build-N/
            │                                   │
            └────────► 两个 commit status check ◄────────
                       jenkins/travelpin-ci             (前端在前端 Jenkinsfile
                                                         里加 status setter 后出现)
                       jenkins/team-project-backend-ci  (后端已经在做)
```

## 两套 Jenkins 的分工

| 项 | Frontend Jenkins | Backend Jenkins |
|---|---|---|
| 物理位置 | zzh's Windows laptop（校园网内网） | 华为云 Beijing AZ `139.159.143.195` |
| Jenkins URL | `http://127.0.0.1:8081` *(仅 zzh 本地可达)* | `http://139.159.143.195:8080` *(公网可达)* |
| Jenkins 账号 | zzh's laptop admin | root 服务器上的 jenkins 用户 |
| Job 名 | `travelpin-ci` | `team-project-backend-ci` |
| Pipeline 文件 | `Jenkinsfile`（仓库根） | `backend/Jenkinsfile` |
| Agent | 本机（Windows）| 本机（Linux） |
| 触发链 | GitHub → GH Action → self-hosted runner → curl Jenkins API | GitHub webhook → Jenkins 直接接收 |
| Status context | `jenkins/travelpin-ci`（若 status setter 已配） | `jenkins/team-project-backend-ci` |
| Artifact 落盘 | `D:\Mydata\...\ci-artifacts\build-N\` | `/var/lib/jenkins/ci-artifacts/team-project-backend/build-N/` |

**为什么不合并到一个 Jenkins？**
前端构建依赖 HarmonyOS DevEco Studio + SDK，**只能跑在 Windows + 装好 SDK 的特定机器**上；
后端依赖 Python 3.10 + apt 系列工具，跑 Linux 最自然。强行合并 = 单机要装全套工具链
+ 跨平台 agent 配置，代价不划算。两套独立反而清晰，故障隔离也好。

## 触发表

| 推送内容 | 前端 GH Action | 前端 Jenkins | 后端 GH Action | 后端 Jenkins |
|---|---|---|---|---|
| 改 `frontend/**` | ✅ 跑 | ✅ 跑（前端 GH Action 拉起） | ⏭️ 跳过（paths 不匹配） | ✅ 跑（webhook 无 paths filter） |
| 改 `backend/**` | ✅ 跑 *(前端 GH Action 当前无 paths filter；任何 push 都跑)* | ✅ 跑 | ✅ 跑（如果改了 `backend/Jenkinsfile` / `backend/ci/**`） | ✅ 跑 |
| 改根目录文件（README / 文档） | ✅ 跑 | ✅ 跑 | ⏭️ 跳过 | ✅ 跑 |
| 空 commit（`--allow-empty`） | ✅ 跑 | ✅ 跑 | ⏭️ 跳过（无文件变化） | ✅ 跑 |

**前端 GH Action 设计选择**：目前没有 paths filter，任何 push 到 `main` / `test/ci-cd`
都会触发 zzh laptop runner。若想优化（只在前端代码变化时跑），将来可以加：
```yaml
paths:
  - 'frontend/**'
  - 'Jenkinsfile'
  - '.github/workflows/jenkinsfile-check.yml'
```

## 已知陷阱（建议阅读后再动 CI 配置）

### 1. SCM polling 基线在分支切换时会错位
Jenkins 的 Git plugin 记忆"上次构建的 commit sha"。把 `Branches to build` 从
`*/test/ci-cd` 改成 `*/main` 之后，第一次 push 进来 poke 会被判定"无变化"，build
不起来。**修法**：手动点一次 Build Now 让它重新建立 main 的 last-built 基线。

### 2. Pipeline → Lightweight checkout 在 private repo 上静默失败
默认勾选的 "Lightweight checkout" 用 GitHub API 取 Jenkinsfile，对 private repo
要求 PAT 有完整 `repo` scope。**关掉**这个勾，让它走 git clone（用我们配的 SSH
deploy key），稳定得多。

### 3. 国内 self-hosted runner 上传 artifact 易超时
GitHub Actions `upload-artifact@v4` 走 `results-receiver.actions.githubusercontent.com`
（Twirp RPC）+ `*.blob.core.windows.net`。后者从 mainland 通常能直达，前者跨境
经常 ECONNRESET / FinalizeArtifact timeout。**修法**：让 actions-runner 显式走
本地代理 —— 在 runner 安装目录加 `.env`：
```
http_proxy=http://127.0.0.1:10808
https_proxy=http://127.0.0.1:10808
no_proxy=localhost,127.0.0.1
```
**注意 `no_proxy` 必须包含 `127.0.0.1`**，否则 runner 调本机 Jenkins
(`http://127.0.0.1:8081`) 也走代理就完了。

### 4. PyPI 直连不稳定，必须用国内镜像
后端 Jenkinsfile 已经写死了 `PIP_INDEX_URL=https://repo.huaweicloud.com/repository/pypi/simple/`
（华为云内网镜像），TUNA + PyPI 作 fallback。Jenkins 服务器换到非华为云时记得
改这个 env。

### 5. Branch protection on main
团队可能为 `main` 开了"必须 PR 才能合"。如果 push 直接到 main 报权限错，正确流程
是 `git checkout -b feat/xxx` → push → 开 PR → review → merge。

### 6. Webhook 一定要带末尾斜杠
GitHub webhook 设 Payload URL 必须是 `http://139.159.143.195:8080/github-webhook/`，
**末尾斜杠**少一个就是 404。

## 凭证清单

### Frontend Jenkins (zzh laptop)
- `github-deploy-key-team-project-frontend`（SSH key）—— clone 本仓库用
- admin 用户 API token —— 存在 GitHub secrets 里：`JENKINS_USERNAME` + `JENKINS_API_TOKEN`，给 GH Action self-hosted runner 调 Jenkins API 用

### Backend Jenkins (root@139.159.143.195)
- `github-deploy-key-team-project`（SSH key）—— clone 本仓库用
- `github-status-token-team-project`（Secret text）—— PAT with `repo:status` scope，给 commit status setter 用
- 同一台 Jenkins 上还有针对独立 `Backend_ItsMapPin` 仓库的另一套（`github-deploy-key-backend-itsmappin-ci` + `github-status-token-backend`），两套并存互不影响

## 这次 CI 搭建的来龙去脉

整套 CI 的搭建过程在 main 上留下了几个 **`trigger: ...` 开头的 empty commit**：

| commit | 调通了什么 |
|---|---|
| `6e0d7ec` | 终极验证：单次 push 同时触发前后端 Jenkins（暴露了前端 GH Action 只监听 `test/ci-cd`，不监听 main 的 bug，由后续 `a90221d` 修复） |
| `cf50fef` | 验证：前端 Jenkins 重建后 API token 刷新到 GH secrets 是否生效 |
| `b0e0775` | 验证：runner `.env` 加 `http_proxy` 后 upload-artifact 是否稳定 |

这些 commit 都是空提交（没有文件变化），保留下来作为**调试痕迹**，方便后人追溯
当时为什么这么改 —— 工程上比 force-push 抹除历史更稳健（main 分支共享，rewrite
会让其他人本地仓库冲突）。

**如果你之后看到类似 `trigger: verify ...` 的提交，那是 CI 实验，不是业务变更**，
直接忽略代码内容（往往是 empty commit）即可。

---

## 相关文档

- 后端 Jenkins 详细配置：[`backend/ci/SETUP.md`](../../backend/ci/SETUP.md)
- 后端 pipeline 定义：[`backend/Jenkinsfile`](../../backend/Jenkinsfile)
- 前端 pipeline 定义：[`Jenkinsfile`](../../Jenkinsfile)
- 后端 CI 工具配置：[`backend/ci/`](../../backend/ci/)
- 本地 hook（可选，默认关）：[`.local-ci/`](../../.local-ci/)
- GH Action 定义：
  - [`.github/workflows/jenkinsfile-check.yml`](../../.github/workflows/jenkinsfile-check.yml)（前端 trigger）
  - [`.github/workflows/backend-jenkinsfile-check.yml`](../../.github/workflows/backend-jenkinsfile-check.yml)（后端结构断言）
