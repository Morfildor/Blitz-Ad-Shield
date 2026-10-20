# Security policy

## Scope

Blitz Ad Shield has not undergone an external security audit. Security reports are reviewed on a best-effort basis; no formal response-time commitment is offered.

## Security-sensitive behavior

Shield launches Blitz with a **localhost Chromium remote-debugging port** and connects through Chrome DevTools Protocol. Other local programs may be able to access this debugging endpoint while Blitz remains running. Exiting Shield **does not** automatically close Blitz or that port. Fully quit Blitz after using Shield.

The package consists of readable PowerShell/VBScript/CMD source files and one local icon. No administrator privilege, service installation, persistent system-level policy change, or developer-operated server is required.

## Reporting a vulnerability

Please **do not publish credentials, active tokens, or proof-of-concept attacks against other users** in issues. To raise a concern, open a GitHub issue with non-sensitive details and request a private reporting channel before sharing sensitive technical material. If GitHub's private vulnerability reporting is enabled for this repository, use that instead.

## Supported versions

| Version | Status |
| --- | --- |
| 0.2 | Current |
| Earlier versions | Not supported |
