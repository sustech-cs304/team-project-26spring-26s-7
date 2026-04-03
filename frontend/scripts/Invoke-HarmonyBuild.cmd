@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-HarmonyBuild.ps1" %*
exit /b %errorlevel%
