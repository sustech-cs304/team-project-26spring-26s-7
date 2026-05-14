param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = (& git rev-parse --show-toplevel).Trim()
if (-not $repoRoot) {
    throw 'Failed to resolve repository root.'
}

$hooksDir = Join-Path $repoRoot '.git/hooks'
$hookPath = Join-Path $hooksDir 'post-commit'
$hookBody = @'
#!/bin/bash
set -u

REPO_ROOT="$(git rev-parse --show-toplevel)"

powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$REPO_ROOT/scripts/invoke-local-jenkins-post-commit.ps1"

exit 0
'@

function Normalize-HookText {
    param([string]$Text)

    if ($null -eq $Text) {
        return ''
    }

    return ($Text -replace "`r`n", "`n").TrimEnd("`n")
}

if ((Test-Path $hookPath) -and -not $Force) {
    $currentContent = Get-Content $hookPath -Raw
    if ((Normalize-HookText $currentContent) -eq (Normalize-HookText $hookBody)) {
        Write-Host '[local-ci] post-commit hook is already up to date.'
        exit 0
    }

    throw "Hook already exists at '$hookPath'. Re-run with -Force to overwrite it."
}

New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null
Set-Content -Path $hookPath -Value $hookBody -NoNewline
Write-Host "[local-ci] Installed post-commit hook at $hookPath"
