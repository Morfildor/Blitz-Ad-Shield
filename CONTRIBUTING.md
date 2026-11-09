# Contributing

Blitz Ad Shield is a small, experimental PowerShell project. Issues, compatibility findings, and focused pull requests are welcome.

## Before opening an issue

- Confirm that Blitz was fully closed before you launched Shield.
- Read the [troubleshooting guide](README.md#troubleshooting).
- Mention your Windows version, Blitz app version, and how you launched Shield.
- Describe what you expected versus what happened.
- Include *redacted* logs if relevant. Remove usernames, local file paths, access tokens, account information, and any sensitive network details.

## Proposing code changes

1. Keep changes scoped and reversible; avoid modifying Blitz or League of Legends installation files.
2. Keep the connection to Blitz private: the default is a pipe with no open port, and the localhost-only port is a fallback. Document any new network rules.
3. Do not include telemetry, tracking, secrets, bundled third-party executables, or undisclosed downloads.
4. Explain which Blitz and Windows versions you tested, or explicitly state that you could not test them.
5. Prefer readable, dependency-free PowerShell 5.1 over complex installers.
6. Do not add code intended to bypass Riot Vanguard, authentication, or anti-cheat safeguards.

## Validating a change

- Verify the scripts parse in **Windows PowerShell 5.1**.
- Run the offline tests in Windows PowerShell 5.1: `powershell -NoProfile -File tests\Test-Worker.ps1` and `powershell -NoProfile -File tests\Test-Pipe.ps1`. CI runs both before packaging.
- Start with Blitz fully closed, confirm it launches from the tray, and check the worker connection message.
- Verify Start, Stop, Logs and Exit behavior, including the confirmation when Blitz is open.
- Confirm Blitz can still run normally after you fully quit it and stop Shield.
- Keep `Blitz-Ad-Shield.ps1` ASCII-only; Windows PowerShell 5.1 reads BOM-less files as ANSI.

The offline tests cover message handling and the pipe transport, not Blitz itself. Don't claim a fix is verified unless it was exercised on an actual Windows installation with Blitz.
