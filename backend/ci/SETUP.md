# Backend CI Setup —— team-project-26spring-26s-7

Adds a **second Jenkins job** on the existing backend Jenkins server
(`root@139.159.143.195:8080`) that watches **this** repo
(`sustech-cs304/team-project-26spring-26s-7`) instead of the standalone
`Backend_ItsMapPin` repo. Both jobs coexist independently — they run on the
same Jenkins controller but watch different GitHub remotes.

This is the **backend** side. The **frontend** side has its own Jenkins on
zzh's Windows laptop, triggered via a self-hosted GitHub Actions runner.
Both fire on every push to `main` and post their own commit status check.

```
git push to team-project/main
        │
        ▼
   GitHub repo
   │                                          │
   │ webhook (any push)                       │ GH Action paths=frontend
   ▼                                          ▼
139.159.143.195:8080                  zzh laptop (self-hosted runner)
team-project-backend-ci job                   │
   │                                          │ curl localhost:8081
   │                                          ▼
   ▼                                  zzh laptop Jenkins
   posts status:                      travelpin-ci job
   jenkins/team-project-backend-ci             │
                                               ▼
                                       posts status:
                                       jenkins/travelpin-ci
```

## A. Generate a GitHub Deploy Key for THIS repo (Jenkins → GitHub)

Run on the backend Jenkins server as `jenkins` user:

```bash
ssh root@139.159.143.195
sudo -u jenkins -H bash -lc '
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  if [ ! -f ~/.ssh/id_ed25519_team_project ]; then
    ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519_team_project \
      -C "jenkins@hcss-ecs-cfee:team-project-26spring-26s-7"
  fi
  ssh-keyscan -t ed25519,rsa github.com >> ~/.ssh/known_hosts 2>/dev/null
  sort -u ~/.ssh/known_hosts -o ~/.ssh/known_hosts
  echo "=== PUBLIC KEY (copy to GitHub) ==="
  cat ~/.ssh/id_ed25519_team_project.pub
  echo "=== PRIVATE KEY (copy to Jenkins credentials) ==="
  cat ~/.ssh/id_ed25519_team_project
'
```

1. Copy the **public key** block.
2. GitHub → repo `sustech-cs304/team-project-26spring-26s-7` → **Settings → Deploy keys → Add deploy key**.
   - Title: `jenkins-139.159.143.195-team-project`
   - Key: paste public key
   - Leave "Allow write access" **unchecked**

## B. Install the private key into Jenkins credentials

Jenkins UI → **Manage Jenkins → Credentials → System → Global credentials → Add Credentials**

- Kind: **SSH Username with private key**
- ID: `github-deploy-key-team-project`  *(exact; SETUP step C below references it)*
- Description: `GitHub deploy key for sustech-cs304/team-project-26spring-26s-7`
- Username: `git`
- Private Key → **Enter directly** → paste the private key block from step A
- Save

## C. Create the second Pipeline job

Jenkins UI → **New Item** → name: **`team-project-backend-ci`** → type: **Pipeline** → OK

| Section | Setting |
|---|---|
| **General** → ✓ GitHub project | URL: `https://github.com/sustech-cs304/team-project-26spring-26s-7/` |
| **Build Triggers** | ✓ GitHub hook trigger for GITScm polling |
| **Pipeline** → Definition | Pipeline script from SCM |
| **SCM** | Git |
| **Repository URL** | `[email protected]:sustech-cs304/team-project-26spring-26s-7.git` |
| **Credentials** | `github-deploy-key-team-project` (the one from step B) |
| **Branches to build** | `*/test/backend-ci` during testing → switch to `*/main` after merge |
| **Script Path** | `backend/Jenkinsfile`  *(critical — not the root frontend Jenkinsfile)* |
| **Lightweight checkout** | UNCHECK (SCM polling fails silently on private repos with Lightweight enabled) |

Save.

## D. Re-use the existing GitHub PAT credential (no new PAT needed)

We already have `github-status-token-backend` from setting up the
`backend-itsmappin-ci` job. The Jenkinsfile in this repo refers to a
**different** credential ID `github-status-token-team-project` for clarity —
add a copy (or just rename the existing one if you no longer need it on the
other job).

Easiest path: clone the credential.

Jenkins UI → Manage Jenkins → Credentials → System → Global credentials →
find `github-status-token-backend` → ⋯ menu → **Move** is read-only; just
**Add** a new one with the same Secret:

- Kind: **Secret text**
- Scope: Global
- Secret: paste the same PAT (same `ghp_…` you used before; collaborator's PAT
  has access to all repos they collaborate on, so the same token works for
  this repo as well, as long as it has `repo:status` scope)
- ID: `github-status-token-team-project`
- Description: `PAT for posting commit status to team-project repo`

## E. Add a webhook on the team-project GitHub repo

GitHub → repo `sustech-cs304/team-project-26spring-26s-7` → **Settings →
Webhooks → Add webhook**:

| Field | Value |
|---|---|
| Payload URL | `http://139.159.143.195:8080/github-webhook/` *(trailing slash)* |
| Content type | `application/json` |
| Events | `Just the push event` |
| Active | ✓ |

The frontend's GH-Action-based trigger continues to coexist with this
webhook — they don't conflict, GitHub fans the push event out to both.

## F. First push test

```bash
cd /data2/cse12310817/ci-server/team-project-26spring-26s-7
git checkout test/backend-ci        # already on it if you followed the script
git push -u origin test/backend-ci
```

Within ~10 seconds you should see:

1. **GitHub webhook delivery 200** (Settings → Webhooks → your hook → Recent Deliveries)
2. **Jenkins job `team-project-backend-ci`** flips to "Build in progress"
3. **GitHub Actions** `Backend Jenkinsfile Check` workflow also runs (structural sanity check)
4. **commit status check** `jenkins/team-project-backend-ci - Pending → Success` appears on the commit

## G. Coexistence verification

Once test/backend-ci is green, **before merging**:

- Make a trivial push (e.g. add a space to a README) to test/backend-ci → only the backend Jenkins should fire (frontend GH Action has `paths:` filter on `frontend/**`).
- Wait until test/ci-cd (frontend) is also merged to main.
- Then make a trivial push to main → **both** Jenkinses should fire, **two** status checks should appear on the commit (jenkins/backend-itsmappin-ci is for the **standalone** repo and won't fire here; the ones for team-project repo are jenkins/team-project-backend-ci + jenkins/travelpin-ci or similar frontend context name).

## H. After it goes green

- Switch this job's branch filter from `*/test/backend-ci` to `*/main`
- Merge `test/backend-ci` → `main` via PR
- Verify the merged commit on main triggers BOTH frontend and backend builds

<!-- ci-trigger-marker: this line exists to validate the backend GH Action paths
     filter (backend/ci/**). Touching this file proves a doc-only edit can
     fan out to both Jenkinses without affecting runtime behavior. -->

## I. 这次后端 CI 搭建的 journey & 后人指南

本仓库后端 CI 是从独立的 `Zmjjeff7/Backend_ItsMapPin` 试验仓搬过来的。完整架构、
两套 Jenkins 的分工、已知陷阱见
[`references/documents/ci-cd-architecture.md`](../../references/documents/ci-cd-architecture.md)。
这里只列搭建过程中**踩过的坑**给后人备查。

### 调通用的痕迹（git log 上 `trigger:` 开头的 empty commit）

调通这套 CI 一共留了若干 `trigger: ...` 开头的空提交（`--allow-empty`），保留作
调试可追溯记录而非 force-push 抹除。**它们都是 CI 实验，不是业务变更**，git log
扫到时直接忽略。

| 阶段 | 在哪里 | 干嘛 |
|---|---|---|
| 后端 Jenkins 走 webhook 直触 | `Backend_ItsMapPin` repo | `fb993e0` / `b00730e` —— 分支过滤 `*/test/ci-cd` → `*/main` 切换时 SCM polling 基线错位，必须 manual Build Now 一次重建 |
| 后端 Jenkins commit status 接通 | `Backend_ItsMapPin` repo | `7d1010a` / `01c1433` —— PAT scope `repo:status` 够用，但插件 `GitHubCommitStatusSetter` 要求 `repo` 完整 scope；解法是绕开插件直接 `curl POST /statuses/{sha}` |
| 后端 CI 迁移到 team-project | 本仓库 | `6e0d7ec` —— 暴露前端 GH Action `branches:` 只列 `test/ci-cd` 不监听 main 的 bug |
| 前端 Jenkins 重建后链路验证 | 本仓库 | `cf50fef` —— Jenkins 重建后 API token 必须同步刷新到 GitHub `JENKINS_API_TOKEN` secret |
| upload-artifact ECONNRESET 修 | 本仓库 | `b0e0775` —— actions-runner 必须用显式 `.env` `http_proxy=` 走本地代理，不能靠 .NET DefaultWebProxy 的隐式探测 |

### 后人改 CI 必读

1. **不要 force-push 到 main**。share 分支历史 = 团队全员的本地状态，rewrite
   等于给所有人挖坑
2. 改完 Jenkinsfile 后**先在 test 分支验证一遍**再 PR 合 main，不然挂在 main 上
   要修很尴尬
3. `Lightweight checkout` 这个勾 Jenkins job → Pipeline 里默认是勾的，**取消勾选**，
   private repo 上它会静默失败
4. PyPI 走华为云 `repo.huaweicloud.com` 内网镜像（已写死在 Jenkinsfile env 中），
   迁移到其它机房记得改
5. 后端 Jenkins 上 SSH key 是按"仓库"区分的（一个 `Backend_ItsMapPin`、一个
   team-project），增加新仓库要单独生成 deploy key + Jenkins credential

### 测试覆盖率（本仓库 share-service 真测）

| Stage | Pass rate | Coverage |
|---|---|---|
| share-service pytest | **111 / 111 passed** | **94%** |
| ai-relay / sensitive-filter / picture-check | smoke import 通过 | — |

业务测试覆盖率 metric 落在 `/var/lib/jenkins/ci-artifacts/team-project-backend/build-N/reports/coverage-share-service-html/` —— 每次成功 build 都会更新一份。

