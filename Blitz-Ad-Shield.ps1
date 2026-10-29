# Blitz Ad Shield v0.3 — local, reversible, no installed-file modifications.
# Windows PowerShell 5.1+; no admin rights or dependencies required.
# This console-based worker also runs hidden under the tray controller.
param(
    [string]$BlitzPath = "$env:LOCALAPPDATA\Programs\Blitz\Blitz.exe",
    [int]$Port = 0,
    [switch]$NoCosmetic,
    [switch]$DebugLog,
    [switch]$InspectHosts
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Narrow ad network patterns, not Blitz.gg or Riot service endpoints.
$BlockedUrlPatterns = @(
    '*://aditude.io/*',
    '*://*.aditude.io/*',
    '*://prebid.cloud/*',
    '*://*.prebid.cloud/*',
    '*://*.doubleclick.net/*',
    '*://*.googlesyndication.com/*',
    '*://*.googletagservices.com/*',
    '*://*.primis.tech/*',
    '*://*.kueezrtb.com/*',
    '*://*.cpmstar.com/*',
    '*://cmp.inmobi.com/*',
    '*://*.inmobi-choice.io/*',
    '*://*.privacymanager.io/*',
    '*://dn0qt3r0xannq.cloudfront.net/*',
    '*://d3g98hgqjqzwq5.cloudfront.net/*',
    '*://*.amazon-adsystem.com/*',
    '*://*.adnxs.com/*'
)

# These are narrowly targeted ad-slot selectors seen in Blitz community projects.
# This script does not alter Blitz's app.asar, inject DLLs, or change game files.
$CosmeticScript = @'
(() => {
  if (window.__blitzAdShieldApplied) return;
  window.__blitzAdShieldApplied = true;
  const css = `
    [class*="🤑"],
    .ads-rail-marker,
    #display-desktop-anchor,
    .leaderboard-promo,
    .blitz3-promo,
    [data-primis-placement-id],
    #qc-cmp2-ui {
      display: none !important;
    }
    :root, main {
      --right-rail-width: 0px !important;
      --rail-gap: 0px !important;
    }
  `;
  const style = document.createElement('style');
  style.id = 'blitz-ad-shield-css';
  style.textContent = css;
  const apply = () => {
    if (document.documentElement && !style.isConnected) {
      document.documentElement.appendChild(style);
    }
  };
  new MutationObserver(apply).observe(document, {childList: true, subtree: true});
  apply();
})();
'@

$script:Socket = $null
$script:Sequence = 0
$script:Buffer = [byte[]]::new(65536)
$script:Cancel = [Threading.CancellationToken]::None
$script:CommandNames = @{}
$script:BlocksObserved = 0
$script:PagesAttached = 0
$script:HostsSeen = @{}

function Send-CdpCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [hashtable]$Params = @{},
        [string]$SessionId = ''
    )
    $script:Sequence++
    $id = $script:Sequence
    $payload = [ordered]@{ id = $id; method = $Method; params = $Params }
    if ($SessionId) { $payload['sessionId'] = $SessionId }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 8 -Compress))
    $script:CommandNames[[string]$id] = $Method
    $script:Socket.SendAsync(
        [ArraySegment[byte]]::new($bytes),
        [Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        $script:Cancel
    ).GetAwaiter().GetResult() | Out-Null
}

function Receive-CdpMessage {
    $stream = [IO.MemoryStream]::new()
    try {
        do {
            $result = $script:Socket.ReceiveAsync(
                [ArraySegment[byte]]::new($script:Buffer),
                $script:Cancel
            ).GetAwaiter().GetResult()
            if ($result.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) {
                return $null
            }
            $stream.Write($script:Buffer, 0, $result.Count)
        } while (-not $result.EndOfMessage)
        return [Text.Encoding]::UTF8.GetString($stream.ToArray())
    }
    finally { $stream.Dispose() }
}

function Find-FreeLoopbackPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally { $listener.Stop() }
}

Write-Host ''
Write-Host 'Blitz Ad Shield v0.3' -ForegroundColor Cyan
Write-Host 'Local Chromium request blocker + optional ad-slot hiding.'
Write-Host 'In console mode, leave this window running; press Ctrl+C to stop blocking.'
Write-Host ''

if (-not (Test-Path -LiteralPath $BlitzPath -PathType Leaf)) {
    throw "Blitz.exe was not found: $BlitzPath`nPass -BlitzPath 'C:\path\to\Blitz.exe' if installed elsewhere."
}

# Do not terminate Blitz, Riot, or any other running process.
if (Get-Process -Name Blitz -ErrorAction SilentlyContinue) {
    throw 'Blitz is already running. Fully exit Blitz from the system tray and try again. This tool never kills Blitz automatically.'
}

if ($Port -eq 0) { $Port = Find-FreeLoopbackPort }
if ($Port -lt 1024 -or $Port -gt 65535) { throw 'Port must be 1024-65535, or 0 for an automatic port.' }

$debugUrl = "http://127.0.0.1:$Port/json/version"
Write-Host "Launching Blitz with localhost-only debug port $Port ..."

$script:ConnectionPhase = 'launching Blitz'

function Format-ConnectionError {
    param([System.Exception]$Exception)
    $details = New-Object 'System.Collections.Generic.List[string]'
    $cursor = $Exception
    for ($depth = 0; $cursor -and $depth -lt 6; $depth++) {
        if ($cursor.Message) { [void]$details.Add($cursor.Message) }
        if ($cursor -is [Net.WebSockets.WebSocketException]) {
            [void]$details.Add("WebSocket code: $($cursor.WebSocketErrorCode)")
        }
        $cursor = $cursor.InnerException
    }
    return ($details | Select-Object -Unique) -join ' | '
}

try {
    # Launch Blitz just once. Reconnecting the blocker must never restart or terminate the app.
    $blitz = Start-Process -FilePath $BlitzPath -ArgumentList @(
        '--remote-debugging-address=127.0.0.1',
        "--remote-debugging-port=$Port"
    ) -PassThru

    $startupDeadline = (Get-Date).AddSeconds(35)
    $hasConnected = $false
    $failures = 0
    $maxFailures = 15

    while ($true) {
        # Blitz sometimes starts a new process during an update. Give the first
        # launch time to settle, but exit cleanly after a connected session closes.
        $running = @(Get-Process -Name Blitz -ErrorAction SilentlyContinue).Count -gt 0
        if (-not $running -and ($hasConnected -or (Get-Date) -gt $startupDeadline)) {
            Write-Host 'Blitz is closed. Disconnecting the blocker.'
            break
        }
        try {
            $script:ConnectionPhase = 'reading the local Chromium debug endpoint'
            $version = Invoke-RestMethod -Uri $debugUrl -TimeoutSec 2 -ErrorAction Stop
            if (-not $version.webSocketDebuggerUrl) {
                throw 'The debug endpoint did not return a browser WebSocket URL.'
            }
            $webSocketUri = [uri]$version.webSocketDebuggerUrl
            if ($webSocketUri.Scheme -ne 'ws' -or $webSocketUri.Host -notin @('127.0.0.1', 'localhost', '::1') -or $webSocketUri.Port -ne $Port) {
                throw 'The debug endpoint is not on the expected localhost port.'
            }

            $script:CommandNames.Clear()
            $script:Sequence = 0
            $script:PagesAttached = 0
            $script:Socket = [Net.WebSockets.ClientWebSocket]::new()
            $script:ConnectionPhase = 'opening the Chromium WebSocket'
            $script:Socket.ConnectAsync($webSocketUri, $script:Cancel).GetAwaiter().GetResult() | Out-Null
            $script:ConnectionPhase = 'enabling automatic target attachment'
            Send-CdpCommand -Method 'Target.setAutoAttach' -Params @{
                autoAttach = $true
                waitForDebuggerOnStart = $false
                flatten = $true
            }

            if ($hasConnected) {
                Write-Host 'Reconnected to Blitz. Blocking known advertising networks...' -ForegroundColor Green
            } else {
                Write-Host 'Connected. Blocking known advertising networks...' -ForegroundColor Green
            }
            $hasConnected = $true
            $failures = 0
            $script:ConnectionPhase = 'receiving Chromium messages'
    while ($script:Socket.State -eq [Net.WebSockets.WebSocketState]::Open) {
        $raw = Receive-CdpMessage
        if (-not $raw) { break }
        $message = $raw | ConvertFrom-Json

        if ($message.PSObject.Properties.Name -contains 'error') {
            $methodName = 'CDP command'
            $key = [string]$message.id
            if ($script:CommandNames.ContainsKey($key)) { $methodName = $script:CommandNames[$key] }
            Write-Warning "$methodName failed: $($message.error.message)"
            continue
        }
        if ($message.PSObject.Properties.Name -contains 'id') {
            [void]$script:CommandNames.Remove([string]$message.id)
        }
        if (-not ($message.PSObject.Properties.Name -contains 'method')) { continue }

        if ($message.method -eq 'Target.attachedToTarget') {
            $target = $message.params.targetInfo
            $session = [string]$message.params.sessionId
            if ($target.type -notin @('page', 'iframe')) { continue }
            $script:PagesAttached++
            if ($DebugLog) { Write-Host "Attached to $($target.type): $($target.url)" }
            Send-CdpCommand -Method 'Network.enable' -SessionId $session
            Send-CdpCommand -Method 'Network.setBlockedURLs' -Params @{ urls = $BlockedUrlPatterns } -SessionId $session
            if (-not $NoCosmetic -and $target.type -eq 'page') {
                Send-CdpCommand -Method 'Page.enable' -SessionId $session
                Send-CdpCommand -Method 'Page.addScriptToEvaluateOnNewDocument' -Params @{ source = $CosmeticScript } -SessionId $session
                Send-CdpCommand -Method 'Runtime.evaluate' -Params @{ expression = $CosmeticScript } -SessionId $session
            }
            if ($script:PagesAttached -eq 1) {
                Write-Host 'Blitz page attached. Ads should now be blocked; open a build page to check.' -ForegroundColor Green
            }
        }
        elseif ($InspectHosts -and $message.method -eq 'Network.requestWillBeSent') {
            try {
                $hostName = ([uri]$message.params.request.url).Host.ToLowerInvariant()
                if ($hostName -and -not $script:HostsSeen.ContainsKey($hostName)) {
                    $script:HostsSeen[$hostName] = $true
                    Write-Host "Network host: $hostName"
                }
            } catch { }
        }
        elseif ($message.method -eq 'Network.loadingFailed') {
            if ($message.params.errorText -like '*BLOCKED_BY_CLIENT*') {
                $script:BlocksObserved++
                if ($DebugLog) { Write-Host "Blocked request #$($script:BlocksObserved)" }
            }
        }
    }

            if (-not (Get-Process -Name Blitz -ErrorAction SilentlyContinue)) {
                Write-Host 'Blitz is closed. Disconnecting the blocker.'
                break
            }
            throw 'Chromium closed the WebSocket connection.'
        }
        catch {
            $failures++
            $reason = Format-ConnectionError -Exception $_.Exception
            $phase = $script:ConnectionPhase
            Write-Warning ("Connection attempt {0}/{1} failed during {2}: {3}" -f $failures, $maxFailures, $phase, $reason)
            if ($failures -ge $maxFailures) {
                throw ("Unable to keep the Chromium WebSocket connected after {0} attempts. Last failure during {1}: {2}" -f $maxFailures, $phase, $reason)
            }
            Write-Host 'Reconnecting to Blitz...'
        }
        finally {
            if ($null -ne $script:Socket) {
                try { $script:Socket.Dispose() } catch { }
                $script:Socket = $null
            }
        }
        # A short backoff handles temporary restarts without hammering the local endpoint.
        Start-Sleep -Milliseconds ([Math]::Min(2000, 400 * $failures))
    }
}
catch {
    Write-Host ("Error: {0}" -f (Format-ConnectionError -Exception $_.Exception)) -ForegroundColor Red
    exit 1
}
finally {
    if ($null -ne $script:Socket) {
        try { $script:Socket.Dispose() } catch { }
    }
    Write-Host "Disconnected. Observed blocked requests: $($script:BlocksObserved)."
    Write-Host 'Blitz was not modified. Restart Blitz normally to run without this tool.'
}
