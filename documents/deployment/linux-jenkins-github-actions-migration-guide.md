# TravelPin Linux CI Migration Guide

## Goal

This guide describes **Scheme B**:

- GitHub Actions runner runs on a **Linux server**
- Jenkins also runs on the **same Linux server** or another Linux server
- The Linux Jenkins job becomes the real build executor
- GitHub Actions remains the outer trigger, log collector, and artifact uploader

This is **not** a simple runner replacement. The current repository is still Windows-oriented in several places, so a Linux migration requires both:

1. Linux server environment setup
2. Repository pipeline refactoring

---

## Current Architecture

Current CI chain:

1. `git push` triggers [`.github/workflows/jenkinsfile-check.yml`](../../.github/workflows/jenkinsfile-check.yml)
2. GitHub Actions runs on a Windows self-hosted runner
3. The workflow calls [`scripts/watch-jenkins-build.ps1`](../../scripts/watch-jenkins-build.ps1)
4. That script triggers Jenkins job `travelpin-ci`
5. Jenkins executes [`Jenkinsfile`](../../Jenkinsfile)
6. `Jenkinsfile` calls [`frontend/build.ps1`](../../frontend/build.ps1)
7. Artifacts are written into `ci-artifacts/build-<BUILD_NUMBER>`
8. GitHub Actions uploads `.ci-logs` and the matching `ci-artifacts` directory

The current bottleneck is that steps 5 and 6 are Windows-specific.

---

## Migration Decision

To complete Scheme B, the team must migrate **all three layers**:

1. **GitHub Actions layer**
2. **Jenkins execution layer**
3. **HarmonyOS command-line build layer**

If only the GitHub runner is moved to Linux but Jenkins remains Windows-based, that is not Scheme B.

---

## Official References

The migration should follow these official references:

- GitHub self-hosted runner as a Linux service:  
  https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/configuring-the-self-hosted-runner-application-as-a-service?platform=linux
- Jenkins installation on Linux:  
  https://www.jenkins.io/doc/book/installing/linux/
- Huawei DevEco Studio archive with **Linux command line tools** (`commandline-tools-linux-*.zip`):  
  https://developer.huawei.com/consumer/cn/deveco-studio/archive/

Important note:

- The Huawei archive page clearly provides **Linux command line tools for HarmonyOS**, including `sdkmgr`, `codelinter`, and `ohpm`.
- This is the main official basis for Linux-side build tooling.
- This guide assumes the command line tools are the Linux-supported path, not the existing Windows desktop DevEco layout.

---

## What Must Change

### 1. Files that must be refactored

These repository files currently block Linux migration:

- [`Jenkinsfile`](../../Jenkinsfile)
- [`frontend/build.ps1`](../../frontend/build.ps1)
- [`.github/workflows/jenkinsfile-check.yml`](../../.github/workflows/jenkinsfile-check.yml)
- [`scripts/watch-jenkins-build.ps1`](../../scripts/watch-jenkins-build.ps1)

### 2. Windows-specific assumptions that must be removed

The current pipeline still depends on:

- `powershell` / `powershell.exe`
- `bat` steps in Jenkins
- Windows drive paths like `C:\\Apps\\...`
- backslash-separated paths
- `rmdir /s /q`
- a Windows DevEco installation layout

These must be replaced with Linux-compatible behavior.

---

## Target Architecture

Recommended target chain:

1. `git push` to GitHub
2. GitHub Actions runs on a Linux self-hosted runner
3. Workflow triggers Linux Jenkins over HTTP
4. Linux Jenkins executes a Linux-compatible `Jenkinsfile`
5. The Linux `Jenkinsfile` runs HarmonyOS command line tools
6. Jenkins writes logs and artifacts to a Linux artifact directory
7. GitHub Actions uploads those logs and artifacts

Recommended Linux-side directories:

- Jenkins home: `/var/lib/jenkins`
- CI workspace: Jenkins default workspace
- Build artifact root: `/srv/travelpin-ci-artifacts`
- GitHub runner directory: `/opt/actions-runner`
- HarmonyOS command line tools: `/opt/harmony-commandline-tools`
- Project checkout path: managed by Jenkins or runner, not hardcoded in the repo

---

## Server Setup Checklist

### Step 1. Prepare the Linux server

Minimum practical recommendations:

- Ubuntu LTS or another mainstream Linux distribution
- 4 GB RAM minimum
- 20 GB free disk minimum
- Stable outbound access to GitHub and HarmonyOS package/tooling endpoints

### Step 2. Install Java for Jenkins

Jenkins official docs require Java 21 or later.

Example on Ubuntu:

```bash
sudo apt update
sudo apt install -y fontconfig openjdk-21-jre
java -version
```

### Step 3. Install Jenkins

Use the Jenkins Linux installation guide for your distribution.

Ubuntu example:

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
sudo systemctl status jenkins
```

If port `8080` is occupied, move Jenkins to `8081` to preserve the current project contract.

### Step 4. Install GitHub self-hosted runner on Linux

Register the runner in the GitHub repository, then install it as a service.

Typical sequence:

```bash
mkdir -p /opt/actions-runner
cd /opt/actions-runner
# download runner package from GitHub
# extract it
./config.sh --url https://github.com/sustech-cs304/team-project-26spring-26s-7 --token <registration-token>
sudo ./svc.sh install
sudo ./svc.sh start
```

Use labels such as:

- `self-hosted`
- `linux`
- `travelpin`

### Step 5. Install HarmonyOS command line tools

Download the Linux package from Huawei's DevEco archive page:

- `commandline-tools-linux-*.zip`

Expected tools from Huawei's archive description:

- `sdkmgr`
- `codelinter`
- `ohpm`

Install them into a stable path, for example:

```bash
sudo mkdir -p /opt/harmony-commandline-tools
sudo unzip commandline-tools-linux-*.zip -d /opt/harmony-commandline-tools
```

Then make their binaries visible to Jenkins, either by:

- adding them to the Jenkins service environment, or
- exporting them in pipeline shell steps

### Step 6. Install Node if required by `hvigor`

The current Windows build uses Node to execute the build wrapper. The Linux replacement will likely still need Node available.

Install a stable LTS version and verify:

```bash
node -v
npm -v
```

### Step 7. Prepare artifact directories

Example:

```bash
sudo mkdir -p /srv/travelpin-ci-artifacts
sudo chown -R jenkins:jenkins /srv/travelpin-ci-artifacts
```

---

## Repository Refactoring Plan

### Phase 1. Replace `frontend/build.ps1`

Current file:

- [`frontend/build.ps1`](../../frontend/build.ps1)

Current problem:

- hardcoded Windows paths
- PowerShell-only
- assumes Windows DevEco layout

Target:

- add a Linux-compatible build entrypoint, for example `frontend/build.sh`
- keep Windows `build.ps1` temporarily if dual-platform support is needed

Recommended behavior of `build.sh`:

1. resolve tool paths from environment variables
2. fail fast if required tools are missing
3. call the Linux-side HarmonyOS build command

Suggested interface:

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${HARMONY_NODE:?HARMONY_NODE is required}"
: "${HARMONY_HVIGOR:?HARMONY_HVIGOR is required}"

cd "$(dirname "$0")"
"$HARMONY_NODE" "$HARMONY_HVIGOR" "$@"
```

This keeps the current pattern but removes Windows hardcoding.

### Phase 2. Refactor `Jenkinsfile`

Current file:

- [`Jenkinsfile`](../../Jenkinsfile)

Current Linux blockers:

- `bat` blocks
- `powershell` blocks
- Windows path literals
- Windows deletion commands

Required replacements:

- `bat` -> `sh`
- `powershell` -> `sh` or `pwsh`
- `C:\\...` -> environment variables
- `rmdir /s /q` -> `rm -rf`
- backslash paths -> slash paths

Recommended Jenkins environment variables for Linux:

- `HARMONY_SDK_HOME`
- `HARMONY_NODE`
- `HARMONY_OHPM`
- `HARMONY_HVIGOR`
- `LOCAL_ARTIFACT_ROOT`

Recommended Linux artifact root:

- `/srv/travelpin-ci-artifacts`

### Phase 3. Refactor `watch-jenkins-build.ps1`

Current file:

- [`scripts/watch-jenkins-build.ps1`](../../scripts/watch-jenkins-build.ps1)

Current Linux blocker:

- it is PowerShell-based

There are two acceptable paths:

1. Keep PowerShell and install `pwsh` on Linux
2. Replace the script with a shell or Python implementation

Recommended choice:

- replace it with a portable shell or Python bridge

Reason:

- the bridge only does HTTP trigger + polling + log capture
- it does not need Windows-specific features
- shell/Python is simpler on Linux CI hosts

### Phase 4. Refactor GitHub Actions workflow

Current file:

- [`.github/workflows/jenkinsfile-check.yml`](../../.github/workflows/jenkinsfile-check.yml)

Required changes:

- `runs-on` must switch to Linux labels
- shell should switch to `bash` unless `pwsh` is intentionally installed
- artifact root environment value must use Linux path syntax
- Jenkins base URL must point to the Linux Jenkins host, not `127.0.0.1`, unless runner and Jenkins are on the same machine

Example direction:

```yaml
runs-on:
  - self-hosted
  - linux
  - travelpin
```

---

## Jenkins Job Migration Checklist

Create a new Linux Jenkins job or convert the existing `travelpin-ci` job to run on Linux.

Required checks:

1. Jenkins can `checkout scm`
2. `ohpm install` works on Linux
3. compile command succeeds on Linux
4. test command succeeds on Linux
5. `.hap` artifact is generated
6. `ci-artifacts/build-<BUILD_NUMBER>` is created
7. reports and metrics are preserved

Recommended Jenkins plugins:

- Pipeline
- Git
- Credentials Binding
- Workspace Cleanup

Optional:

- JUnit
- Warnings NG

---

## Migration Sequence

Use this order to reduce risk:

### Stage A. Prepare Linux infrastructure only

1. Install Jenkins
2. Install GitHub runner
3. Install HarmonyOS command line tools
4. Verify Java, Node, and `ohpm`

### Stage B. Make the project dual-platform temporarily

1. Keep current Windows flow working
2. Add Linux build entrypoint
3. Add Linux-compatible Jenkinsfile version or parameterized logic
4. Test the Jenkins job locally on Linux first

### Stage C. Switch GitHub Actions outer flow

1. Change workflow runner labels
2. Change the bridge script or shell
3. Push to a test branch
4. Verify artifact upload

### Stage D. Promote to main branch

1. change workflow trigger to `main`
2. keep screenshots/logs for the report
3. document final pipeline in the team report

---

## Risks and Constraints

### Risk 1. HarmonyOS Linux CLI behavior may differ from Windows DevEco

The current project was implemented against a Windows desktop toolchain. Linux command line tools are available, but the exact build command and environment layout may differ from the current `build.ps1` assumptions.

Mitigation:

- do not rewrite the whole pipeline at once
- first prove a minimal Linux compile command

### Risk 2. Jenkins and runner on different hosts break `127.0.0.1`

If runner and Jenkins are split across machines, `127.0.0.1` becomes wrong.

Mitigation:

- use a real host name or server IP

### Risk 3. Path assumptions in artifact upload

Current workflow computes artifact paths assuming a fixed local directory root.

Mitigation:

- move artifact root into a configurable environment variable on Linux

### Risk 4. Test paths may differ

The current test report collection in `Jenkinsfile` assumes specific paths under `frontend/entry/.test/...`.

Mitigation:

- verify actual Linux-side test outputs before finalizing the archive logic

---

## Definition of Done

Scheme B is complete only when all of the following are true:

1. A Linux self-hosted GitHub runner receives the workflow job
2. A Linux Jenkins job is triggered successfully
3. Jenkins compiles the ArkTS project on Linux
4. Jenkins runs tests on Linux
5. Jenkins packages a runnable artifact such as `.hap`
6. GitHub Actions uploads logs and artifacts successfully
7. A push to the target branch shows a green GitHub Actions run with downloadable artifacts

---

## Recommended Deliverables for the Team Report

Include the following in `final-report-teamID.md`:

1. pipeline architecture diagram
2. links to:
   - [`.github/workflows/jenkinsfile-check.yml`](../../.github/workflows/jenkinsfile-check.yml)
   - [`Jenkinsfile`](../../Jenkinsfile)
   - Linux migration guide
3. screenshots of:
   - GitHub Actions successful run
   - Jenkins successful Linux build
   - downloadable artifacts
4. a short note that the Linux migration required replacing Windows-specific pipeline logic

---

## Practical Recommendation

For this repository, the safest approach is:

1. first build a **minimal Linux compile proof**
2. then migrate Jenkins pipeline steps
3. only then switch the GitHub Actions runner permanently

Do **not** switch the production CI path to Linux before proving that the HarmonyOS command line tools can compile this project end-to-end on that server.
