# Publishing an update

Ad Shield v0.4.0 and later use the repository's `dist/latest.json` manifest for automatic updates.

## Release steps

1. Change the app's PowerShell or launcher files.
2. Update `VERSION` to a higher semantic version (for example, `0.4.1`).
3. Add a short entry to `CHANGELOG.md` and commit the changes to `main`.
4. The **Build and publish Windows portable app** workflow validates the PowerShell files, builds `dist/Blitz-Ad-Shield-Tray-v<version>.zip`, computes its SHA-256, and publishes `dist/latest.json`.
5. The **Windows updater integration test** verifies that an older installation can download and apply the published update.

The downloader only installs when the manifest version is newer than the installed `VERSION`. **Changing a script without increasing `VERSION` will not update existing installations.** Make sure to increment the version for every shipped application change.

Users receive updates automatically when they launch Shield and Blitz is closed. If Blitz is running, the update is downloaded but not installed until the next Shield launch. Shield also checks every six hours while running.

## Security and recovery

- The updater only accepts URLs matching the canonical `Morfildor/Blitz-Ad-Shield` GitHub download path.
- The manifest SHA-256 and size must match before extraction.
- Only a fixed list of application files is accepted from the archive.
- The previous files are backed up under `%LOCALAPPDATA%\BlitzAdShield\Updater`.
- A SHA-256 in a manifest published alongside its ZIP verifies integrity but is **not a separate publisher signature**. GitHub repository write permissions and Actions permissions must be protected.

If GitHub is unavailable, the downloader fails validation, or an update is not ready, the installed app should continue to launch. Test against the current Blitz version before marking a new release as compatible.
