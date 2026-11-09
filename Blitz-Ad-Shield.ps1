# Blitz Ad Shield worker - local, reversible, no installed-file modifications.
# Windows PowerShell 5.1+; no admin rights or dependencies required.
# This console-based worker also runs hidden under the tray controller.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.
param(
    [string]$BlitzPath = "$env:LOCALAPPDATA\Programs\Blitz\Blitz.exe",
    [int]$Port = 0,
    [switch]$NoCosmetic,
    [switch]$DebugLog,
    [switch]$InspectHosts,
    # Kill switch: attach to pages without pausing them first (pre-0.6 behaviour).
    [switch]$LegacyAttach,
    # Use a local TCP debugging port instead of the private pipe (the pre-0.7 behaviour).
    [switch]$UsePort
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Rules. Narrow ad-network patterns only, never Blitz.gg or Riot endpoints.
# ---------------------------------------------------------------------------
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

# Narrowly targeted ad-slot selectors. Nothing here touches app.asar, injects
# DLLs, or changes game files. The style tag is mounted on <html> and only that
# element's children are observed, so page re-renders cost nothing.
$CosmeticScript = @'
(() => {
  if (window.__blitzAdShieldApplied) return;
  window.__blitzAdShieldApplied = true;
  const style = document.createElement('style');
  style.id = 'blitz-ad-shield-css';
  style.textContent = `
    [class*="\u{1F911}"],
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
  const watcher = new MutationObserver(() => mount());
  function mount() {
    const root = document.documentElement;
    if (!root) return;
    if (!style.isConnected) root.appendChild(style);
    watcher.observe(root, { childList: true });
  }
  watcher.observe(document, { childList: true });
  mount();
})();
'@

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
$script:Socket = $null
$script:Pipe = $null
$script:Sequence = 0
$script:Buffer = [byte[]]::new(65536)
$script:Cancel = [Threading.CancellationToken]::None
$script:CommandNames = @{}
$script:BlocksObserved = 0
$script:PagesAttached = 0
$script:HostsSeen = @{}
$script:ConnectionPhase = 'starting'
$script:Utf8 = [Text.UTF8Encoding]::new($false)

# ---------------------------------------------------------------------------
# CDP transport
# ---------------------------------------------------------------------------
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
    $json = $payload | ConvertTo-Json -Depth 8 -Compress
    # Bounded: responses prune entries, and a clear guards against odd servers.
    if ($script:CommandNames.Count -gt 2048) { $script:CommandNames.Clear() }
    $script:CommandNames[[string]$id] = $Method
    $script:ConnectionPhase = "sending $Method"
    if ($null -ne $script:Pipe) {
        $script:Pipe.Send($json)
        return
    }
    $bytes = $script:Utf8.GetBytes($json)
    $script:Socket.SendAsync(
        [ArraySegment[byte]]::new($bytes),
        [Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        $script:Cancel
    ).GetAwaiter().GetResult() | Out-Null
}

function Receive-CdpMessage {
    $script:ConnectionPhase = 'receiving Chromium messages'
    $result = $script:Socket.ReceiveAsync(
        [ArraySegment[byte]]::new($script:Buffer),
        $script:Cancel
    ).GetAwaiter().GetResult()
    if ($result.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) { return $null }

    # Most messages fit in one frame: decode straight from the shared buffer.
    if ($result.EndOfMessage) {
        return $script:Utf8.GetString($script:Buffer, 0, $result.Count)
    }

    $stream = [IO.MemoryStream]::new()
    try {
        $stream.Write($script:Buffer, 0, $result.Count)
        do {
            $result = $script:Socket.ReceiveAsync(
                [ArraySegment[byte]]::new($script:Buffer),
                $script:Cancel
            ).GetAwaiter().GetResult()
            if ($result.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) { return $null }
            $stream.Write($script:Buffer, 0, $result.Count)
        } while (-not $result.EndOfMessage)
        return $script:Utf8.GetString($stream.GetBuffer(), 0, [int]$stream.Length)
    }
    finally { $stream.Dispose() }
}

# ---------------------------------------------------------------------------
# Message handling
#
# Network.enable makes Chromium emit an event for every request and response.
# Parsing each one with ConvertFrom-Json is the dominant cost in PowerShell, so
# messages are classified from their first characters and only the few we act
# on are parsed. Blocked requests are counted from the raw text, with no parse.
# ---------------------------------------------------------------------------
function Test-MessageHead {
    param([string]$Raw, [string]$Needle)
    $window = [Math]::Min(160, $Raw.Length)
    return $Raw.IndexOf($Needle, 0, $window, [StringComparison]::Ordinal) -ge 0
}

function Initialize-CdpTarget {
    param($Message)
    $params = $Message.params
    $session = [string]$params.sessionId
    $type = [string]$params.targetInfo.type
    $waiting = $params.PSObject.Properties.Name -contains 'waitingForDebugger' -and [bool]$params.waitingForDebugger

    try {
        if ($type -in @('page', 'iframe')) {
            $script:PagesAttached++
            if ($DebugLog) { Write-Host "Attached to ${type}: $($params.targetInfo.url)" }

            # Cover frames nested inside this one, then apply rules before it can load.
            Send-CdpCommand -Method 'Target.setAutoAttach' -SessionId $session -Params @{
                autoAttach = $true
                waitForDebuggerOnStart = (-not $LegacyAttach)
                flatten = $true
            }
            Send-CdpCommand -Method 'Network.enable' -SessionId $session
            Send-CdpCommand -Method 'Network.setBlockedURLs' -Params @{ urls = $BlockedUrlPatterns } -SessionId $session
            if (-not $NoCosmetic -and $type -eq 'page') {
                Send-CdpCommand -Method 'Page.enable' -SessionId $session
                Send-CdpCommand -Method 'Page.addScriptToEvaluateOnNewDocument' -Params @{ source = $CosmeticScript } -SessionId $session
                # A page that was already loaded will not run the script above again.
                if (-not $waiting) {
                    Send-CdpCommand -Method 'Runtime.evaluate' -Params @{ expression = $CosmeticScript } -SessionId $session
                }
            }
            if ($script:PagesAttached -eq 1) {
                Write-Host 'Blitz page attached. Ads should now be blocked; open a build page to check.' -ForegroundColor Green
            }
        }
    }
    finally {
        # Every paused target must be released, including types we do not touch
        # (workers and so on), or that part of Blitz would hang until we disconnect.
        if ($waiting) {
            Send-CdpCommand -Method 'Runtime.runIfWaitingForDebugger' -SessionId $session
        }
    }
}

function Invoke-CdpMessage {
    param([Parameter(Mandatory = $true)][string]$Raw)

    # Command responses start with the id. Parse only the failures.
    if ($Raw.StartsWith('{"id":', [StringComparison]::Ordinal)) {
        $end = $Raw.IndexOfAny([char[]]@(',', '}'), 6)
        $key = $null
        if ($end -gt 6) { $key = $Raw.Substring(6, $end - 6) }
        if ($Raw.IndexOf('"error"', [StringComparison]::Ordinal) -ge 0) {
            $message = $Raw | ConvertFrom-Json
            if ($message.PSObject.Properties.Name -contains 'error') {
                $methodName = 'CDP command'
                if ($key -and $script:CommandNames.ContainsKey($key)) { $methodName = $script:CommandNames[$key] }
                Write-Warning "$methodName failed: $($message.error.message)"
            }
        }
        if ($key) { [void]$script:CommandNames.Remove($key) }
        return
    }

    if (Test-MessageHead $Raw '"Target.attachedToTarget"') {
        Initialize-CdpTarget -Message ($Raw | ConvertFrom-Json)
    }
    elseif (Test-MessageHead $Raw '"Network.loadingFailed"') {
        if ($Raw.IndexOf('ERR_BLOCKED_BY_CLIENT', [StringComparison]::Ordinal) -ge 0) {
            $script:BlocksObserved++
            if ($DebugLog) { Write-Host "Blocked request #$($script:BlocksObserved)" }
        }
    }
    elseif ($InspectHosts -and (Test-MessageHead $Raw '"Network.requestWillBeSent"')) {
        try {
            $message = $Raw | ConvertFrom-Json
            $hostName = ([uri]$message.params.request.url).Host.ToLowerInvariant()
            if ($hostName -and -not $script:HostsSeen.ContainsKey($hostName)) {
                $script:HostsSeen[$hostName] = $true
                Write-Host "Network host: $hostName"
            }
        } catch { }
    }
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Find-FreeLoopbackPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally { $listener.Stop() }
}

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

function Get-ShieldVersion {
    $path = Join-Path $PSScriptRoot 'VERSION'
    try { return (Get-Content -LiteralPath $path -Raw -ErrorAction Stop).Trim() }
    catch { return 'dev' }
}

function Connect-Blitz {
    param([uri]$WebSocketUri, [int]$Port)
    $script:CommandNames.Clear()
    $script:Sequence = 0
    $script:PagesAttached = 0
    $script:Socket = [Net.WebSockets.ClientWebSocket]::new()
    # Recent Chromium builds may reject a CDP WebSocket with no Origin.
    # Match the exact localhost-only origin enabled by our launch flag.
    $script:Socket.Options.SetRequestHeader('Origin', "http://127.0.0.1:$Port")
    $script:ConnectionPhase = 'opening the Chromium WebSocket'
    $script:Socket.ConnectAsync($WebSocketUri, $script:Cancel).GetAwaiter().GetResult() | Out-Null
    $script:ConnectionPhase = 'enabling automatic target attachment'
    Send-CdpCommand -Method 'Target.setAutoAttach' -Params @{
        autoAttach = $true
        waitForDebuggerOnStart = (-not $LegacyAttach)
        flatten = $true
    }
}

# ---------------------------------------------------------------------------
# Private pipe transport.
# Chromium can speak DevTools over a pair of anonymous pipes inherited by the
# child process, so no TCP port is ever opened. This type launches Blitz with
# exactly two inheritable handles and frames messages with a trailing NUL byte.
# Note: when the pipe closes, Electron asks Blitz to quit. Blitz answers by closing
# its window to the system tray and keeps running unfiltered, so ads return until
# it is restarted through Shield.
# ---------------------------------------------------------------------------
$PipeSource = @'
using System;
using System.Collections.Concurrent;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

public sealed class CdpPipe : IDisposable
{
    const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
    const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    const int HANDLE_FLAG_INHERIT = 1;
    static readonly IntPtr PROC_THREAD_ATTRIBUTE_HANDLE_LIST = (IntPtr)0x00020002;

    [StructLayout(LayoutKind.Sequential)]
    struct SECURITY_ATTRIBUTES { public int nLength; public IntPtr lpSecurityDescriptor; public int bInheritHandle; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO
    {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX; public int dwY; public int dwXSize; public int dwYSize;
        public int dwXCountChars; public int dwYCountChars; public int dwFillAttribute; public int dwFlags;
        public short wShowWindow; public short cbReserved2; public IntPtr lpReserved2;
        public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct STARTUPINFOEX { public STARTUPINFO StartupInfo; public IntPtr lpAttributeList; }

    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId; }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CreatePipe(out IntPtr hReadPipe, out IntPtr hWritePipe, ref SECURITY_ATTRIBUTES sa, int nSize);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetHandleInformation(IntPtr h, int mask, int flags);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previous, IntPtr returnSize);
    [DllImport("kernel32.dll")]
    static extern void DeleteProcThreadAttributeList(IntPtr list);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string app, StringBuilder commandLine, IntPtr procAttrs, IntPtr threadAttrs,
        bool inheritHandles, uint flags, IntPtr environment, string currentDirectory,
        ref STARTUPINFOEX startupInfo, out PROCESS_INFORMATION processInfo);

    readonly FileStream toChild;
    readonly FileStream fromChild;
    readonly Process child;
    readonly BlockingCollection<string> inbox = new BlockingCollection<string>();
    readonly object sendLock = new object();
    public int ProcessId { get; private set; }

    CdpPipe(FileStream toChild, FileStream fromChild, Process child, int pid)
    {
        this.toChild = toChild; this.fromChild = fromChild; this.child = child; ProcessId = pid;
        Thread reader = new Thread(ReadLoop);
        reader.IsBackground = true;
        reader.Start();
    }

    // argsTemplate may contain {READ} and {WRITE}: the handle values the child must use.
    // {READ} is where the child reads our commands; {WRITE} is where it writes replies.
    public static CdpPipe Launch(string exePath, string argsTemplate)
    {
        SECURITY_ATTRIBUTES sa = new SECURITY_ATTRIBUTES();
        sa.nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
        sa.bInheritHandle = 1;
        IntPtr cmdRead, cmdWrite, resRead, resWrite;
        if (!CreatePipe(out cmdRead, out cmdWrite, ref sa, 0)) throw new Win32Exception(Marshal.GetLastWin32Error());
        if (!CreatePipe(out resRead, out resWrite, ref sa, 0))
        {
            int error = Marshal.GetLastWin32Error();
            CloseHandle(cmdRead); CloseHandle(cmdWrite);
            throw new Win32Exception(error);
        }
        // Our own ends must never be inherited by the child.
        SetHandleInformation(cmdWrite, HANDLE_FLAG_INHERIT, 0);
        SetHandleInformation(resRead, HANDLE_FLAG_INHERIT, 0);

        IntPtr attrList = IntPtr.Zero;
        GCHandle pinned = default(GCHandle);
        bool launched = false;
        try
        {
            IntPtr size = IntPtr.Zero;
            InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
            attrList = Marshal.AllocHGlobal(size);
            if (!InitializeProcThreadAttributeList(attrList, 1, 0, ref size)) throw new Win32Exception(Marshal.GetLastWin32Error());
            // Only these two handles are inherited by the child; nothing else leaks.
            IntPtr[] inherit = new IntPtr[] { cmdRead, resWrite };
            pinned = GCHandle.Alloc(inherit, GCHandleType.Pinned);
            if (!UpdateProcThreadAttribute(attrList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                pinned.AddrOfPinnedObject(), (IntPtr)(IntPtr.Size * 2), IntPtr.Zero, IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error());

            STARTUPINFOEX si = new STARTUPINFOEX();
            si.StartupInfo.cb = Marshal.SizeOf(typeof(STARTUPINFOEX));
            si.lpAttributeList = attrList;

            string args = argsTemplate
                .Replace("{READ}", cmdRead.ToInt64().ToString())
                .Replace("{WRITE}", resWrite.ToInt64().ToString());
            StringBuilder commandLine = new StringBuilder("\"" + exePath + "\" " + args);
            PROCESS_INFORMATION pi;
            if (!CreateProcessW(null, commandLine, IntPtr.Zero, IntPtr.Zero, true,
                EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT, IntPtr.Zero,
                Path.GetDirectoryName(exePath), ref si, out pi))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            launched = true;
            Process child = null;
            try { child = Process.GetProcessById(pi.dwProcessId); } catch (Exception) { }
            CloseHandle(pi.hThread);
            CloseHandle(pi.hProcess);
            // Close the child's ends here, or we would never see the pipe close.
            CloseHandle(cmdRead);
            CloseHandle(resWrite);
            return new CdpPipe(
                new FileStream(new SafeFileHandle(cmdWrite, true), FileAccess.Write, 4096, false),
                new FileStream(new SafeFileHandle(resRead, true), FileAccess.Read, 4096, false),
                child, pi.dwProcessId);
        }
        finally
        {
            if (pinned.IsAllocated) pinned.Free();
            if (attrList != IntPtr.Zero) { DeleteProcThreadAttributeList(attrList); Marshal.FreeHGlobal(attrList); }
            if (!launched) { CloseHandle(cmdRead); CloseHandle(cmdWrite); CloseHandle(resRead); CloseHandle(resWrite); }
        }
    }

    void ReadLoop()
    {
        byte[] buffer = new byte[16384];
        MemoryStream pending = new MemoryStream();
        try
        {
            while (true)
            {
                int n = fromChild.Read(buffer, 0, buffer.Length);
                if (n <= 0) break;
                for (int i = 0; i < n; i++)
                {
                    if (buffer[i] == 0)
                    {
                        inbox.Add(Encoding.UTF8.GetString(pending.GetBuffer(), 0, (int)pending.Length));
                        pending.SetLength(0);
                    }
                    else pending.WriteByte(buffer[i]);
                }
            }
        }
        catch (Exception) { }
        finally { inbox.CompleteAdding(); }
    }

    public void Send(string json)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(json);
        lock (sendLock)
        {
            toChild.Write(bytes, 0, bytes.Length);
            toChild.WriteByte(0);
            toChild.Flush();
        }
    }

    // False on timeout, or when the pipe is closed and nothing is left to read.
    public bool TryReceive(int timeoutMs, out string message)
    {
        return inbox.TryTake(out message, timeoutMs);
    }

    // True once the other side closed the pipe and every queued message was read.
    public bool Closed { get { return inbox.IsCompleted; } }

    // True when the launched process has exited (or cannot be inspected).
    public bool WaitForChildExit(int timeoutMs)
    {
        try { return child == null || child.WaitForExit(timeoutMs); }
        catch (Exception) { return true; }
    }

    public void Dispose()
    {
        try { toChild.Dispose(); } catch (Exception) { }
        try { fromChild.Dispose(); } catch (Exception) { }
        try { if (child != null) child.Dispose(); } catch (Exception) { }
    }
}
'@

function Initialize-PipeType {
    if ('CdpPipe' -as [type]) { return }
    Add-Type -TypeDefinition $PipeSource -Language CSharp
}

# Runs one Blitz session over the private pipe.
# Returns $false only if Blitz could not be started this way (the caller may fall
# back to the TCP port). Returns $true once Blitz was started and the session ended.
function Start-PipeSession {
    param([string]$BlitzPath)

    try {
        Initialize-PipeType
        $script:CommandNames.Clear()
        $script:Sequence = 0
        $script:PagesAttached = 0
        $script:ConnectionPhase = 'launching Blitz over a private pipe'
        $script:Pipe = [CdpPipe]::Launch($BlitzPath, '--remote-debugging-pipe --remote-debugging-io-pipes={READ},{WRITE}')
    }
    catch {
        Write-Warning ('Could not start Blitz over a private pipe: {0}' -f (Format-ConnectionError -Exception $_.Exception))
        $script:Pipe = $null
        return $false
    }

    $pipe = $script:Pipe
    $received = $false
    $exited = $false
    Write-Host 'Launched Blitz with a private connection (no network debugging port).'
    Write-Host 'If Shield stops, Blitz closes its window to the tray and ads return until it is restarted through Shield.'
    try {
        Send-CdpCommand -Method 'Target.setAutoAttach' -Params @{
            autoAttach = $true
            waitForDebuggerOnStart = (-not $LegacyAttach)
            flatten = $true
        }
        $message = $null
        while ($true) {
            if ($pipe.TryReceive(1000, [ref]$message)) {
                if (-not $received) {
                    $received = $true
                    Write-Host 'Connected. Blocking known advertising networks...' -ForegroundColor Green
                }
                # A failure here must never end the worker: Blitz would close with it.
                try { Invoke-CdpMessage -Raw $message }
                catch { Write-Warning ('Skipped a message that could not be handled: {0}' -f $_.Exception.Message) }
            }
            elseif ($pipe.Closed) { break }
        }
        $script:ConnectionPhase = 'waiting for Blitz to exit'
        $exited = $pipe.WaitForChildExit(15000)
    }
    finally {
        $script:Pipe = $null
        $pipe.Dispose()
    }

    if (-not $received) {
        throw 'Blitz closed before it answered. If Blitz was just updated, close it fully and start it through Shield again.'
    }
    if ($exited) {
        # Blitz's helper processes need a moment to finish closing after the main one exits.
        for ($i = 0; $i -lt 10 -and (Get-Process -Name Blitz -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
    }
    if (Get-Process -Name Blitz -ErrorAction SilentlyContinue) {
        Write-Host 'Shield is no longer connected, but Blitz is still running (it may have restarted itself). Close Blitz fully and start it through Shield to block ads again.'
    } else {
        Write-Host 'Blitz is closed. Disconnecting the blocker.'
    }
    return $true
}

# Runs one Blitz session over a localhost TCP debugging port (legacy mode).
function Start-PortSession {
    param([string]$BlitzPath, [int]$Port)

    if ($Port -eq 0) { $Port = Find-FreeLoopbackPort }
    if ($Port -lt 1024 -or $Port -gt 65535) { throw 'Port must be 1024-65535, or 0 for an automatic port.' }

    $debugUrl = "http://127.0.0.1:$Port/json/version"
    Write-Host "Launching Blitz with localhost-only debug port $Port ..."
    $script:ConnectionPhase = 'launching Blitz'

    # Launch Blitz just once. Reconnecting the blocker must never restart or terminate the app.
    $blitz = Start-Process -FilePath $BlitzPath -ArgumentList @(
        '--remote-debugging-address=127.0.0.1',
        "--remote-debugging-port=$Port",
        "--remote-allow-origins=http://127.0.0.1:$Port"
    ) -PassThru

    $startupDeadline = (Get-Date).AddSeconds(35)
    $hasConnected = $false
    $failures = 0
    $lastConnectedAt = $null
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

            Connect-Blitz -WebSocketUri $webSocketUri -Port $Port

            if ($hasConnected) {
                Write-Host 'Reconnected to Blitz. Blocking known advertising networks...' -ForegroundColor Green
            } else {
                Write-Host 'Connected. Blocking known advertising networks...' -ForegroundColor Green
            }
            $hasConnected = $true
            $lastConnectedAt = Get-Date

            while ($script:Socket.State -eq [Net.WebSockets.WebSocketState]::Open) {
                $raw = Receive-CdpMessage
                if (-not $raw) { break }
                Invoke-CdpMessage -Raw $raw
            }

            if (-not (Get-Process -Name Blitz -ErrorAction SilentlyContinue)) {
                Write-Host 'Blitz is closed. Disconnecting the blocker.'
                break
            }
            throw 'Chromium closed the WebSocket connection.'
        }
        catch {
            # A connection that stayed healthy for 15 seconds is not part of a
            # rapid crash loop. Reset the retry counter only for stable sessions.
            if ($null -ne $lastConnectedAt -and ((Get-Date) - $lastConnectedAt).TotalSeconds -ge 15) {
                $failures = 0
            }
            $lastConnectedAt = $null
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

# Dot-sourcing this file (for tests) loads the functions without launching Blitz.
if ($MyInvocation.InvocationName -eq '.') { return }

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host "Blitz Ad Shield v$(Get-ShieldVersion)" -ForegroundColor Cyan
Write-Host 'Local Chromium request blocker + optional ad-slot hiding.'
if ($UsePort) {
    Write-Host 'In console mode, leave this window running; press Ctrl+C to stop blocking.'
} else {
    Write-Host 'In console mode, leave this window running; Ctrl+C stops blocking (Blitz then closes to its tray).'
}
Write-Host ''

if (-not (Test-Path -LiteralPath $BlitzPath -PathType Leaf)) {
    throw "Blitz.exe was not found: $BlitzPath`nPass -BlitzPath 'C:\path\to\Blitz.exe' if installed elsewhere."
}

# Do not terminate Blitz, Riot, or any other running process.
if (Get-Process -Name Blitz -ErrorAction SilentlyContinue) {
    throw 'Blitz is already running. Fully exit Blitz from the system tray and try again. This tool never kills Blitz automatically.'
}

try {
    $done = $false
    if (-not $UsePort) {
        $done = Start-PipeSession -BlitzPath $BlitzPath
        if (-not $done) {
            Write-Warning 'Falling back to the local TCP debugging port. Other programs on this PC may be able to reach it while Blitz runs.'
        }
    }
    if (-not $done) {
        Start-PortSession -BlitzPath $BlitzPath -Port $Port
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
