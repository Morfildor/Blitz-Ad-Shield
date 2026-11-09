# Security policy

## Scope

Blitz Ad Shield has not undergone an external security audit. Security reports are reviewed on a best-effort basis; no formal response-time commitment is offered.

## Security-sensitive behavior

By default, Shield launches Blitz with a **private pipe** (`--remote-debugging-pipe`) and connects through Chrome DevTools Protocol. No network port is opened, and only Shield holds the other end. Exiting Shield makes Blitz close its window to the tray and leaves it unfiltered.

If the pipe cannot be started, or `"connectionMode": "port"` is set in `%LOCALAPPDATA%\BlitzAdShield\settings.json`, Shield uses the legacy **localhost remote-debugging port**. Other local programs may be able to access that endpoint while Blitz remains running, and exiting Shield does not close it. Fully quit Blitz after using Shield in that mode.

The package consists of readable PowerShell/VBScript/CMD source files and one local icon. No administrator privilege, service installation, persistent system-level policy change, or developer-operated server is required.

## Reporting a vulnerability

Please **do not publish credentials, active tokens, or proof-of-concept attacks against other users** in issues. To raise a concern, open a GitHub issue with non-sensitive details and request a private reporting channel before sharing sensitive technical material. If GitHub's private vulnerability reporting is enabled for this repository, use that instead.

## Supported versions

| Version | Status |
| --- | --- |
| 0.2 | Current |
| Earlier versions | Not supported |
