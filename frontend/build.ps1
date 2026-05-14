# Build script for TravelPin HarmonyOS Project
# Usage: powershell -ExecutionPolicy Bypass -File build.ps1 [--sync] [-p product=default] [other hvigor args]

# Set DEVECO_SDK_HOME environment variable (fixes "Invalid value of DEVECO_SDK_HOME" error)
$env:DEVECO_SDK_HOME = "C:\Apps\DevEco Studio\sdk"

# Change to script directory
Set-Location -Path $PSScriptRoot

$hvigorArgs = @($args)
$hasDaemonFlag = $hvigorArgs -contains '--daemon' -or $hvigorArgs -contains '--no-daemon'
$isCiBuild = [string]::IsNullOrWhiteSpace($env:JENKINS_URL) -eq $false -or
    [string]::IsNullOrWhiteSpace($env:JOB_NAME) -eq $false -or
    $env:CI -eq 'true'

# Hvigor daemon is flaky in Jenkins on this machine; default CI runs to no-daemon
# unless the caller explicitly requests daemon behavior.
if ($isCiBuild -and -not $hasDaemonFlag) {
    $hvigorArgs = @('--no-daemon') + $hvigorArgs
}

# Run hvigor with all arguments passed to this script
& "C:\Apps\DevEco Studio\tools\node\node.exe" "C:\Apps\DevEco Studio\tools\hvigor\bin\hvigorw.js" $hvigorArgs
