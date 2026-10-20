<div align="center">

# 🛡️ Blitz Ad Shield

**Less ads. More game.**

A free, open-source ad blocker for the **Blitz.gg desktop app on Windows**.

Keep Blitz's useful features and get rid of distracting ads and empty ad spaces. It runs quietly in your system tray, with no subscription or extra software to install.

**[Download for Windows](https://github.com/Morfildor/Blitz-Ad-Shield/raw/refs/heads/main/dist/Blitz-Ad-Shield-Tray-v0.2.zip)** · **[How to install](#-getting-started)** · **[Source code](#how-it-works)** · **[Report a bug](https://github.com/Morfildor/Blitz-Ad-Shield/issues)**

<sub>Windows 10 / 11 · Free · Open source · MIT License</sub>

</div>

---

## Why I made this

Blitz is handy when you're playing League of Legends, but the ads can take up a lot of space. I wanted a simple way to clean up the app without paying for a subscription or messing with the game itself.

That's what Blitz Ad Shield does. It blocks known advertising requests, hides empty ad containers, and stays out of your way while you play.

### What you get

- **Fewer distractions:** Blocks known ad requests inside the Blitz desktop app.
- **More room:** Hides empty ad slots instead of leaving awkward gaps.
- **A simple tray icon:** Start or stop protection, check its status, and open logs whenever you need to.
- **No changes to game files:** Doesn't patch Blitz, League of Legends, or Riot Vanguard.
- **No subscription:** Free to use, with the source code available here on GitHub.

## 📦 Getting started

1. **[Download Blitz Ad Shield](https://github.com/Morfildor/Blitz-Ad-Shield/raw/refs/heads/main/dist/Blitz-Ad-Shield-Tray-v0.2.zip)** and extract the ZIP into a folder.
2. **Close Blitz completely.** Check the Windows system tray to make sure it isn't still running.
3. Double-click **`Launch-Blitz-Ad-Shield.vbs`** in the extracted folder.
4. Look for the shield icon near your clock. It may be hidden under the **^** menu.
5. Right-click the icon to **Start protection**, **Stop protection**, **Open logs folder**, or **Exit Shield**.

That's it. Blitz launches through Ad Shield, and you can leave the tool running in the tray. **No command window needs to stay open.**

**You'll need:** Windows 10 or 11, Windows PowerShell 5.1, and Blitz.gg installed.

If Windows has VBScript disabled, use `Run-Blitz-Ad-Shield.cmd` instead.

**Using a custom Blitz installation folder?** Launch `Blitz-Ad-Shield-Tray.ps1` in PowerShell with `-BlitzPath "C:\path\to\Blitz.exe"`.

## ⚙️ How it works

Blitz Ad Shield uses a local **Chromium DevTools Protocol (CDP)** connection to filter selected ad requests and hide ad containers in Blitz.

The blocker runs as a PowerShell process, while the tray icon gives you a convenient way to control it. Logs are saved locally at:

```text
%LOCALAPPDATA%\BlitzAdShield\Logs
```

There are no DNS changes, system-wide proxies, browser extensions, or patches to Riot's game files. The app is made up of readable PowerShell, VBScript, and CMD scripts, not a compiled executable.

## 🔒 A quick security note

Ad Shield starts Blitz with a **local Chromium debugging port**. Other programs on your computer may be able to access that connection while Blitz is open, so use it only on a PC you trust.

When you're done, **fully close Blitz** to shut down its debugging port. Exiting Ad Shield alone won't close it.

Blitz updates can occasionally change how ads are loaded. If you run into a problem, [open an issue](https://github.com/Morfildor/Blitz-Ad-Shield/issues). Please check logs for sensitive URLs before sharing them.

## Contribute

Found something to improve? Issues and pull requests are welcome.

Check out [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and the [MIT License](LICENSE).

<sub>© 2026 Morfildor. This is an independent community project and is not affiliated with Blitz.gg or Riot Games. All trademarks belong to their respective owners.</sub>
