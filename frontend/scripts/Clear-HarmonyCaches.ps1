param()

$ErrorActionPreference = 'Stop'

function Assert-UnderRoot {
  param(
    [string]$Root,
    [string]$Path
  )

  $resolved = (Resolve-Path -LiteralPath $Path).Path
  if (-not $resolved.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to delete outside frontend root: $resolved"
  }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$frontendRoot = Split-Path -Parent $scriptDir

$targets = Get-ChildItem -LiteralPath $frontendRoot -Force |
  Where-Object {
    $_.PSIsContainer -and (
      $_.Name -like '.codex*' -or $_.Name -eq '.hvigor'
    )
  } |
  Select-Object -ExpandProperty FullName

if (-not $targets) {
  Write-Host 'No local Harmony caches found.'
  exit 0
}

foreach ($target in $targets) {
  Assert-UnderRoot -Root $frontendRoot -Path $target
}

$failed = @()
foreach ($target in $targets) {
  try {
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
    Write-Host "Removed: $target"
  } catch {
    $failed += $target
    Write-Warning "Could not fully remove: $target"
  }
}

if ($failed.Count -gt 0) {
  Write-Warning 'Some cache directories were left partially in place. Close any process that may still be using them and rerun this script.'
  $failed | ForEach-Object { Write-Host "Remaining: $_" }
  exit 1
}

Write-Host 'Local Harmony caches cleared.'
