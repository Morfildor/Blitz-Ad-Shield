# Blitz Ad Shield tray controller (Windows PowerShell 5.1; .NET Framework WinForms).
# Runs the existing Blitz-Ad-Shield.ps1 worker in a hidden child PowerShell process.
# No administrator privileges, installers, network services, or changes to Blitz files.
param(
    [string]$BlitzPath = "$env:LOCALAPPDATA\Programs\Blitz\Blitz.exe"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:workerScript = Join-Path $PSScriptRoot 'Blitz-Ad-Shield.ps1'
$script:iconFile = Join-Path $PSScriptRoot 'Blitz-Ad-Shield.ico'
$script:logDir = Join-Path $env:LOCALAPPDATA 'BlitzAdShield\Logs'
$script:worker = $null
$script:stdoutPath = $null
$script:stderrPath = $null
$script:startedAt = [DateTime]::MinValue
$script:connected = $false
$script:stoppedByUser = $false
$script:statusMessage = 'Starting...'
$script:shuttingDown = $false

# Only one controller per logged-in Windows session.
$createdNew = $false
$script:mutex = [System.Threading.Mutex]::new($true, 'Local\BlitzAdShield_Tray_02', [ref]$createdNew)
if (-not $createdNew) {
    $script:mutex.Dispose()
    exit 0
}

$script:context = New-Object System.Windows.Forms.ApplicationContext
$script:tray = New-Object System.Windows.Forms.NotifyIcon
$script:menu = New-Object System.Windows.Forms.ContextMenuStrip
$script:statusItem = [System.Windows.Forms.ToolStripMenuItem]::new('Status: starting...')
$script:statusItem.Enabled = $false
$script:startItem = [System.Windows.Forms.ToolStripMenuItem]::new('Start protection')
$script:stopItem = [System.Windows.Forms.ToolStripMenuItem]::new('Stop protection')
$script:logsItem = [System.Windows.Forms.ToolStripMenuItem]::new('Open logs folder')
$script:exitItem = [System.Windows.Forms.ToolStripMenuItem]::new('Exit Shield')
$script:timer = New-Object System.Windows.Forms.Timer
$script:timer.Interval = 1300

$script:icon = $null
if (Test-Path -LiteralPath $script:iconFile -PathType Leaf) {
    $script:icon = [System.Drawing.Icon]::new($script:iconFile)
    $script:tray.Icon = $script:icon
} else {
    $script:tray.Icon = [System.Drawing.SystemIcons]::Information
}

[void]$script:menu.Items.Add($script:statusItem)
[void]$script:menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$script:menu.Items.Add($script:startItem)
[void]$script:menu.Items.Add($script:stopItem)
[void]$script:menu.Items.Add($script:logsItem)
[void]$script:menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$script:menu.Items.Add($script:exitItem)
$script:tray.ContextMenuStrip = $script:menu
$script:tray.Text = 'Blitz Ad Shield'
$script:tray.Visible = $true

function Set-TrayStatus {
    param([string]$Message)
    $script:statusMessage = $Message
    $script:statusItem.Text = "Status: $Message"
    $text = "Blitz Ad Shield - $Message"
    # Windows shell tooltip max length is 63 characters.
    $script:tray.Text = $text.Substring(0, [Math]::Min($text.Length, 63))
}

function Show-ShieldNotice {
    param([string]$Message, [bool]$Warning = $false)
    $kind = [System.Windows.Forms.ToolTipIcon]::Info
    if ($Warning) { $kind = [System.Windows.Forms.ToolTipIcon]::Warning }
    $script:tray.ShowBalloonTip(4000, 'Blitz Ad Shield', $Message, $kind)
}

function Worker-IsRunning {
    if ($null -eq $script:worker) { return $false }
    try { return (-not $script:worker.HasExited) }
    catch { return $false }
}

function Get-LatestWorkerMessage {
    $entries = @()
    foreach ($path in @($script:stderrPath, $script:stdoutPath)) {
        if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try {
            $entries += @(Get-Content -LiteralPath $path -Tail 12 -ErrorAction Stop)
        } catch { }
    }
    $lines = @($entries | Where-Object { $_ -and $_.Trim() })
    if ($lines.Count -eq 0) { return '' }
    # Prefer a useful error line over PowerShell diagnostic formatting.
    $errors = @($lines | Where-Object { $_ -match '(?i)error:|exception:|not found|already running|did not expose|cannot find|failed:' })
    if ($errors.Count -gt 0) { return [string]$errors[-1] }
    return [string]$lines[-1]
}

function Start-Shield {
    if (Worker-IsRunning) { return }
    if (-not (Test-Path -LiteralPath $script:workerScript -PathType Leaf)) {
        Set-TrayStatus 'Worker script missing'
        Show-ShieldNotice 'Blitz-Ad-Shield.ps1 is missing from the application folder.' $true
        return
    }
    if (-not (Test-Path -LiteralPath $BlitzPath -PathType Leaf)) {
        Set-TrayStatus 'Blitz.exe not found'
        Show-ShieldNotice 'Blitz.exe was not found at its default location. See README for custom path.' $true
        return
    }
    if (Get-Process -Name Blitz -ErrorAction SilentlyContinue) {
        Set-TrayStatus 'Close Blitz before starting'
        Show-ShieldNotice 'Fully exit Blitz (including its system tray icon), then select Start protection.' $true
        return
    }

    [void][IO.Directory]::CreateDirectory($script:logDir)
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
    $script:stdoutPath = Join-Path $script:logDir "shield-$stamp.log"
    $script:stderrPath = Join-Path $script:logDir "shield-$stamp-errors.log"
    $script:startedAt = Get-Date
    $script:connected = $false
    $script:stoppedByUser = $false
    Set-TrayStatus 'Starting Blitz...'
    $script:startItem.Enabled = $false
    $script:stopItem.Enabled = $true
    try {
        $shell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        # Powershell's Start-Process will redirect both streams into local log files.
        $args = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -BlitzPath "{1}"' -f $script:workerScript, $BlitzPath
        $script:worker = Start-Process -FilePath $shell -ArgumentList $args -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $script:stdoutPath -RedirectStandardError $script:stderrPath
    }
    catch {
        Set-TrayStatus 'Could not start'
        $script:startItem.Enabled = $true
        $script:stopItem.Enabled = $false
        Show-ShieldNotice "Could not launch the blocker: $($_.Exception.Message)" $true
    }
}

function Stop-Shield {
    if (Worker-IsRunning) {
        $script:stoppedByUser = $true
        try { $script:worker.Kill() } catch { }
        try { $script:worker.WaitForExit(1800) | Out-Null } catch { }
    }
    Set-TrayStatus 'Stopped - restart Blitz to resume'
    $script:startItem.Enabled = $true
    $script:stopItem.Enabled = $false
}

$script:startItem.Add_Click({ Start-Shield })
$script:stopItem.Add_Click({
    Stop-Shield
    Show-ShieldNotice 'Blocking stopped. Fully quit Blitz to close its debugging port; restart Blitz through Shield to resume.'
})
$script:logsItem.Add_Click({
    [void][IO.Directory]::CreateDirectory($script:logDir)
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $script:logDir) | Out-Null
})
$script:tray.Add_DoubleClick({ Show-ShieldNotice "Current status: $script:statusMessage" })
$script:exitItem.Add_Click({
    $script:shuttingDown = $true
    Stop-Shield
    $script:context.ExitThread()
})

$script:timer.Add_Tick({
    if ($null -eq $script:worker) { return }
    if (Worker-IsRunning) {
        if ($script:stdoutPath -and (Test-Path -LiteralPath $script:stdoutPath)) {
            try {
                $tail = @(Get-Content -LiteralPath $script:stdoutPath -Tail 12 -ErrorAction Stop)
                # Use the latest connection event. Older messages may still be in the tail.
                $events = @($tail | Where-Object { $_ -match '(?i)^(Reconnecting to Blitz|Connected\.|Reconnected to Blitz)' })
                if ($events.Count -gt 0) {
                    $latest = [string]$events[-1]
                    if ($latest -match '^Reconnecting to Blitz') {
                        Set-TrayStatus 'Reconnecting to Blitz...'
                    } else {
                        $script:connected = $true
                        Set-TrayStatus 'Protection connected'
                    }
                }
            } catch { }
        }
    }
    else {
        $exitCode = 1
        try { $exitCode = $script:worker.ExitCode } catch { }
        try { $script:worker.Dispose() } catch { }
        $script:worker = $null
        $script:startItem.Enabled = $true
        $script:stopItem.Enabled = $false
        if (-not $script:shuttingDown -and -not $script:stoppedByUser) {
            if ($exitCode -eq 0 -and $script:connected) {
                Set-TrayStatus 'Disconnected (Blitz closed?)'
                Show-ShieldNotice 'Protection disconnected. Start protection again after fully closing Blitz.'
            } else {
                Set-TrayStatus 'Protection stopped with an error'
                $detail = Get-LatestWorkerMessage
                if ($detail.Length -gt 180) { $detail = $detail.Substring(0,180) }
                if (-not $detail) { $detail = 'Open the logs folder for details.' }
                Show-ShieldNotice "The blocker stopped: $detail" $true
            }
        }
    }
})

try {
    $script:timer.Start()
    Start-Shield
    [System.Windows.Forms.Application]::Run($script:context)
}
finally {
    $script:timer.Stop()
    if (Worker-IsRunning) { Stop-Shield }
    if ($null -ne $script:worker) { $script:worker.Dispose() }
    $script:timer.Dispose()
    $script:tray.Visible = $false
    $script:tray.Dispose()
    $script:menu.Dispose()
    if ($null -ne $script:icon) { $script:icon.Dispose() }
    $script:context.Dispose()
    if ($createdNew) {
        try { $script:mutex.ReleaseMutex() } catch { }
    }
    $script:mutex.Dispose()
}
