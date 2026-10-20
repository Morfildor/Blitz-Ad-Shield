<div align="center">

# Blitz Ad Shield

### Less clutter. More game.

**A free, open-source ad blocker for the Blitz.gg desktop app on Windows.**

Block advertising requests, remove empty ad spaces, and keep Blitz running with a cleaner interface—all from a small utility that lives in your system tray.

**[Download for Windows](https://github.com/Morfildor/Blitz-Ad-Shield/raw/refs/heads/main/dist/Blitz-Ad-Shield-Tray-v0.2.zip)** · **[Get started](#get-started)** · **[View source](#how-it-works)** · **[Report an issue](https://github.com/Morfildor/Blitz-Ad-Shield/issues)**

<sub>Windows 10 / 11 · No subscription · No installer · MIT licensed</sub>

</div>

---

## A cleaner Blitz.gg experience

Blitz Ad Shield is a lightweight Windows companion for people using **Blitz.gg with League of Legends**. It filters selected advertising requests and removes unused ad placeholders without patching the Blitz installation or touching League of Legends or Riot Vanguard.

**Designed to stay out of your way:**

- **Block ads** — Filter known advertising requests inside the Blitz desktop app.
- **Reclaim space** — Hide empty ad containers for a less cluttered layout.
- **Use the system tray** — Start, stop, check status, or open logs without a terminal window.
- **Keep control** — Free, locally operated, open-source scripts. No account or subscription required.

## Get started

1. **[Download Blitz Ad Shield for Windows](https://github.com/Morfildor/Blitz-Ad-Shield/raw/refs/heads/main/dist/Blitz-Ad-Shield-Tray-v0.2.zip)** and extract the ZIP to a folder.
2. **Fully exit Blitz**, including its icon in the Windows notification area.
3. Double-click **`Launch-Blitz-Ad-Shield.vbs`** inside the extracted folder.
4. Look for the **shield icon** in the system tray (under **^** if hidden).
5. Right-click it to access **Start protection**, **Stop protection**, **Open logs folder**, or **Exit Shield**.

Blitz opens through Shield, and protection continues without a visible command window. Keep the tray utility running while using Blitz.

**Requirements:** Windows 10 or 11, Windows PowerShell 5.1, and the Blitz.gg desktop app. No administrator privileges or additional ad-blocking software required.

> If VBScript is disabled, use `Run-Blitz-Ad-Shield.cmd` instead. For a custom Blitz installation path, launch `Blitz-Ad-Shield-Tray.ps1` with `-BlitzPath "C:\path\to\Blitz.exe"`.

## How it works

Blitz Ad Shield launches Blitz with a local **Chromium DevTools Protocol (CDP)** connection. The PowerShell worker uses it to filter advertising network requests and apply cosmetic cleanup rules. A separate tray controller manages the worker and stores diagnostic logs at:

```text
%LOCALAPPDATA%\BlitzAdShield\Logs
```

Everything runs locally. There is no system-wide DNS change, proxy, service, browser extension, or modification of Blitz and Riot game files.

The project is distributed as readable **PowerShell, VBScript, and CMD files**, not a compiled `.exe`. Browse [the source code](https://github.com/Morfildor/Blitz-Ad-Shield) or check [the changelog](CHANGELOG.md).

## Important to know

Shield uses a **localhost Chromium debugging port**. Other programs on your PC may be able to access that session while Blitz is running. Use it on a trusted computer, and **fully exit Blitz after use** to close its debugging port; closing Shield alone does not close it.

Blitz updates may change how advertising is delivered. If something stops behaving as expected, [open an issue](https://github.com/Morfildor/Blitz-Ad-Shield/issues) with the Blitz version and a description of the problem. Review logs before sharing them, as they may contain sensitive URLs.

## Open source

Contributions and fixes are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and the [MIT License](LICENSE).

<sub>© 2026 Morfildor. Independent community project. Not affiliated with or endorsed by Blitz.gg or Riot Games. All respective trademarks belong to their owners.</sub>
