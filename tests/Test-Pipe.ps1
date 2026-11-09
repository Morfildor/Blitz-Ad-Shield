# Offline tests for the private pipe transport. A stand-in child process plays Blitz.
# Run with Windows PowerShell 5.1:  powershell -NoProfile -File tests\Test-Pipe.ps1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Blitz-Ad-Shield.ps1')
Initialize-PipeType

$script:Failed = 0
function Assert-That([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "  ok   $Name" }
    else { Write-Host "  FAIL $Name" -ForegroundColor Red; $script:Failed++ }
}

$shell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$work = Join-Path ([IO.Path]::GetTempPath()) ("shield-pipe-" + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)

# Runs a child script that receives the two handle values as its arguments.
function Start-StandIn([string]$Body) {
    $path = Join-Path $work ([guid]::NewGuid().ToString('N') + '.ps1')
    $header = '$ErrorActionPreference = "Stop"; $R = [long]$args[0]; $W = [long]$args[1]; ' +
        '$in = [IO.FileStream]::new([Microsoft.Win32.SafeHandles.SafeFileHandle]::new([IntPtr]$R, $true), "Read", 1, $false); ' +
        '$out = [IO.FileStream]::new([Microsoft.Win32.SafeHandles.SafeFileHandle]::new([IntPtr]$W, $true), "Write", 1, $false); ' +
        'function Send-Raw([string]$s) { $b = [Text.Encoding]::UTF8.GetBytes($s); $out.Write($b, 0, $b.Length); $out.Flush() }; '
    Set-Content -LiteralPath $path -Value ($header + $Body) -Encoding ASCII
    return [CdpPipe]::Launch($shell, ('-NoProfile -ExecutionPolicy Bypass -File "{0}" {{READ}} {{WRITE}}' -f $path))
}
function Read-All($link, [int]$TimeoutMs = 15000) {
    $got = @(); $m = $null
    while ($link.TryReceive($TimeoutMs, [ref]$m)) { $got += $m }
    return , $got
}

try {
    Write-Host 'Round trip and framing'
    $link = Start-StandIn @'
$sb = New-Object Collections.Generic.List[byte]
while (($b = $in.ReadByte()) -gt 0) { $sb.Add([byte]$b) }
$cmd = [Text.Encoding]::UTF8.GetString($sb.ToArray())
Send-Raw ('{"echo":' + ($cmd | ConvertTo-Json -Compress) + '}'); Send-Raw "`0"
Send-Raw '{"a":1}'; Send-Raw "`0"; Send-Raw '{"b":2}'; Send-Raw "`0"
Send-Raw '{"split":'; Start-Sleep -Milliseconds 300; Send-Raw '"whole"}'; Send-Raw "`0"
'@
    $link.Send('{"id":1,"method":"hello"}')
    $got = Read-All $link
    Assert-That ($got.Count -eq 4) "receives every message (got $($got.Count))"
    Assert-That (($got.Count -ge 1) -and $got[0] -eq '{"echo":"{\"id\":1,\"method\":\"hello\"}"}') 'child received our command intact'
    Assert-That (($got.Count -ge 3) -and $got[1] -eq '{"a":1}' -and $got[2] -eq '{"b":2}') 'back-to-back messages are split correctly'
    Assert-That (($got.Count -ge 4) -and $got[3] -eq '{"split":"whole"}') 'a message split across writes is reassembled'
    Assert-That ($link.WaitForChildExit(15000)) 'child exit is detected'
    Assert-That ($link.Closed) 'pipe reports closed after the child exits'
    $link.Dispose()

    Write-Host 'Non-ASCII payload'
    $link = Start-StandIn @'
$sb = New-Object Collections.Generic.List[byte]
while (($b = $in.ReadByte()) -gt 0) { $sb.Add([byte]$b) }
$bytes = $sb.ToArray(); $out.Write($bytes, 0, $bytes.Length); Send-Raw "`0"
'@
    $text = '{"t":"' + [char]0x00E9 + [char]0x4E2D + [char]0xD83E + [char]0xDD11 + '"}'
    $link.Send($text)
    $got = Read-All $link
    Assert-That (($got.Count -eq 1) -and $got[0] -ceq $text) 'UTF-8 survives the round trip'
    $link.Dispose()

    Write-Host 'Closing'
    $link = Start-StandIn 'Start-Sleep -Seconds 30'
    Assert-That (-not $link.Closed) 'open while the child lives'
    $link.Dispose()
    Start-Sleep -Milliseconds 200
    $gone = $true
    try { $link.Send('{}') ; $gone = $false } catch { }
    Assert-That $gone 'sending after Dispose fails instead of hanging'
    $leftover = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like "*$work*" })
    $leftover | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    Write-Host 'Launch failure'
    $threw = $false
    try { [void][CdpPipe]::Launch((Join-Path $work 'missing.exe'), '{READ} {WRITE}') } catch { $threw = $true }
    Assert-That $threw 'a missing executable throws (so the worker can fall back)'

    Write-Host 'Session logic'
    $script:Sent = New-Object 'System.Collections.Generic.List[object]'
    Assert-That ($null -eq $script:Pipe) 'no pipe is held between sessions'
    $fallback = Start-PipeSession -BlitzPath (Join-Path $work 'missing.exe') 3>$null
    Assert-That ($fallback -eq $false) 'Start-PipeSession reports failure so the port fallback can run'
    Assert-That ($null -eq $script:Pipe) 'failed start leaves no pipe behind'
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:Failed -gt 0) { Write-Host "`n$($script:Failed) check(s) failed." -ForegroundColor Red; exit 1 }
Write-Host "`nAll checks passed." -ForegroundColor Green
