# Offline tests for the worker's message handling. No Blitz, network, or admin rights needed.
# Run with Windows PowerShell 5.1:  powershell -NoProfile -File tests\Test-Worker.ps1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Blitz-Ad-Shield.ps1')

# Record commands instead of sending them over a socket.
$script:Sent = New-Object 'System.Collections.Generic.List[object]'
function Send-CdpCommand {
    param([string]$Method, [hashtable]$Params = @{}, [string]$SessionId = '')
    $script:Sent.Add([pscustomobject]@{ Method = $Method; Session = $SessionId; Params = $Params })
    if ($script:ThrowOn -and $Method -eq $script:ThrowOn) { throw 'simulated send failure' }
}
$script:ThrowOn = ''

$script:Failed = 0
function Assert-That([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "  ok   $Name" }
    else { Write-Host "  FAIL $Name" -ForegroundColor Red; $script:Failed++ }
}
function Reset-Run { $script:Sent.Clear(); $script:PagesAttached = 0; $script:BlocksObserved = 0; $script:CommandNames.Clear() }
function Get-Methods { @($script:Sent | ForEach-Object { $_.Method }) }
function New-Attach([string]$Type, [bool]$Waiting, [string]$Session = 'S1') {
    $w = if ($Waiting) { 'true' } else { 'false' }
    '{"method":"Target.attachedToTarget","params":{"sessionId":"' + $Session + '","targetInfo":{"targetId":"T","type":"' + $Type + '","url":"https://example.test/"},"waitingForDebugger":' + $w + '}}'
}

Write-Host 'Paused page'
Reset-Run
Invoke-CdpMessage -Raw (New-Attach 'page' $true)
$m = Get-Methods
Assert-That ($m[0] -eq 'Target.setAutoAttach') 'enables nested auto-attach first'
Assert-That ($m -contains 'Network.setBlockedURLs') 'sets blocked URLs'
Assert-That ($m -contains 'Page.addScriptToEvaluateOnNewDocument') 'registers the cosmetic script'
Assert-That ($m -notcontains 'Runtime.evaluate') 'does not evaluate on a paused page'
Assert-That ($m[-1] -eq 'Runtime.runIfWaitingForDebugger') 'resumes the page last'
Assert-That ($script:Sent[0].Params['waitForDebuggerOnStart'] -eq $true) 'children are paused until configured'

Write-Host 'Already-loaded page'
Reset-Run
Invoke-CdpMessage -Raw (New-Attach 'page' $false)
$m = Get-Methods
Assert-That ($m -contains 'Runtime.evaluate') 'evaluates the cosmetic script immediately'
Assert-That ($m -notcontains 'Runtime.runIfWaitingForDebugger') 'does not resume what is not paused'

Write-Host 'Iframe and other targets'
Reset-Run
Invoke-CdpMessage -Raw (New-Attach 'iframe' $true)
$m = Get-Methods
Assert-That ($m -contains 'Network.setBlockedURLs') 'blocks inside iframes'
Assert-That ($m -notcontains 'Page.addScriptToEvaluateOnNewDocument') 'no cosmetic script in iframes'
Assert-That ($m[-1] -eq 'Runtime.runIfWaitingForDebugger') 'iframe is resumed'
Reset-Run
Invoke-CdpMessage -Raw (New-Attach 'service_worker' $true)
Assert-That (((Get-Methods) -join ',') -eq 'Runtime.runIfWaitingForDebugger') 'paused workers are resumed and otherwise untouched'

Write-Host 'Failure still releases a paused target'
Reset-Run
$script:ThrowOn = 'Network.enable'
try { Invoke-CdpMessage -Raw (New-Attach 'page' $true) } catch { }
$script:ThrowOn = ''
Assert-That ((Get-Methods)[-1] -eq 'Runtime.runIfWaitingForDebugger') 'resume is sent even if setup throws'

Write-Host 'Cosmetic opt-out'
Reset-Run
$NoCosmetic = [switch]$true
Invoke-CdpMessage -Raw (New-Attach 'page' $false)
Assert-That ((Get-Methods) -notcontains 'Page.addScriptToEvaluateOnNewDocument') '-NoCosmetic skips the script'
$NoCosmetic = [switch]$false

Write-Host 'Legacy attach'
Reset-Run
$LegacyAttach = [switch]$true
Invoke-CdpMessage -Raw (New-Attach 'page' $false)
Assert-That ($script:Sent[0].Params['waitForDebuggerOnStart'] -eq $false) '-LegacyAttach does not pause children'
$LegacyAttach = [switch]$false

Write-Host 'Noise and counters'
Reset-Run
Invoke-CdpMessage -Raw '{"method":"Network.requestWillBeSent","params":{"requestId":"1","request":{"url":"https://a.test/x"}},"sessionId":"S1"}'
Assert-That ($script:Sent.Count -eq 0) 'ordinary network events cause no commands'
Invoke-CdpMessage -Raw '{"method":"Network.loadingFailed","params":{"requestId":"1","errorText":"net::ERR_BLOCKED_BY_CLIENT","blockedReason":"inspector"},"sessionId":"S1"}'
Invoke-CdpMessage -Raw '{"method":"Network.loadingFailed","params":{"requestId":"2","errorText":"net::ERR_ABORTED"},"sessionId":"S1"}'
Assert-That ($script:BlocksObserved -eq 1) 'only blocked requests are counted'

Write-Host 'Responses'
Reset-Run
$script:CommandNames['7'] = 'Network.enable'
$script:CommandNames['8'] = 'Page.enable'
Invoke-CdpMessage -Raw '{"id":7,"result":{},"sessionId":"S1"}'
Assert-That (-not $script:CommandNames.ContainsKey('7')) 'success responses are pruned'
$warnings = @()
Invoke-CdpMessage -Raw '{"id":8,"error":{"code":-32601,"message":"nope"},"sessionId":"S1"}' -WarningVariable warnings -WarningAction SilentlyContinue
Assert-That (-not $script:CommandNames.ContainsKey('8')) 'error responses are pruned'
Assert-That (@($warnings).Count -eq 1 -and "$($warnings[0])" -like 'Page.enable failed: nope') 'errors name the failing command'

Write-Host 'Rules'
$bad = @($BlockedUrlPatterns | Where-Object { $_ -cnotmatch '^\*://(\*\.)?[a-z0-9-]+(\.[a-z0-9-]+)+/\*$' })
Assert-That ($bad.Count -eq 0) 'block patterns are well-formed host wildcards'
Assert-That (@($BlockedUrlPatterns | Select-Object -Unique).Count -eq $BlockedUrlPatterns.Count) 'no duplicate patterns'
Assert-That (@($BlockedUrlPatterns | Where-Object { $_ -match 'blitz\.gg|riotgames|riotcdn|leagueoflegends' }).Count -eq 0) 'never targets Blitz or Riot endpoints'
Assert-That (($CosmeticScript -cmatch '[^\x00-\x7F]') -eq $false) 'cosmetic script is ASCII-only'

if (Get-Command node -ErrorAction SilentlyContinue) {
    $js = Join-Path ([IO.Path]::GetTempPath()) "shield-$([guid]::NewGuid().ToString('N')).js"
    try {
        [IO.File]::WriteAllText($js, $CosmeticScript)
        & node --check $js 2>$null
        Assert-That ($LASTEXITCODE -eq 0) 'cosmetic script is valid JavaScript'
    }
    finally { Remove-Item -LiteralPath $js -Force -ErrorAction SilentlyContinue }
}

if ($script:Failed -gt 0) { Write-Host "`n$($script:Failed) check(s) failed." -ForegroundColor Red; exit 1 }
Write-Host "`nAll checks passed." -ForegroundColor Green
