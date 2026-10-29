# Changelog

All notable changes to Blitz Ad Shield are documented here.

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

