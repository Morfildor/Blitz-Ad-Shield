<div align="center">

# Blitz Ad Shield

**A free, open-source Blitz.gg ad blocker for Windows.**

Reduce advertising in the **Blitz.gg desktop app for League of Legends** without a paid subscription. Blitz Ad Shield combines network filtering and cosmetic cleanup with a lightweight Windows system-tray controller.

[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows&logoColor=white)](#requirements)
[![Version](https://img.shields.io/badge/version-v0.2%20experimental-F59E0B)](#project-status)
[![License](https://img.shields.io/badge/license-MIT-64748B)](#license)

[**Get started**](#installation) · [**How it works**](#how-it-works) · [**FAQ**](#frequently-asked-questions) · [**Report an issue**](https://github.com/Morfildor/Blitz-Ad-Shield/issues)

</div>

---

> [!IMPORTANT]
> **Experimental preview — not a confirmed working ad blocker.** The current Blitz release has **not** been tested with v0.2. Ads may remain, and future Blitz updates may break compatibility.
>
> **Source publication is pending:** This repository currently contains an import workflow, but not yet the full app. Its ZIP download is **not ready to use** until the project files are imported.

## What is Blitz Ad Shield?

**Blitz Ad Shield** is an independent, Windows-only utility for people who use Blitz.gg while playing League of Legends and would prefer fewer ads in the companion app.

It launches Blitz with a **localhost Chromium DevTools Protocol (CDP)** connection, attempts to block a curated set of advertising requests, and applies cosmetic rules to hide selected ad placeholders. A notification-area icon lets you manage it without leaving a terminal window open.

- **Free and local:** No subscription, account, installer, or paid dependencies.
- **Quiet system tray:** Start or stop protection, view status, and open logs.
- **Two kinds of filtering:** Advertising URL patterns plus cosmetic page cleanup.
- **No game-file changes:** Does not patch League of Legends, Riot Vanguard, or Blitz executables.
- **Easy to reverse:** Fully exit Shield and restart Blitz normally.

**It is not a browser extension, DNS blocker, League cheat, or replacement for Blitz Premium.** Results depend on how the current Blitz build serves its advertisements.

## Installation

**Requirements:** Windows 10/11, Windows PowerShell 5.1, an installed Blitz.gg desktop app, and a Blitz version that accepts Chromium remote-debugging flags.

Once the source import is complete:

1. Select **Code → Download ZIP** on [this repository](https://github.com/Morfildor/Blitz-Ad-Shield), then **extract** it. Do not run the scripts inside the ZIP.
2. **Completely quit Blitz**, including its notification-area icon.
3. Double-click **`Launch-Blitz-Ad-Shield.vbs`** from the extracted folder.
4. Locate the shield icon in the Windows tray (check the hidden-icons **^** menu).
5. **Right-click the icon** for **Start protection**, **Stop protection**, **Open logs folder**, or **Exit Shield**.

Blitz should launch through Shield. You **do not need to leave a Command Prompt window open**. If Windows disables VBScript, the project also contains `Run-Blitz-Ad-Shield.cmd` for console use.

> **Installed Blitz somewhere else?** Launch `Blitz-Ad-Shield-Tray.ps1` using PowerShell with `-BlitzPath "C:\path\to\Blitz.exe"`.

## How it works

```text
Tray launcher
    └── Hidden PowerShell worker
          └── Starts Blitz with a 127.0.0.1 CDP debugging endpoint
                ├── Rejects selected advertising URLs
                └── Hides some known ad containers
```

Filtering is implemented in readable PowerShell source. The worker needs to stay running for continued protection; the tray controller manages it and saves diagnostic logs under `%LOCALAPPDATA%\BlitzAdShield\Logs`.

This approach is **best-effort**. A successful connection does not prove that an ad was blocked, and filtering shared domains can interfere with legitimate Blitz content.

## Project status

| | |
| --- | --- |
| **Latest prototype** | v0.2 — Windows system-tray edition |
| **Compatibility** | Not verified with the current Blitz desktop release |
| **Release status** | Application source import pending |
| **Development** | Open-source, community-driven, experimental |

This project is intentionally transparent about what is and is not verified. Confirm that it works on your Blitz version before relying on it.

## Frequently asked questions

<details>
<summary><strong>Can I block Blitz.gg ads without paying for Premium?</strong></summary>

Blitz Ad Shield **attempts** to do that in the Windows desktop app. It does not guarantee complete ad removal or compatibility with the latest version.

</details>

<details>
<summary><strong>Do I need administrator access or another ad blocker?</strong></summary>

Not by design. The scripts use Windows PowerShell and built-in .NET components. They do not require changing your hosts file, DNS settings, or installing a system-wide proxy.

</details>

<details>
<summary><strong>Does it modify League of Legends or Riot Vanguard?</strong></summary>

No. Shield connects to Blitz's Chromium interface and does not modify League of Legends or Vanguard. **Compatibility with anti-cheat software and Blitz's terms has not been independently verified.**

</details>

<details>
<summary><strong>Why am I still seeing ads?</strong></summary>

Blitz may have changed its advertising endpoints, layout, or support for CDP debugging. Check the local logs, then [open an issue](https://github.com/Morfildor/Blitz-Ad-Shield/issues) with your Blitz version and a description of what remains. Review logs before sharing them because they may contain sensitive URLs or hostnames.

</details>

<details>
<summary><strong>Can I close the tray app after launching Blitz?</strong></summary>

The console does not need to stay visible, but the **tray controller and its worker** must continue running for filtering to persist. Closing Shield stops filtering; it does **not** close Blitz's debugging port. Fully quit Blitz when finished.

</details>

<details>
<summary><strong>How do I uninstall it?</strong></summary>

Choose **Exit Shield**, completely exit Blitz, delete the extracted folder, and optionally remove `%LOCALAPPDATA%\BlitzAdShield\Logs`. There is no system-level installation to undo.

</details>

## Security and limitations

> [!WARNING]
> **The Chromium debugging port is sensitive.** Shield requests a loopback address (`127.0.0.1`), but other software on your computer may be able to access the debugging endpoint while Blitz is running. Use this utility only on a trusted computer and **completely quit Blitz** when you are done.

Windows may display script-execution or download warnings. Read the source before running it; do not disable system or organizational security protections. Shield does not include telemetry or developer-run servers, but Blitz itself continues to communicate with its own services.

## Contributing

Found a broken selector, a changed ad endpoint, or a startup issue? [Report it here](https://github.com/Morfildor/Blitz-Ad-Shield/issues). Pull requests are welcome once source publication is complete. Please avoid including account tokens, private logs, or instructions to bypass Vanguard.

## License

MIT License. © 2026 **Morfildor**. The license file will be available when the project import is complete.

**Disclaimer:** Blitz Ad Shield is an unofficial, independent community project. It is not affiliated with, endorsed by, or supported by **Blitz.gg** or **Riot Games**. Their names and trademarks belong to their respective owners.
