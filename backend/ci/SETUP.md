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
