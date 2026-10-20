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
2. Preserve the localhost-only debugging connection and document any new network rules.
3. Do not include telemetry, tracking, secrets, bundled third-party executables, or undisclosed downloads.
4. Explain which Blitz and Windows versions you tested, or explicitly state that you could not test them.
5. Prefer readable, dependency-free PowerShell 5.1 over complex installers.
6. Do not add code intended to bypass Riot Vanguard, authentication, or anti-cheat safeguards.

## Validating a change

- Verify the scripts parse in **Windows PowerShell 5.1**.
- Start with Blitz fully closed, confirm it launches from the tray, and check the worker connection message.
- Verify Start, Stop, Logs and Exit behavior.
- Confirm Blitz can still run normally after you fully quit it and stop Shield.

No automated Windows integration test suite is currently supplied. Don't claim a fix is verified unless it was exercised on an actual Windows installation.
