# Build script for ItsMapPin HarmonyOS Project
# Usage: powershell -ExecutionPolicy Bypass -File build.ps1 [--sync] [-p product=default] [other hvigor args]

# Set DEVECO_SDK_HOME environment variable (fixes "Invalid value of DEVECO_SDK_HOME" error)
$env:DEVECO_SDK_HOME = "C:\Apps\DevEco Studio\sdk"

# Change to script directory
Set-Location -Path $PSScriptRoot

# Run hvigor with all arguments passed to this script
& "C:\Apps\DevEco Studio\tools\node\node.exe" "C:\Apps\DevEco Studio\tools\hvigor\bin\hvigorw.js" $args
