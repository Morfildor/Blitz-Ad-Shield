# Changelog

All notable changes to Blitz Ad Shield are documented here.

## [0.5.0] - 2026-10-29

### Changed
- Downloaded updates now install automatically once Blitz has exited naturally, without requiring the user to restart Shield.
- Shield safely hands off the update to a helper, closes its previous tray process, then reopens the updated tray without launching Blitz unexpectedly.
- Failed automatic installation attempts have a six-hour cooldown, preventing repeated restart loops.
- The in-game session remains uninterrupted; downloads continue in the background.

### Upgrade note
- v0.4 and v0.4.1 users receive this version through their existing updater at the next regular launch with Blitz closed. The new hands-free installation behavior is active after that upgrade.

## [0.4.1] - 2026-10-29

### Added
- Installed version shown in the system-tray menu, making it easy to verify successful automatic updates.
- Windows integration test of a v0.4.0 staged download and installation after restarting.

### Notes
- No changes to ad filtering in this release.

## [0.4.0] - 2026-10-29

### Added
- Automatic GitHub update checks before each launch and every six hours while running.
- Download and staging of updates without interrupting an active Blitz session.
- Safe application of pending updates the next time Shield starts with Blitz closed.
- SHA-256 integrity verification, restricted download URLs, archive file allowlisting, and backups for recovery.
- "Check for updates" and pending-version information in the system-tray menu.
- A published `dist/latest.json` manifest generated alongside each versioned Windows ZIP.

### Upgrade note
- v0.3 users need to install v0.4 once. Future versions will update through the built-in updater.

## [0.3] - 2026-10-29

### Fixed
- Reconnect to the local Chromium WebSocket after temporary disconnects or Blitz startup changes.
- Add a restricted localhost Origin to the CDP WebSocket handshake and matching Chromium launch flag for newer browser builds.
- Keep Blitz running while the blocker retries a failed connection.
- Limit repeated connection attempts and include the failing CDP operation and underlying exception in diagnostic logs.
- Show a reconnecting status in the system tray rather than immediately exiting.

### Notes
- Blitz versions changed repeatedly in late October 2026. This release improves recovery from connection failures, but compatibility with every updated Blitz build has not been verified.
- The application does not change Blitz or Riot game files.

## [0.2] - 2026-10-20

### Added
- Windows system-tray controller with Start protection, Stop protection, Open logs folder, and Exit Shield actions.
- Hidden PowerShell worker process and local diagnostic logs.
- VBScript launcher and CMD fallback launcher.
- Single-instance tray mutex and worker disconnection reporting.

### Existing functionality
- Chromium DevTools Protocol connection to locally launched Blitz.
- Selected ad network request blocking and cosmetic ad-slot hiding.
- Console diagnostics and hostname inspection.

