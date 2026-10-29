# Blitz Ad Shield updater. Windows PowerShell 5.1.
# Uses the project-owned HTTPS manifest and SHA-256 checksum.
# Stage mode downloads updates without touching a running session.
[CmdletBinding()]
param(
    [ValidateSet('Apply','Stage')][string]$Mode = 'Apply',
    [string]$InstallDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:SourceBase = 'https://raw.githubusercontent.com/Morfildor/Blitz-Ad-Shield/main/dist'
$script:ManifestUrl = "$($script:SourceBase)/latest.json"
$script:UpdateDir = Join-Path $env:LOCALAPPDATA 'BlitzAdShield\Updater'
$script:PendingMetadata = Join-Path $script:UpdateDir 'pending.json'
$script:Files = @(
    'Blitz-Ad-Shield.ps1',
    'Blitz-Ad-Shield-Tray.ps1',
    'Blitz-Ad-Shield.ico',
    'Launch-Blitz-Ad-Shield.vbs',
    'Run-Blitz-Ad-Shield.cmd',
    'Run-Console-Diagnostics.cmd',
    'Start-Blitz-Ad-Shield.ps1',
    'Update-Blitz-Ad-Shield.ps1',
    'VERSION',
    'README.md',
    'LICENSE'
)

function Get-InstalledVersion {
    $path = Join-Path $InstallDir 'VERSION'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [version]'0.0.0' }
    $raw = (Get-Content -LiteralPath $path -Raw).Trim()
    if ($raw -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid local VERSION: $raw" }
    return [version]$raw
}

function Confirm-Manifest {
    param($Manifest)
    if ($null -eq $Manifest -or [int]$Manifest.schema -ne 1) { throw 'Invalid update manifest schema.' }
    $v = [string]$Manifest.version
    if ($v -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid manifest version.' }
    $expectedUrl = "$($script:SourceBase)/Blitz-Ad-Shield-Tray-v$v.zip"
    if ([string]$Manifest.url -cne $expectedUrl) { throw 'The manifest contains an unexpected download URL.' }
    if ([string]$Manifest.sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Invalid SHA-256 in update manifest.' }
    $size = [long]$Manifest.size
    if ($size -lt 1000 -or $size -gt 5242880) { throw 'Unexpected update package size.' }
    return [version]$v
}

function Confirm-PackageHash {
    param([string]$Path, $Manifest)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Update ZIP missing.' }
    $length = (Get-Item -LiteralPath $Path).Length
    if ($length -ne [long]$Manifest.size) { throw 'Update size does not match manifest.' }
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($hash -ine [string]$Manifest.sha256) { throw 'Update SHA-256 mismatch. Nothing was installed.' }
}

function Test-ZipContents {
    param([string]$Path, [string]$Version)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $totalBytes = [long]0
        foreach ($entry in $archive.Entries) {
            if (-not $entry.FullName.StartsWith('Blitz-Ad-Shield/', [StringComparison]::Ordinal)) {
                throw 'Unexpected path in update archive.'
            }
            $name = $entry.FullName.Substring('Blitz-Ad-Shield/'.Length)
            if ($name -cnotin $script:Files -or -not $names.Add($name)) {
                throw 'Unexpected or duplicate file in update archive.'
            }
            $totalBytes += $entry.Length
            if ($totalBytes -gt 5242880) { throw 'Update archive exceeds extraction size limit.' }
        }
        if ($names.Count -ne $script:Files.Count) { throw 'The update is missing required application files.' }
        return $true
    }
    finally { $archive.Dispose() }
}

function Read-Pending {
    if (-not (Test-Path -LiteralPath $script:PendingMetadata -PathType Leaf)) { return $null }
    try {
        $data = Get-Content -LiteralPath $script:PendingMetadata -Raw | ConvertFrom-Json
        $v = Confirm-Manifest -Manifest $data
        $zip = Join-Path $script:UpdateDir "pending-$v.zip"
        Confirm-PackageHash -Path $zip -Manifest $data
        [void](Test-ZipContents -Path $zip -Version ([string]$v))
        return $data
    }
    catch {
        Write-Warning "Discarding invalid pending update: $($_.Exception.Message)"
        Remove-Item -LiteralPath $script:PendingMetadata -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Save-Pending {
    param($Manifest)
    $version = Confirm-Manifest -Manifest $Manifest
    $target = Join-Path $script:UpdateDir "pending-$version.zip"
    $temporary = Join-Path $script:UpdateDir "download-$([guid]::NewGuid().ToString('N')).tmp"
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Manifest.url -OutFile $temporary -TimeoutSec 25 -ErrorAction Stop
        Confirm-PackageHash -Path $temporary -Manifest $Manifest
        [void](Test-ZipContents -Path $temporary -Version ([string]$version))
        Move-Item -LiteralPath $temporary -Destination $target -Force
        $Manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:PendingMetadata -Encoding UTF8
        Write-Output "Downloaded update v$version. It will be installed when Blitz is closed."
    }
    finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Install-Pending {
    param($Manifest)
    $version = Confirm-Manifest -Manifest $Manifest
    $zip = Join-Path $script:UpdateDir "pending-$version.zip"
    Confirm-PackageHash -Path $zip -Manifest $Manifest
    [void](Test-ZipContents -Path $zip -Version ([string]$version))
    if (Get-Process -Name Blitz -ErrorAction SilentlyContinue) {
        Write-Output "Blitz is running. Update v$version is ready for next launch."
        return
    }

    $unpack = Join-Path $script:UpdateDir "unpack-$([guid]::NewGuid().ToString('N'))"
    $backup = Join-Path $script:UpdateDir "backup-$((Get-Date).ToString('yyyyMMdd-HHmmss'))-$([guid]::NewGuid().ToString('N').Substring(0,6))"
    [void][IO.Directory]::CreateDirectory($unpack)
    [void][IO.Directory]::CreateDirectory($backup)

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Substring('Blitz-Ad-Shield/'.Length)
            $destination = Join-Path $unpack $name
            $inStream = $entry.Open()
            $outStream = [IO.File]::Create($destination)
            try { $inStream.CopyTo($outStream) }
            finally { $outStream.Dispose(); $inStream.Dispose() }
        }
    }
    finally { $archive.Dispose() }

    $newVersion = (Get-Content -LiteralPath (Join-Path $unpack 'VERSION') -Raw).Trim()
    if ($newVersion -cne [string]$version) { throw 'Package VERSION does not match manifest.' }

    # Save every original file before writing the first replacement.
    foreach ($name in $script:Files) {
        $existing = Join-Path $InstallDir $name
        if (Test-Path -LiteralPath $existing -PathType Leaf) {
            Copy-Item -LiteralPath $existing -Destination (Join-Path $backup $name) -Force
        }
    }

    $installed = New-Object 'System.Collections.Generic.List[string]'
    try {
        foreach ($name in $script:Files) {
            $existing = Join-Path $InstallDir $name
            $prepared = Join-Path $unpack $name
            $tmp = "$existing.new-$([guid]::NewGuid().ToString('N'))"
            Copy-Item -LiteralPath $prepared -Destination $tmp
            try { Move-Item -LiteralPath $tmp -Destination $existing -Force }
            finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
            [void]$installed.Add($name)
        }
        Remove-Item -LiteralPath $script:PendingMetadata -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Write-Output "Installed Blitz Ad Shield v$version. Previous files saved in $backup"
    }
    catch {
        foreach ($name in $installed) {
            $original = Join-Path $backup $name
            $existing = Join-Path $InstallDir $name
            if (Test-Path -LiteralPath $original -PathType Leaf) {
                Copy-Item -LiteralPath $original -Destination $existing -Force
            } else {
                Remove-Item -LiteralPath $existing -Force -ErrorAction SilentlyContinue
            }
        }
        throw
    }
    finally { Remove-Item -LiteralPath $unpack -Recurse -Force -ErrorAction SilentlyContinue }
}

$lock = $null
$ownsLock = $false
try {
    [void][IO.Directory]::CreateDirectory($script:UpdateDir)
    $created = $false
    $lock = [Threading.Mutex]::new($false, 'Local\BlitzAdShieldUpdater_v1', [ref]$created)
    try { $ownsLock = $lock.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsLock = $true }
    if (-not $ownsLock) { Write-Output 'Another update check is already running.'; exit 0 }

    $installedVersion = Get-InstalledVersion
    $pending = Read-Pending

    if ($Mode -eq 'Apply' -and $null -ne $pending) {
        $pendingVersion = Confirm-Manifest -Manifest $pending
        if ($pendingVersion -gt $installedVersion -and -not (Get-Process -Name Blitz -ErrorAction SilentlyContinue)) {
            Install-Pending -Manifest $pending
            $installedVersion = Get-InstalledVersion
        }
    }

    try {
        $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $manifest = Invoke-RestMethod -Uri "$($script:ManifestUrl)?t=$cacheBust" -TimeoutSec 8 -ErrorAction Stop
        $remoteVersion = Confirm-Manifest -Manifest $manifest
        if ($remoteVersion -gt $installedVersion) {
            if ($null -eq $pending -or (Confirm-Manifest -Manifest $pending) -ne $remoteVersion) {
                Save-Pending -Manifest $manifest
            }
            if ($Mode -eq 'Apply' -and -not (Get-Process -Name Blitz -ErrorAction SilentlyContinue)) {
                Install-Pending -Manifest $manifest
            }
        } else {
            Write-Output "Blitz Ad Shield is up to date (v$installedVersion)."
        }
    }
    catch {
        # An unavailable network must never stop Blitz from starting.
        Write-Warning "Update check skipped: $($_.Exception.Message)"
    }
}
catch {
    Write-Warning "Updater could not finish: $($_.Exception.Message)"
}
finally {
    if ($null -ne $lock) {
        if ($ownsLock) { try { $lock.ReleaseMutex() } catch { } }
        $lock.Dispose()
    }
}
