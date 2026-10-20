@echo off
rem Maintainer-only: publishes the prepared project to public GitHub after confirmation.
cd /d "%~dp0.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Publish-To-GitHub.ps1"
echo.
pause
