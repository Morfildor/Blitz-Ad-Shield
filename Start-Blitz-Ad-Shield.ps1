# Start Blitz Ad Shield, applying pending updates before the tray is opened.
# This bootstrap runs hidden through Launch-Blitz-Ad-Shield.vbs.
[CmdletBinding()]
param(
    [string]$BlitzPath = "$env:LOCALAPPDATA\Programs\Blitz\Blitz.exe"
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$logDir = Join-Path $env:LOCALAPPDATA 'BlitzAdShield\Logs'
[void][IO.Directory]::CreateDirectory($logDir)
$updateLog = Join-Path $logDir 'updater.log'
$powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

$updater = Join-Path $root 'Update-Blitz-Ad-Shield.ps1'
if (Test-Path -LiteralPath $updater -PathType Leaf) {
    try {
        # Failure or lack of internet never prevents the app from launching.
        & $updater -Mode Apply -InstallDir $root *>> $updateLog
    }
    catch {
        ("Update check skipped: " + $_.Exception.Message) | Out-File -LiteralPath $updateLog -Append
    }
}

$tray = Join-Path $root 'Blitz-Ad-Shield-Tray.ps1'
if (-not (Test-Path -LiteralPath $tray -PathType Leaf)) { exit 1 }
$arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -BlitzPath "{1}"' -f $tray, $BlitzPath
Start-Process -FilePath $powershell -ArgumentList $arguments -WindowStyle Hidden | Out-Null
