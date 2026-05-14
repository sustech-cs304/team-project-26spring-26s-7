# Linux CI Migration: Handoff for Claude Code (Server-Side)

## Purpose

This document is an actionable handoff for a Claude Code instance running on the **target Linux server**. It contains everything you need to:

1. Verify the server environment
2. Install missing components
3. Create the Linux-compatible pipeline files
4. Wire up GitHub Actions + Jenkins on Linux
5. Validate end-to-end

**Do not start writing code until you have read this entire document.**

### Reference Branch

The team has pushed the `test/ci-cd` branch to this repository. It will be cloned to `~/ci-server/team-project-26spring-26s-7` on this server for your reference. The Windows source files you are migrating from are:

- `Jenkinsfile`
- `frontend/build.ps1`
- `scripts/watch-jenkins-build.ps1`
- `.github/workflows/jenkinsfile-check.yml`

Read them to understand the existing logic before writing the Linux replacements.

---

## Project Context

- **Repository**: `sustech-cs304/team-project-26spring-26s-7`
- **Project**: TravelPin, a HarmonyOS (ArkTS) travel journal app
- **Course**: SUSTech CS304, 2026 Spring, Group 7
- **Source root**: `frontend/entry/src/main/ets/`
- **Build system**: HarmonyOS `hvigor` via `ohpm`

---

## Current Architecture (Windows — what we are migrating FROM)

```
git push → GitHub Actions (Windows self-hosted runner)
         → watch-jenkins-build.ps1 (PowerShell)
         → Jenkins job "travelpin-ci" (Windows, uses bat/powershell)
         → build.ps1 (PowerShell, hardcoded C:\Apps\DevEco Studio\...)
         → Artifacts in D:\...\ci-artifacts\build-N
         → GitHub Actions uploads .ci-logs + ci-artifacts
```

### Key files to migrate

| File | Current state | Linux target |
|---|---|---|
| `Jenkinsfile` | `bat` / `powershell` blocks, Windows paths, `rmdir /s /q` | `sh` blocks, Linux paths, `rm -rf` |
| `frontend/build.ps1` | Hardcoded `C:\Apps\DevEco Studio\*` paths | New `frontend/build.sh`, env-var-driven |
| `scripts/watch-jenkins-build.ps1` | PowerShell HTTP bridge to Jenkins | New `scripts/watch-jenkins-build.sh` (bash+cURL) |
| `.github/workflows/jenkinsfile-check.yml` | `runs-on: [self-hosted, windows]`, `shell: powershell` | `runs-on: [self-hosted, linux, travelpin]`, `shell: bash` |

---

## Target Architecture (Linux — what we are migrating TO)

```
git push → GitHub Actions (Linux self-hosted runner)
         → watch-jenkins-build.sh (bash + curl)
         → Jenkins job "travelpin-ci" (Linux, uses sh)
         → build.sh (bash, env-var-driven tool paths)
         → Artifacts in ~/ci-server/ci-artifacts/build-N
         → GitHub Actions uploads .ci-logs + ci-artifacts
```

### Linux directory layout

All CI-related files live under `/data2/cse12310817/ci-server`. This is the designated base directory on the server.

| Purpose | Path |
|---|---|
| CI base directory | `~/ci-server` |
| Repository reference clone | `~/ci-server/team-project-26spring-26s-7` |
| Jenkins home | `/var/lib/jenkins` (system package default) |
| GitHub runner | `~/ci-server/actions-runner` |
| HarmonyOS CLI tools | `~/ci-server/harmony-commandline-tools` |
| Artifact root | `~/ci-server/ci-artifacts` |
| CI logs (repo-local) | `.ci-logs/` |

---

## Step 0. Verify Environment

Run these checks first. If anything fails, fix it before proceeding.

```bash
# Java 21+ (required by Jenkins)
java -version

# Node.js (required by hvigor)
node -v
npm -v

# Jenkins service running
sudo systemctl status jenkins

# GitHub runner service running
sudo systemctl status actions.runner.*

# Jenkins accessible
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8081/api/json
# Expected: 401 or 403 (auth required = Jenkins is running)

# Artifact directory exists
ls -la ~/ci-server/ci-artifacts

# HarmonyOS tools exist
ls ~/ci-server/harmony-commandline-tools/
# Should contain: sdkmgr, ohpm, hvigor, node or similar
```

If Jenkins is not installed, follow Step 1. If the runner is not installed, follow Step 2. If HarmonyOS tools are missing, follow Step 3.

---

## Step 1. Install Jenkins (if not present)

```bash
sudo apt update
sudo apt install -y fontconfig openjdk-21-jre
java -version

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

If port 8080 is occupied, change Jenkins to 8081:

```bash
sudo sed -i 's/--httpPort=8080/--httpPort=8081/' /etc/default/jenkins
sudo systemctl restart jenkins
```

Initial admin password:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Required Jenkins plugins: Pipeline, Git, Credentials Binding, Workspace Cleanup.

---

## Step 2. Install GitHub Self-Hosted Runner (if not present)

Register in the GitHub repo Settings → Actions → Runners → New self-hosted runner. Choose Linux, then:

```bash
mkdir -p ~/ci-server/actions-runner
cd ~/ci-server/actions-runner
# Follow the GitHub instructions to download and extract the runner

./config.sh --url https://github.com/sustech-cs304/team-project-26spring-26s-7 --token <TOKEN>

# Set labels: self-hosted, linux, travelpin

sudo ./svc.sh install   # svc.sh needs root to register as a system service
sudo ./svc.sh start
```

---

## Step 3. Install HarmonyOS Command Line Tools (if not present)

Download from: https://developer.huawei.com/consumer/cn/deveco-studio/archive/

Look for `commandline-tools-linux-*.zip`.

```bash
mkdir -p ~/ci-server/harmony-commandline-tools
unzip commandline-tools-linux-*.zip -d ~/ci-server/harmony-commandline-tools
```

After extraction, locate these specific binaries — you will need their exact paths for environment variables:

```bash
# Find the tools
find ~/ci-server/harmony-commandline-tools -name 'ohpm' -type f
find ~/ci-server/harmony-commandline-tools -name 'hvigorw' -o -name 'hvigorw.js' -type f
find ~/ci-server/harmony-commandline-tools -name 'node' -type f
find ~/ci-server/harmony-commandline-tools -name 'sdkmgr' -type f
```

Record the actual paths. These become the `HARMONY_*` environment variables below.

---

## Step 4. Prepare Artifact Directory

```bash
mkdir -p ~/ci-server/ci-artifacts
```

---

## Step 5. Create `frontend/build.sh`

Create this file at `frontend/build.sh` in the repository. This replaces `frontend/build.ps1` for Linux.

```bash
#!/usr/bin/env bash
set -euo pipefail

# TravelPin Linux build entrypoint
# Replaces frontend/build.ps1 for Linux CI.
#
# Required environment variables:
#   HARMONY_SDK_HOME  - Path to HarmonyOS SDK root
#   HARMONY_NODE      - Path to Node.js binary (from HarmonyOS tools)
#   HARMONY_HVIGOR    - Path to hvigorw.js
#
# Usage:
#   ./build.sh [--mode module] [-p module=entry@default] assembleHap
#   ./build.sh test

: "${HARMONY_SDK_HOME:?HARMONY_SDK_HOME is required}"
: "${HARMONY_NODE:?HARMONY_NODE is required}"
: "${HARMONY_HVIGOR:?HARMONY_HVIGOR is required}"

export DEVECO_SDK_HOME="$HARMONY_SDK_HOME"

cd "$(dirname "$0")"

echo "[build.sh] DEVECO_SDK_HOME=$DEVECO_SDK_HOME"
echo "[build.sh] Node: $("$HARMONY_NODE" -v)"
echo "[build.sh] Running: $HARMONY_NODE $HARMONY_HVIGOR $*"

"$HARMONY_NODE" "$HARMONY_HVIGOR" "$@"
```

Make it executable:

```bash
chmod +x frontend/build.sh
```

---

## Step 6. Create `scripts/watch-jenkins-build.sh`

Create this file at `scripts/watch-jenkins-build.sh`. This replaces `scripts/watch-jenkins-build.ps1`.

```bash
#!/usr/bin/env bash
set -euo pipefail

# TravelPin Linux Jenkins build watcher
# Replaces scripts/watch-jenkins-build.ps1 for Linux CI.
#
# Usage:
#   ./watch-jenkins-build.sh \
#     --base-url http://127.0.0.1:8081 \
#     --job-name travelpin-ci \
#     --username USER \
#     --api-token TOKEN \
#     [--log-dir .ci-logs] \
#     [--metadata-path .ci-logs/latest-run.json]

BASE_URL=""
JOB_NAME=""
USERNAME=""
API_TOKEN=""
LOG_DIR=".ci-logs"
METADATA_PATH=""
POLL_INTERVAL=2
TIMEOUT=1800

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)     BASE_URL="$2"; shift 2 ;;
    --job-name)     JOB_NAME="$2"; shift 2 ;;
    --username)     USERNAME="$2"; shift 2 ;;
    --api-token)    API_TOKEN="$2"; shift 2 ;;
    --log-dir)      LOG_DIR="$2"; shift 2 ;;
    --metadata-path) METADATA_PATH="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

[[ -z "$BASE_URL"  ]] && { echo "ERROR: --base-url is required"; exit 1; }
[[ -z "$JOB_NAME"  ]] && { echo "ERROR: --job-name is required"; exit 1; }
[[ -z "$USERNAME"  ]] && { echo "ERROR: --username is required"; exit 1; }
[[ -z "$API_TOKEN" ]] && { echo "ERROR: --api-token is required"; exit 1; }

AUTH_HEADER="Authorization: Basic $(printf '%s:%s' "$USERNAME" "$API_TOKEN" | base64)"

# Build job URL from job name (handle folders)
JOB_PATH=$(echo "$JOB_NAME" | sed 's|/|/job/|g')
JOB_URL="${BASE_URL%/}/${JOB_PATH}"

mkdir -p "$LOG_DIR"

echo "[jenkins] Triggering job '$JOB_NAME' at $JOB_URL"

# Trigger build
QUEUE_LOCATION=$(curl -s -D - -o /dev/null -X POST \
  "$JOB_URL/build" \
  -H "$AUTH_HEADER" 2>&1 | grep -i '^location:' | head -1 | sed 's/[Ll]ocation:[[:space:]]*//' | tr -d '\r\n')

if [[ -z "$QUEUE_LOCATION" ]]; then
  echo "ERROR: Jenkins did not return a queue location header."
  exit 1
fi

# Make queue URL absolute if relative
if [[ "$QUEUE_LOCATION" == /* ]]; then
  QUEUE_URL="${BASE_URL%/}${QUEUE_LOCATION}"
else
  QUEUE_URL="$QUEUE_LOCATION"
fi

QUEUE_API="${QUEUE_URL%/}/api/json"
echo "[jenkins] Queued: $QUEUE_URL"

# Resolve repo root for relative paths
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
resolve_path() {
  if [[ "$1" = /* ]]; then echo "$1"; else echo "${REPO_ROOT}/$1"; fi
}

LOG_DIR_RESOLVED=$(resolve_path "$LOG_DIR")
METADATA_PATH_RESOLVED=""
[[ -n "$METADATA_PATH" ]] && METADATA_PATH_RESOLVED=$(resolve_path "$METADATA_PATH")

# Poll queue until build starts
BUILD_NUMBER=""
BUILD_URL=""
DEADLINE=$((SECONDS + TIMEOUT))

while [[ -z "$BUILD_NUMBER" ]]; do
  if [[ $SECONDS -ge $DEADLINE ]]; then
    echo "ERROR: Timed out waiting for Jenkins queue after ${TIMEOUT}s."
    exit 1
  fi

  QUEUE_JSON=$(curl -s -H "$AUTH_HEADER" "$QUEUE_API")

  CANCELLED=$(echo "$QUEUE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cancelled',False))" 2>/dev/null || echo "false")
  if [[ "$CANCELLED" == "True" ]]; then
    echo "ERROR: Jenkins queue item was cancelled."
    exit 1
  fi

  EXECUTABLE=$(echo "$QUEUE_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ex = d.get('executable')
if ex and ex.get('number'):
    print(f\"{ex['number']}|{ex['url'].rstrip('/')}\")
" 2>/dev/null || echo "")

  if [[ -n "$EXECUTABLE" ]]; then
    BUILD_NUMBER="${EXECUTABLE%%|*}"
    BUILD_URL="${EXECUTABLE##*|}"
    break
  fi

  WHY=$(echo "$QUEUE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('why',''))" 2>/dev/null || echo "")
  [[ -n "$WHY" ]] && echo "[jenkins] Waiting in queue: $WHY"

  sleep "$POLL_INTERVAL"
done

BUILD_API="${BUILD_URL}/api/json"
SAFE_JOB_NAME=$(echo "$JOB_NAME" | sed 's/[^A-Za-z0-9._-]/_/g')
LOG_FILE="${LOG_DIR_RESOLVED}/jenkins-${SAFE_JOB_NAME}-build-${BUILD_NUMBER}.log"

{
  echo "Jenkins job: $JOB_NAME"
  echo "Build URL: $BUILD_URL"
  echo "Started at: $(date -Iseconds)"
  echo ""
} > "$LOG_FILE"

# Write metadata
if [[ -n "$METADATA_PATH_RESOLVED" ]]; then
  mkdir -p "$(dirname "$METADATA_PATH_RESOLVED")"
  cat > "$METADATA_PATH_RESOLVED" <<META_EOF
{
  "jobName": "$JOB_NAME",
  "buildNumber": $BUILD_NUMBER,
  "buildUrl": "$BUILD_URL",
  "logPath": "$LOG_FILE",
  "generatedAt": "$(date -Iseconds)"
}
META_EOF
fi

echo "[jenkins] Streaming build #$BUILD_NUMBER"
echo "[jenkins] Log file: $LOG_FILE"

# Stream console output
LOG_OFFSET=0
while true; do
  if [[ $SECONDS -ge $DEADLINE ]]; then
    echo "ERROR: Timed out waiting for build #$BUILD_NUMBER after ${TIMEOUT}s."
    exit 1
  fi

  PROGRESS_URL="${BUILD_URL}/logText/progressiveText?start=${LOG_OFFSET}"
  PROGRESS_RESPONSE=$(curl -s -D /tmp/jenkins-headers.txt -o /tmp/jenkins-body.txt \
    -H "$AUTH_HEADER" "$PROGRESS_URL")

  CONTENT=$(cat /tmp/jenkins-body.txt)
  # Strip ANSI escape sequences
  CLEAN_CONTENT=$(echo "$CONTENT" | sed 's/\x1b\[[0-9;]*[A-Za-z]//g; s/\x1b\[8mha:.*\x1b\[0m//g')

  if [[ -n "$CLEAN_CONTENT" ]]; then
    echo -n "$CLEAN_CONTENT"
    echo -n "$CLEAN_CONTENT" >> "$LOG_FILE"
  fi

  TEXT_SIZE=$(grep -i 'x-text-size:' /tmp/jenkins-headers.txt | sed 's/[xX]-[tT]ext-[sS]ize:[[:space:]]*//' | tr -d '\r\n')
  if [[ -n "$TEXT_SIZE" ]]; then
    LOG_OFFSET="$TEXT_SIZE"
  else
    LOG_OFFSET=$((LOG_OFFSET + ${#CONTENT}))
  fi

  MORE_DATA=$(grep -i 'x-more-data:' /tmp/jenkins-headers.txt | sed 's/[xX]-[mM]ore-[dD]ata:[[:space:]]*//' | tr -d '\r\n')
  if [[ "$MORE_DATA" == "true" ]]; then
    sleep "$POLL_INTERVAL"
    continue
  fi

  # Check if build is still running
  BUILD_INFO=$(curl -s -H "$AUTH_HEADER" "$BUILD_API")
  BUILDING=$(echo "$BUILD_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('building',False))" 2>/dev/null || echo "false")
  RESULT=$(echo "$BUILD_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('result','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")

  if [[ "$BUILDING" == "True" ]]; then
    sleep "$POLL_INTERVAL"
    continue
  fi

  echo ""
  echo "[jenkins] Build #$BUILD_NUMBER finished with status: $RESULT"

  if [[ "$RESULT" != "SUCCESS" ]]; then
    exit 1
  fi
  exit 0
done
```

Make it executable:

```bash
chmod +x scripts/watch-jenkins-build.sh
```

**Note**: This script requires `python3` for JSON parsing. If not available, install it or replace the `python3 -c` calls with `jq`.

---

## Step 7. Create the Linux Jenkinsfile

Create `Jenkinsfile.linux` in the repository root. This is the Linux-compatible version of `Jenkinsfile`. The Jenkins job should be pointed to this file (or you can rename it to `Jenkinsfile` once Windows CI is decommissioned).

```groovy
pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        skipStagesAfterUnstable()
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        // These MUST be set in Jenkins global config or job config (use absolute paths):
        //   HARMONY_SDK_HOME   - e.g. /data2/cse12310817/ci-server/harmony-commandline-tools/sdk
        //   HARMONY_NODE       - e.g. /data2/cse12310817/ci-server/harmony-commandline-tools/tools/node/bin/node
        //   HARMONY_OHPM       - e.g. /data2/cse12310817/ci-server/harmony-commandline-tools/tools/ohpm/bin/ohpm
        //   HARMONY_HVIGOR     - e.g. /data2/cse12310817/ci-server/harmony-commandline-tools/tools/hvigor/bin/hvigorw.js
        //   LOCAL_ARTIFACT_ROOT - e.g. /data2/cse12310817/ci-server/ci-artifacts
        LOCAL_ARTIFACT_ROOT_DEFAULT = '/data2/cse12310817/ci-server/ci-artifacts'
        ANSI_RESET  = "[0m"
        ANSI_GREEN  = "[32m"
        ANSI_RED    = "[31m"
        ANSI_YELLOW = "[33m"
        ANSI_CYAN   = "[36m"
    }

    stages {
        stage('Checkout') {
            steps {
                script {
                    echo ''
                    echo '============================================================'
                    echo '  Stage: Checkout'
                    echo '============================================================'
                    echo ''
                    checkout scm
                }
            }
        }

        stage('Prepare Outputs') {
            steps {
                script {
                    echo ''
                    echo '============================================================'
                    echo '  Stage: Prepare Outputs'
                    echo '============================================================'
                    echo ''
                    def artifactRoot = env.LOCAL_ARTIFACT_ROOT?.trim()
                    if (!artifactRoot) {
                        artifactRoot = env.LOCAL_ARTIFACT_ROOT_DEFAULT
                    }
                    env.CI_OUTPUT_DIR = "${artifactRoot}/build-${env.BUILD_NUMBER}"
                    echo "Output directory: ${env.CI_OUTPUT_DIR}"
                    echo ''
                    sh """
                        mkdir -p ${env.CI_OUTPUT_DIR}/{logs,reports,packages,metrics,meta}

                        cat > ${env.CI_OUTPUT_DIR}/meta/build-info.txt <<'BUILDINFO'
Job Name: ${env.JOB_NAME}
Build Number: ${env.BUILD_NUMBER}
Build URL: ${env.BUILD_URL}
Workspace: ${env.WORKSPACE}
Git Branch: ${env.GIT_BRANCH}
Started At: \$(date -Iseconds)
BUILDINFO
                    """
                }
            }
        }

        stage('Clean') {
            steps {
                script {
                    echo ''
                    echo '============================================================'
                    echo '  Stage: Clean'
                    echo '============================================================'
                    echo ''
                    dir('frontend') {
                        sh '''
                            rm -rf entry/build .hvigor oh_modules entry/oh_modules
                        '''
                    }
                }
            }
        }

        stage('Install Dependencies') {
            steps {
                script {
                    echo ''
                    echo '============================================================'
                    echo '  Stage: Install Dependencies'
                    echo '============================================================'
                    echo ''
                    dir('frontend') {
                        sh """
                            \${HARMONY_OHPM} install > \${CI_OUTPUT_DIR}/logs/install-dependencies.log 2>&1
                            EXIT_CODE=\$?
                            grep -v -i -E 'ArkTS:WARN|Warning:|Switching off type checks|Function may throw exceptions|has been deprecated|is not supported on all devices' \${CI_OUTPUT_DIR}/logs/install-dependencies.log || true
                            exit \$EXIT_CODE
                        """
                    }
                }
            }
        }

        stage('Compile') {
            steps {
                script {
                    echo ''
                    echo '============================================================'
                    echo '  Stage: Compile'
                    echo '============================================================'
                    echo ''
                    dir('frontend') {
                        sh """
                            chmod +x build.sh
                            ./build.sh --mode module -p module=entry@default assembleHap > \${CI_OUTPUT_DIR}/logs/compile.log 2>&1
                            EXIT_CODE=\$?
                            grep -v -i -E 'ArkTS:WARN|Warning:|Switching off type checks|Function may throw exceptions|has been deprecated|is not supported on all devices|@Entry decorator' \${CI_OUTPUT_DIR}/logs/compile.log || true
                            exit \$EXIT_CODE
                        """
                    }
                }
            }
        }

        stage('Test') {
            steps {
                script {
                    echo ''
                    echo '============================================================'
                    echo '  Stage: Test'
                    echo '============================================================'
                    echo ''
                    dir('frontend') {
                        sh """
                            ./build.sh test > \${CI_OUTPUT_DIR}/logs/test.log 2>&1
                            EXIT_CODE=\$?
                            grep -v -i -E 'ArkTS:WARN|Warning:|Switching off type checks|Function may throw exceptions|has been deprecated|is not supported on all devices|@Entry decorator' \${CI_OUTPUT_DIR}/logs/test.log || true
                            exit \$EXIT_CODE
                        """
                    }
                }
            }
            post {
                always {
                    script {
                        echo ''
                        echo '------------------------------------------------------------'
                        echo '  Collecting and Processing Test Reports'
                        echo '------------------------------------------------------------'
                        echo ''
                        dir('frontend/entry/.test/default/intermediates/test/coverage_data') {
                            sh '''
                                RESULT_FILE="test_result.txt"
                                if [ -f "$RESULT_FILE" ]; then
                                    echo "============================================================"
                                    echo "  TEST RESULTS"
                                    echo "============================================================"
                                    grep -v -E '@Entry decorator|recommended way to export struct|ACE Engine error in component preview' "$RESULT_FILE" || true
                                    echo ""
                                    echo "============================================================"
                                    echo "  END TEST RESULTS"
                                    echo "============================================================"
                                else
                                    echo "WARNING: test_result.txt not found - tests may not have run"
                                fi
                            '''
                        }
                        dir('frontend/entry/.test/default/outputs/test') {
                            archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
                            sh """
                                mkdir -p ${env.CI_OUTPUT_DIR}/reports/test
                                cp -r reports/* ${env.CI_OUTPUT_DIR}/reports/test/ 2>/dev/null || true
                            """
                        }
                        dir('frontend/entry/.test/default/intermediates/test') {
                            archiveArtifacts artifacts: '*.json, coverage_data/**', allowEmptyArchive: true
                            sh """
                                mkdir -p ${env.CI_OUTPUT_DIR}/reports/coverage
                                cp -f *.json ${env.CI_OUTPUT_DIR}/reports/coverage/ 2>/dev/null || true
                                cp -r coverage_data ${env.CI_OUTPUT_DIR}/reports/coverage/ 2>/dev/null || true
                            """
                        }
                    }
                }
            }
        }

        stage('Archive') {
            steps {
                script {
                    echo ''
                    echo '============================================================'
                    echo '  Stage: Archive'
                    echo '============================================================'
                    echo ''
                    dir('frontend/entry/build/default/outputs/default') {
                        archiveArtifacts artifacts: '*.hap', fingerprint: true
                        sh """
                            cp -f *.hap ${env.CI_OUTPUT_DIR}/packages/ 2>/dev/null || true
                            cp -f pack.info ${env.CI_OUTPUT_DIR}/packages/ 2>/dev/null || true
                        """
                    }
                }
            }
        }

        stage('Metrics') {
            steps {
                script {
                    echo ''
                    echo '============================================================'
                    echo '  Stage: Collect Metrics'
                    echo '============================================================'
                    echo ''
                    dir('frontend/entry/src/main/ets') {
                        sh """
                            METRICS_PATH="${env.CI_OUTPUT_DIR}/metrics/summary.txt"

                            LINE_COUNT=0
                            FILE_COUNT=0
                            COMPLEXITY=0

                            while IFS= read -r -d '' f; do
                                LINES=\$(wc -l < "\$f")
                                LINE_COUNT=\$((LINE_COUNT + LINES))
                                FILE_COUNT=\$((FILE_COUNT + 1))

                                CONTENT=\$(cat "\$f")
                                DP=0
                                DP=\$((DP + \$(echo "\$CONTENT" | grep -c -E '\\bif\\b' || true)))
                                DP=\$((DP + \$(echo "\$CONTENT" | grep -c -E '\\bfor\\b' || true)))
                                DP=\$((DP + \$(echo "\$CONTENT" | grep -c -E '\\bwhile\\b' || true)))
                                DP=\$((DP + \$(echo "\$CONTENT" | grep -c -E '\\bcatch\\b' || true)))
                                DP=\$((DP + \$(echo "\$CONTENT" | grep -c -E '\\bcase\\b' || true)))
                                DP=\$((DP + \$(echo "\$CONTENT" | grep -c -E '\\?' || true)))
                                DP=\$((DP + \$(echo "\$CONTENT" | grep -c -E '&&|\\|\\|' || true)))
                                COMPLEXITY=\$((COMPLEXITY + 1 + DP))
                            done < <(find . -name '*.ets' -print0)

                            DEPENDENCIES=\$(cat ../../../oh-package.json5)

                            {
                                echo "Lines of Code:"
                                echo "\$LINE_COUNT"
                                echo ""
                                echo "Number of Source Files:"
                                echo "\$FILE_COUNT"
                                echo ""
                                echo "Cyclomatic Complexity (Approximate):"
                                echo "\$COMPLEXITY"
                                echo ""
                                echo "Dependencies:"
                                echo "\$DEPENDENCIES"
                            } | tee "\$METRICS_PATH"
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                echo ''
                echo '============================================================'
                echo '  PIPELINE COMPLETED'
                echo '============================================================'
                echo ''
                env.CI_BUILD_RESULT = currentBuild.currentResult
                sh """
                    cat > ${env.CI_OUTPUT_DIR}/meta/build-result.txt <<EOF
Build Status: ${env.CI_BUILD_RESULT}
Finished At: \$(date -Iseconds)
EOF

                    find ${env.CI_OUTPUT_DIR} -type f > ${env.CI_OUTPUT_DIR}/meta/artifact-manifest.txt
                """
            }
        }
    }
}
```

---

## Step 8. Create the Linux GitHub Actions Workflow

Create `.github/workflows/jenkinsfile-check.yml` with this content (replacing the Windows version):

```yaml
name: Jenkinsfile Check

on:
  push:
    branches:
      - test/ci-cd

permissions:
  contents: read

concurrency:
  group: jenkinsfile-check-${{ github.ref }}
  cancel-in-progress: true

jobs:
  jenkinsfile-check:
    runs-on:
      - self-hosted
      - linux
      - travelpin
    env:
      JENKINS_BASE_URL: http://127.0.0.1:8081
      JENKINS_JOB_NAME: travelpin-ci
      LOCAL_CI_ARTIFACT_ROOT: /data2/cse12310817/ci-server/ci-artifacts
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Trigger Jenkins job and stream logs
        shell: bash
        env:
          JENKINS_USERNAME: ${{ secrets.JENKINS_USERNAME }}
          JENKINS_API_TOKEN: ${{ secrets.JENKINS_API_TOKEN }}
        run: |
          chmod +x scripts/watch-jenkins-build.sh
          ./scripts/watch-jenkins-build.sh \
            --base-url "$JENKINS_BASE_URL" \
            --job-name "$JENKINS_JOB_NAME" \
            --username "$JENKINS_USERNAME" \
            --api-token "$JENKINS_API_TOKEN" \
            --log-dir '.ci-logs' \
            --metadata-path '.ci-logs/latest-run.json'

      - name: Resolve artifact paths
        if: always()
        id: paths
        shell: bash
        run: |
          METADATA_PATH=".ci-logs/latest-run.json"
          if [ ! -f "$METADATA_PATH" ]; then
            echo "build_number=" >> "$GITHUB_OUTPUT"
            echo "artifact_dir=" >> "$GITHUB_OUTPUT"
            exit 0
          fi

          BUILD_NUMBER=$(python3 -c "import json; print(json.load(open('$METADATA_PATH'))['buildNumber'])")
          ARTIFACT_DIR="${LOCAL_CI_ARTIFACT_ROOT}/build-${BUILD_NUMBER}"

          echo "build_number=${BUILD_NUMBER}" >> "$GITHUB_OUTPUT"
          echo "artifact_dir=${ARTIFACT_DIR}" >> "$GITHUB_OUTPUT"

      - name: Upload Jenkins logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: ci-logs-run-${{ github.run_number }}
          path: .ci-logs
          if-no-files-found: warn

      - name: Upload Jenkins artifacts
        if: always() && steps.paths.outputs.artifact_dir != ''
        uses: actions/upload-artifact@v4
        with:
          name: ci-artifacts-build-${{ steps.paths.outputs.build_number }}
          path: ${{ steps.paths.outputs.artifact_dir }}
          if-no-files-found: warn
```

---

## Step 9. Configure Jenkins

### 9.1 Set environment variables in Jenkins

Go to **Manage Jenkins → System** or configure in the job, and set:

| Variable | Example value |
|---|---|
| `HARMONY_SDK_HOME` | `~/ci-server/harmony-commandline-tools/sdk` |
| `HARMONY_NODE` | `~/ci-server/harmony-commandline-tools/tools/node/bin/node` |
| `HARMONY_OHPM` | `~/ci-server/harmony-commandline-tools/tools/ohpm/bin/ohpm` |
| `HARMONY_HVIGOR` | `~/ci-server/harmony-commandline-tools/tools/hvigor/bin/hvigorw.js` |
| `LOCAL_ARTIFACT_ROOT` | `~/ci-server/ci-artifacts` |

**Note**: Jenkins does not expand `~` in environment variables. All paths in Jenkins config **must use the absolute path** `/data2/cse12310817/ci-server/...`.

**Adjust the actual paths based on what you found in Step 3.**

### 9.2 Create or update the Jenkins job

1. Create a Pipeline job named `travelpin-ci`
2. Set "Pipeline script from SCM"
3. Point to the Git repository
4. Set Script Path to `Jenkinsfile.linux` (or `Jenkinsfile` if you renamed it)
5. Set the branch to `test/ci-cd`

### 9.3 Add credentials

In **Manage Jenkins → Credentials**, add:

- `JENKINS_USERNAME` / `JENKINS_API_TOKEN` as a Username/Password credential (for GitHub Actions to trigger Jenkins)

Also add these as GitHub repository secrets so the workflow can use them.

---

## Step 10. Validate End-to-End

Run through this checklist in order:

### 10.1 Verify Jenkins can build independently

```bash
# Manually trigger the Jenkins build via curl
curl -X POST http://127.0.0.1:8081/job/travelpin-ci/build \
  --user "<username>:<api_token>"
```

Check in Jenkins UI that the build completes and `~/ci-server/ci-artifacts/build-N/` contains the expected files.

### 10.1b Verify the reference clone

```bash
ls ~/ci-server/team-project-26spring-26s-7/
# Should contain: Jenkinsfile, frontend/, scripts/, .github/, references/documents/
ls ~/ci-server/team-project-26spring-26s-7/references/documents/
# Should contain the migration guide documents
```

### 10.2 Verify GitHub Actions end-to-end

```bash
# From a local clone, push to test/ci-cd
git push origin test/ci-cd
```

Watch the GitHub Actions run. Verify:

- [ ] The Linux runner picks up the job
- [ ] `watch-jenkins-build.sh` triggers Jenkins successfully
- [ ] Logs stream to the GitHub Actions console
- [ ] Build finishes with SUCCESS
- [ ] `.ci-logs` artifact is uploaded
- [ ] `ci-artifacts-build-N` artifact is uploaded and contains `.hap` + reports

### 10.3 Verify artifacts

```bash
# Download the artifact from GitHub Actions and inspect
ls ~/ci-server/ci-artifacts/build-N/
# Should contain: logs/ reports/ packages/ metrics/ meta/
ls ~/ci-server/ci-artifacts/build-N/packages/
# Should contain: *.hap
```

---

## Troubleshooting

### Jenkins build fails at "Install Dependencies"

- Check `HARMONY_OHPM` path is correct and executable
- Try running `ohpm install` manually in the `frontend/` directory
- Check `ohpm` can reach HarmonyOS package registries from the server

### Jenkins build fails at "Compile"

- Check `HARMONY_NODE` and `HARMONY_HVIGOR` paths
- Run `build.sh` manually to see the actual error
- Verify `HARMONY_SDK_HOME` points to a valid SDK with the right API version

### GitHub Actions cannot trigger Jenkins

- Verify `127.0.0.1:8081` is reachable from the runner (same machine)
- If runner and Jenkins are on different machines, update `JENKINS_BASE_URL`
- Check that GitHub secrets `JENKINS_USERNAME` and `JENKINS_API_TOKEN` are set

### `watch-jenkins-build.sh` fails on JSON parsing

- Ensure `python3` is installed: `sudo apt install -y python3`
- Or install `jq` and replace `python3 -c` calls with `jq -r`

### Test reports not found

- The test output path `frontend/entry/.test/default/...` may differ on Linux
- Run a test build manually and check the actual output paths
- Adjust the `dir()` blocks in the Test stage accordingly

---

## What NOT to Do

- Do not delete the Windows files (`build.ps1`, `watch-jenkins-build.ps1`) yet — keep them for reference until Linux CI is verified
- Do not change the `Jenkinsfile` filename until the team confirms Windows CI is decommissioned
- Do not merge the workflow change to `main` until `test/ci-cd` passes completely
- Do not hardcode server-specific paths in the repository files — use environment variables

---

## File Checklist

After completing all steps, the repository should have these new/modified files:

| File | Action |
|---|---|
| `frontend/build.sh` | **NEW** — Linux build entrypoint |
| `scripts/watch-jenkins-build.sh` | **NEW** — Linux Jenkins bridge |
| `Jenkinsfile.linux` | **NEW** — Linux-compatible Jenkinsfile |
| `.github/workflows/jenkinsfile-check.yml` | **MODIFIED** — Linux runner labels + bash |
| `Jenkinsfile` | **KEEP** — Windows version, untouched |
| `frontend/build.ps1` | **KEEP** — Windows version, untouched |
| `scripts/watch-jenkins-build.ps1` | **KEEP** — Windows version, untouched |

---

## Handoff Complete

When all validation steps pass, report back with:

1. The actual absolute paths for `HARMONY_*` environment variables
2. Whether `ohpm install` and `assembleHap` succeeded on Linux
3. Any deviations from this document (different tool paths, missing packages, etc.)
4. A green GitHub Actions run link

**Before starting**, read the Windows source files in the reference clone at `~/ci-server/team-project-26spring-26s-7/` to understand the exact logic you are migrating.
