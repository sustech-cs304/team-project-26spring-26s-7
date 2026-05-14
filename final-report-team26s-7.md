# Team Report - TravelPin

**Team ID**: team26s-7

**Project**: TravelPin - HarmonyOS travel journal app

**Date**: 2026-05-14

## 1. Metrics

We report frontend and backend metrics separately because they are implemented in
different languages and measured by different CI tools. The project-level totals
combine only directly comparable metrics: source file count, lines of code, and
direct dependency count. Cyclomatic complexity is shown per side instead of
being added together.

### 1.1 Metrics Sources

Frontend CI artifact:

- Runner path: `D:\Mydata\1University\3Junior\Software_Engineering\project\frontendv1\team-project-26spring-26s-7\ci-artifacts\build-11\metrics\summary.txt`
- Repo-relative path: `ci-artifacts/build-11/metrics/summary.txt`
- CI build: frontend Jenkins build 11

Backend CI artifact:

- Runner path: `D:\Mydata\1University\3Junior\Software_Engineering\project\frontendv1\team-project-26spring-26s-7\.be-ci-artifacts\team-project-backend-12-53bac8dc\backend\metrics\summary.txt`
- Repo-relative path: `.be-ci-artifacts/team-project-backend-12-53bac8dc/backend/metrics/summary.txt`
- CI build: backend Jenkins build 12, commit `53bac8dc`

### 1.2 Project Summary

| Metric | Frontend | Backend | Project Total | Notes |
|---|---:|---:|---:|---|
| Source files | 87 `.ets` | 36 `.py` | 123 | CI source-file counts |
| LOC, total lines | 25,747 | 5,673 | 31,420 | Frontend total lines + backend service lines |
| Direct dependencies | 6 | 11 | 17 | Frontend package manifest + backend service requirements |

### 1.3 Frontend Metrics

| Metric | Value | Source / Notes |
|---|---:|---|
| Source files | 87 | `.ets` files counted by frontend CI |
| LOC, total lines | 25,747 | `LOC (total lines)` |
| NLOC | 21,036 | `NLOC (lizard)` |
| Comment/blank density | 18.3% | From frontend metrics summary |
| Functions detected | 807 | PowerShell brace-matched scan |
| File-level cyclomatic complexity | 2,402 total / 27.6 average per file | Regex-based file-level CCN |
| Function-level cyclomatic complexity | 2,777 total / 3.44 average per function | PowerShell per-function parser |
| Direct dependencies | 6 | 4 runtime + 2 dev dependencies |

Frontend direct dependencies:

- Runtime: `@hw-agconnect/auth`, `@hw-agconnect/auth-component`,
  `@hw-agconnect/cloud`, `@hw-agconnect/hmcore`
- Dev: `@ohos/hamock`, `@ohos/hypium`

Frontend complexity hotspots:

| CCN | File | LOC |
|---:|---|---:|
| 221 | `feature/map-travel/views/MapHomeView.ets` | 1,877 |
| 149 | `feature/map-travel/pages/TripReplayPage.ets` | 1,335 |
| 121 | `common/service/RdbDataService.ets` | 914 |
| 105 | `feature/ai-copy/pages/AiCopyPage.ets` | 1,034 |
| 103 | `common/data/MemoryNodeRepository.ets` | 679 |
| 103 | `common/sync/SyncManager.ets` | 546 |
| 100 | `common/data/TravelRepository.ets` | 569 |

Frontend test result in the same CI build:

```text
Tests run: 35, Failure: 0, Error: 0, Pass: 35, Ignore: 0
```

### 1.4 Backend Metrics

| Metric | Value | Source / Notes |
|---|---:|---|
| Source files | 36 | Python files across backend service targets |
| LOC, total lines | 5,673 | Backend Jenkins `loc.txt` |
| Radon CC entries | 280 | Parsed from `cyclomatic-complexity.txt` |
| Radon CC total | 1,001 | Sum of reported Radon CC entries |
| Radon CC average | 3.58 | Computed from Radon CC entries |
| Direct dependencies | 11 | Unique backend service requirements |

Backend service-level metrics:

| Service | Files | LOC | Average Radon CC |
|---|---:|---:|---|
| `ai-relay` | 1 | 431 | B, 5.07 |
| `sensitive-filter` | 1 | 300 | A, 3.85 |
| `picture-check` | 3 | 441 | A, 2.00 |
| `share-service` | 31 | 4,501 | A, 3.58 |

Backend direct dependencies:

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

Backend complexity hotspots from Radon:

| CCN | Function | File |
|---:|---|---|
| 48 | `publish` | `share-service/share_service/routers/publish.py` |
| 19 | `chat_completions_image` | `ai-relay/siliconflow_relay.py` |
| 17 | `test_viewer_html_has_og_meta_tags` | `share-service/share_service/tests/test_publish_api.py` |
| 16 | `chat_completions` | `ai-relay/siliconflow_relay.py` |
| 14 | `SensitiveWordFilter.__init__` | `sensitive-filter/sensitive_filter_service.py` |

## 2. CI/CD Pipeline Description

TravelPin uses a GitHub Actions and Jenkins bridge for the frontend CI pipeline.
GitHub Actions runs on a Windows self-hosted runner, triggers the local Jenkins
job, streams Jenkins logs back into the GitHub Actions job, and uploads the
Jenkins output directory as a GitHub Actions artifact. Jenkins performs the
actual HarmonyOS build, test, package, archive, and metrics stages.

The backend runs on a separate Jenkins job at
`http://139.159.143.195:8080/job/team-project-backend-ci/`. It uses
`backend/Jenkinsfile` and executes the Python backend pipeline directly:
dependency installation, lint reporting, syntax compilation, smoke tests,
pytest, coverage generation, metrics collection, and artifact packaging.

### Frontend Pipeline Steps

| Step | What it does | Tools / Technologies |
|---|---|---|
| Checkout | Fetches the latest repository state for the CI run. | GitHub Actions `actions/checkout@v4`, Jenkins `checkout scm` |
| Trigger Jenkins | Starts the local Jenkins job and streams logs into GitHub Actions. | PowerShell, `scripts/watch-jenkins-build.ps1`, Jenkins HTTP API |
| Prepare Outputs | Creates per-build artifact folders under `ci-artifacts/build-{BUILD_NUMBER}`. | Jenkins, PowerShell |
| Clean | Cleans build caches and previous generated outputs. | Windows shell / PowerShell |
| Install Dependencies | Installs HarmonyOS frontend dependencies. | OHPM |
| Compile | Builds the HarmonyOS HAP package. | `frontend/build.ps1 --mode module -p module=entry@default assembleHap`, Hvigor |
| Test | Runs the business test suite. | `frontend/build.ps1 test`, Hypium |
| Archive | Archives generated HAP packages and test/coverage reports. | Jenkins `archiveArtifacts`, GitHub Actions artifact upload |
| Metrics | Computes source file count, LOC, CCN, function count, and dependency count. | Jenkinsfile PowerShell metrics script |

### Backend Jenkins Pipeline Steps

| Step | What it does | Tools / Technologies |
|---|---|---|
| Checkout | Checks out the team project repository and records the short Git commit SHA. | Jenkins `checkout scm`, Git |
| Prepare Outputs | Creates the external CI artifact directory and workspace staging directory, then writes build metadata. | Jenkins, Bash, `/var/lib/jenkins/ci-artifacts/team-project-backend/build-{BUILD_NUMBER}` |
| Clean | Removes Python cache directories and previous backend build/test outputs. | Bash, `find`, `rm` |
| Install Dependencies | Creates or reuses `backend/.ci-venv`, installs CI tooling and service requirements with a hash-based dependency cache, and writes `pip-freeze.txt`. | Python venv, pip, HuaweiCloud PyPI mirror, TUNA fallback |
| Lint | Runs Ruff on `ai-relay`, `sensitive-filter`, `picture-check`, `share-service`, and `ci`; lint is warn-only and writes `reports/lint-ruff.txt`. | `ruff==0.6.9` |
| Compile | Performs Python syntax compilation for backend service and CI modules. | `python -m compileall -q` |
| Test | Runs import smoke checks for `ai-relay`, `sensitive-filter`, and `picture-check`, then runs the `share-service` pytest suite with JUnit XML and coverage reports. | `backend/ci/smoke_imports.py`, `pytest`, `pytest-cov` |
| Metrics | Counts Python files and LOC, computes Radon cyclomatic complexity, maintainability index, raw stats, and writes backend `metrics/summary.txt`. | `radon cc`, `radon mi`, `radon raw`, Bash |
| Archive | Packages backend source, reports, metrics, metadata, and logs into tarballs with checksums, then archives them in Jenkins. | `tar`, `sha256sum`, Jenkins `archiveArtifacts` |

### Triggering and Feedback

- Frontend trigger: pushes to `main` and `test/ci-cd` start the GitHub Actions
  bridge, which triggers the local frontend Jenkins job `travelpin-ci`.
- Backend trigger: pushes to the team project repository are delivered to
  `http://139.159.143.195:8080/github-webhook/`; the Jenkins job
  `team-project-backend-ci` checks out the configured branch and runs
  `backend/Jenkinsfile`.
- Frontend feedback: GitHub Actions shows the bridge status and uploads Jenkins
  logs/artifacts; the frontend Jenkins job shows stage-level build status.
- Backend feedback: the backend Jenkins job shows stage-level status and posts
  the GitHub commit status context `jenkins/team-project-backend-ci`.

### Pipeline Configuration

- Frontend GitHub Actions workflow: [`.github/workflows/jenkinsfile-check.yml`](.github/workflows/jenkinsfile-check.yml)
- Frontend Jenkins pipeline: [`Jenkinsfile`](Jenkinsfile)
- Jenkins bridge script: [`scripts/watch-jenkins-build.ps1`](scripts/watch-jenkins-build.ps1)
- Backend Jenkins pipeline: [`backend/Jenkinsfile`](backend/Jenkinsfile)

### Successful Execution Evidence

The following screenshot shows one commit receiving both frontend and backend CI
checks. GitHub displays each check with a status icon, so contributors can see
success or failure feedback directly on the commit.

![Frontend and backend CI checks on one commit](documents/screenshots/front_back_allpass_example.jpg)

Frontend proof:

- GitHub Actions run URL:
  <https://github.com/sustech-cs304/team-project-26spring-26s-7/actions/runs/25851795537/job/75959874734>
- Local artifact directory on the runner:
  `D:\Mydata\1University\3Junior\Software_Engineering\project\frontendv1\team-project-26spring-26s-7\ci-artifacts\build-11`
- Packaged HAP artifacts:
  - `ci-artifacts/build-11/packages/entry-default-signed.hap`
  - `ci-artifacts/build-11/packages/entry-default-unsigned.hap`

![Frontend GitHub Actions success](documents/screenshots/frontend_jenkins_github_success_total.jpg)

![Frontend Jenkins status](documents/screenshots/frontend_jenkins_status.jpg)

![Frontend Jenkins stage view](documents/screenshots/frontend_jenkins_stages.jpg)

![Frontend GitHub Actions uploaded artifact](documents/screenshots/frontend_jenkins_github_artifact.jpg)

Backend proof:

- Backend Jenkins URL:
  <http://139.159.143.195:8080/job/team-project-backend-ci/>

![Backend Jenkins status](documents/screenshots/backend_jenkins_status.jpg)

![Backend Jenkins stage view](documents/screenshots/backend_jenkins_stages.jpg)
