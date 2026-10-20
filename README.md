<div align="center">

<img src="docs/assets/shield.svg" alt="Blitz Ad Shield" width="88">

# Blitz Ad Shield

**Fewer ads. More room for the game.**

A free, open-source ad blocker for the **Blitz.gg desktop app on Windows**. It blocks known ad requests, cleans up empty ad spaces, and runs quietly in your system tray.

[**⬇️ Download for Windows**](https://github.com/Morfildor/Blitz-Ad-Shield/raw/refs/heads/main/dist/Blitz-Ad-Shield-Tray-v0.2.zip) · [Installation](#installation) · [Report an issue](https://github.com/Morfildor/Blitz-Ad-Shield/issues)

<sub>Windows 10/11 · No subscription · No installer · MIT License</sub>

</div>

---

## Why I made this

I like using Blitz with League of Legends. I just don't like how much space its ads take up.

Blitz Ad Shield is a small tool I made to deal with that. Launch Blitz through it and carry on playing as usual, without having another window to manage.

## ✨ Features

- **Blocks ad requests.** Filters known advertising networks used by the Blitz desktop app.
- **Cleans up the layout.** Hides empty ad containers so they don't take up space.
- **Stays in your system tray.** Start or stop protection, check its status, and open logs with a right-click.
- **Leaves game files alone.** No changes to Blitz's installed files, League of Legends, or Riot Vanguard.
- **Runs locally.** No account, subscription, administrator rights, or separate ad-blocking service needed.

## Installation

1. **[Download Blitz Ad Shield](https://github.com/Morfildor/Blitz-Ad-Shield/raw/refs/heads/main/dist/Blitz-Ad-Shield-Tray-v0.2.zip)** and extract the ZIP.
2. **Quit Blitz completely.** Make sure it's also closed in the Windows system tray.
3. Open the extracted folder and double-click **`Launch-Blitz-Ad-Shield.vbs`**.
4. Find the shield icon in your system tray. It might be tucked under the **^** hidden-icons menu.

That's it. Blitz launches with Ad Shield running in the background. You don't need to keep a command window open, just leave the shield running in your tray.

**Tray controls:** Right-click the shield icon to **Start protection**, **Stop protection**, **Open logs folder**, or **Exit Shield**.

**Requirements:** Windows 10 or 11, Windows PowerShell 5.1, and the Blitz.gg desktop app.

<details>
<summary><strong>Alternative launch options</strong></summary>

If VBScript is disabled on your PC, launch `Run-Blitz-Ad-Shield.cmd` instead.

If Blitz is installed somewhere unusual, start `Blitz-Ad-Shield-Tray.ps1` in PowerShell with the custom executable path:

```powershell
.\Blitz-Ad-Shield-Tray.ps1 -BlitzPath "C:\path\to\Blitz.exe"
```

</details>

## ⚙️ How it works

Blitz Ad Shield connects to Blitz through the **Chromium DevTools Protocol (CDP)**. It filters selected advertising requests and applies CSS rules to hide known ad placeholders.

The [PowerShell blocker](Blitz-Ad-Shield.ps1) does the filtering, and the [tray controller](Blitz-Ad-Shield-Tray.ps1) manages it. Logs are saved to `%LOCALAPPDATA%\BlitzAdShield\Logs`.

It doesn't modify game files, change your DNS settings, or install a system-wide proxy.

## Troubleshooting

If Blitz doesn't start, make sure it's completely closed before launching Shield again. If the tray icon isn't visible, check the hidden-icons menu. If your PC blocks the VBScript launcher, use the CMD alternative above.

For other problems, [open a GitHub issue](https://github.com/Morfildor/Blitz-Ad-Shield/issues). Include your Windows and Blitz versions, along with what happened. Please remove sensitive URLs or other private information from logs before sharing them.

## A note about security

Shield opens a **local Chromium debugging port** while Blitz is running. Other programs on your computer may be able to access that session, so use it on a trusted PC.

**Fully quit Blitz when you're done.** Closing the Shield tray app stops filtering, but it doesn't close Blitz's debugging port. Future Blitz updates may also change how ad filtering behaves.

## Contributing

Found a bug or have an idea? Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and [LICENSE](LICENSE).

<sub>© 2026 Morfildor. Blitz Ad Shield is an independent community project, not affiliated with Blitz.gg or Riot Games. All trademarks belong to their respective owners.</sub>
