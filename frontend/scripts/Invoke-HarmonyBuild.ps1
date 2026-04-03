param(
  [string]$Task = 'assembleApp',
  [string[]]$HvigorArgs = @()
)

$ErrorActionPreference = 'Stop'

function New-DirectoryIfMissing {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function New-JunctionIfMissing {
  param(
    [string]$Path,
    [string]$Target
  )

  if (Test-Path -LiteralPath $Path) {
    return
  }

  try {
    New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
  } catch {
    if (-not (Test-Path -LiteralPath $Path)) {
      throw
    }
  }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

$devecoRoot = 'D:\software\DevEco Studio'
$nodeHome = Join-Path $devecoRoot 'tools\node'
$nodeExe = Join-Path $nodeHome 'node.exe'
$hvigorJs = Join-Path $devecoRoot 'tools\hvigor\hvigor\bin\hvigor.js'
$hvigorToolRoot = Join-Path $devecoRoot 'tools\hvigor'
$sdkHome = Join-Path $devecoRoot 'sdk'
$toolNodeModules = Join-Path $projectRoot '.codex_tool_node_modules'
$toolOhosModules = Join-Path $toolNodeModules '@ohos'

$requiredPaths = @(
  $nodeExe,
  $hvigorJs,
  $sdkHome,
  (Join-Path $hvigorToolRoot 'hvigor'),
  (Join-Path $hvigorToolRoot 'hvigor-ohos-plugin')
)

foreach ($requiredPath in $requiredPaths) {
  if (-not (Test-Path -LiteralPath $requiredPath)) {
    throw "Missing DevEco dependency: $requiredPath"
  }
}

New-DirectoryIfMissing $toolOhosModules
New-JunctionIfMissing (Join-Path $toolOhosModules 'hvigor') (Join-Path $hvigorToolRoot 'hvigor')
New-JunctionIfMissing (Join-Path $toolOhosModules 'hvigor-ohos-plugin') (Join-Path $hvigorToolRoot 'hvigor-ohos-plugin')

$cacheDirs = @{
  HVIGOR_USER_HOME = (Join-Path $projectRoot '.codex_hvigor_home')
  USERPROFILE = (Join-Path $projectRoot '.codex_user')
  NPM_CONFIG_CACHE = (Join-Path $projectRoot '.codex_npm_cache')
  LOCALAPPDATA = (Join-Path $projectRoot '.codex_localapp')
  APPDATA = (Join-Path $projectRoot '.codex_appdata')
  TEMP = (Join-Path $projectRoot '.codex_tmp')
  TMP = (Join-Path $projectRoot '.codex_tmp')
  PNPM_HOME = (Join-Path $projectRoot '.codex_pnpm_home')
}

foreach ($dir in ($cacheDirs.Values | Select-Object -Unique)) {
  New-DirectoryIfMissing $dir
}

$env:NODE_HOME = $nodeHome
$env:DEVECO_SDK_HOME = $sdkHome
$env:NODE_PATH = $toolNodeModules

foreach ($pair in $cacheDirs.GetEnumerator()) {
  [System.Environment]::SetEnvironmentVariable($pair.Key, $pair.Value, 'Process')
}

$env:npm_config_cache = $cacheDirs['NPM_CONFIG_CACHE']
$env:PATH = "$nodeHome;$(Join-Path $devecoRoot 'tools\ohpm\bin');$(Join-Path $devecoRoot 'tools\hvigor\bin');$env:PATH"

$arguments = @($hvigorJs, $Task)
if (($HvigorArgs -notcontains '--daemon') -and ($HvigorArgs -notcontains '--no-daemon')) {
  $arguments += '--no-daemon'
}
$arguments += $HvigorArgs

Write-Host "Project root: $projectRoot"
Write-Host "Task: $Task $($HvigorArgs -join ' ')"
Write-Host "HVIGOR_USER_HOME: $($cacheDirs['HVIGOR_USER_HOME'])"
Write-Host "NODE_PATH: $toolNodeModules"

Set-Location -LiteralPath $projectRoot
& $nodeExe @arguments
exit $LASTEXITCODE
