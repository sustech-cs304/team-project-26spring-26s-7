param(
    [string]$ConfigPath = '.local-ci/local-jenkins-hook.json'
)

$ErrorActionPreference = 'Stop'

function Write-HookStatus {
    param([string]$Message)
    Write-Host "[local-ci] $Message"
}

function Resolve-RepoPath {
    param(
        [string]$RepoRoot,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $RepoRoot $Path
}

$repoRoot = (& git rev-parse --show-toplevel).Trim()
if (-not $repoRoot) {
    throw 'Failed to resolve repository root.'
}

$resolvedConfigPath = Resolve-RepoPath -RepoRoot $repoRoot -Path $ConfigPath
if (-not (Test-Path $resolvedConfigPath)) {
    Write-HookStatus "Config not found at $resolvedConfigPath. Local Jenkins check is disabled."
    exit 0
}

$config = Get-Content $resolvedConfigPath -Raw | ConvertFrom-Json
if (-not $config.enabled) {
    Write-HookStatus 'Local Jenkins check is disabled by config.'
    exit 0
}

if ([string]::IsNullOrWhiteSpace($config.jenkinsBaseUrl) -or [string]::IsNullOrWhiteSpace($config.jobName)) {
    throw "Config file '$resolvedConfigPath' is missing jenkinsBaseUrl or jobName."
}

$username = $null
$apiToken = $null

if (-not [string]::IsNullOrWhiteSpace($config.usernameEnvVar)) {
    $username = [Environment]::GetEnvironmentVariable([string]$config.usernameEnvVar)
}
if (-not [string]::IsNullOrWhiteSpace($config.apiTokenEnvVar)) {
    $apiToken = [Environment]::GetEnvironmentVariable([string]$config.apiTokenEnvVar)
}

if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($apiToken)) {
    throw "Missing Jenkins credentials in environment variables '$($config.usernameEnvVar)' and '$($config.apiTokenEnvVar)'."
}

$logDir = if ([string]::IsNullOrWhiteSpace($config.logDir)) { '.ci-logs' } else { [string]$config.logDir }
$metadataPath = if ([string]::IsNullOrWhiteSpace($config.metadataPath)) { '.ci-logs/latest-local-run.json' } else { [string]$config.metadataPath }

$currentBranch = (& git branch --show-current 2>$null).Trim()
$upstreamBranch = (& git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null).Trim()

if ($currentBranch -and $upstreamBranch) {
    $localHead = (& git rev-parse HEAD).Trim()
    $remoteHead = (& git rev-parse $upstreamBranch 2>$null).Trim()

    if ($remoteHead -and $localHead -ne $remoteHead) {
        Write-HookStatus "HEAD is ahead of $upstreamBranch."
        Write-HookStatus 'Push first if you want Jenkins to validate this exact commit.'
    }
}

Write-HookStatus "Triggering Jenkins job '$($config.jobName)' at $($config.jenkinsBaseUrl)."

& powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $repoRoot 'scripts/watch-jenkins-build.ps1') `
    -BaseUrl ([string]$config.jenkinsBaseUrl) `
    -JobName ([string]$config.jobName) `
    -Username $username `
    -ApiToken $apiToken `
    -LogDir $logDir `
    -MetadataPath $metadataPath

$hookStatus = $LASTEXITCODE
if ($hookStatus -ne 0) {
    Write-HookStatus "Jenkins build watcher exited with status $hookStatus."
}

exit 0
