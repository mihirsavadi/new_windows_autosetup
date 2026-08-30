# installers\

Offline GUI installers, kept here so a fresh machine can still install these apps
if winget is unavailable or a package fails.

**When they run:** `tasks\10-apps.ps1` only touches these if a winget install
*fails* (or if you set `PreferOffline = $true` in `config.psd1`). It then launches
**all** the needed ones **at once, with their normal GUIs**, for you to click
through. Nothing here is ever run silently.

`config.psd1` -> `OfflineInstallerSearchPaths` also lists `%USERPROFILE%\Downloads`,
so files there are picked up too without copying them in.

## File -> app

| File | App | Re-download from |
|------|-----|-----------------|
| `DropboxInstaller.exe` | Dropbox | https://www.dropbox.com/install |
| `BraveBrowserSetup-BRV011.exe` | Brave browser | https://brave.com/download/ |
| `Obsidian-1.13.7.exe` | Obsidian | https://obsidian.md/download |
| `SpotifySetup.exe` | Spotify | https://www.spotify.com/download/windows/ |
| `WhatsApp Installer.exe` | WhatsApp | https://www.whatsapp.com/download |
| `DiscordSetup.exe` | Discord | https://discord.com/download |
| `logioptionsplus_installer.exe` | Logi Options+ | https://www.logitech.com/software/logi-options-plus.html |
| `qbittorrent_5.2.3_x64_setup.exe` | qBittorrent | https://www.qbittorrent.org/download |
| `Y21C_C1_ULWT_PP-inst-E1.EXE` | Brother printer full driver (likely) | https://support.brother.com -> your model -> "Full Driver & Software Package" |
| `Bitwarden-Installer-2026.8.0.exe` | Bitwarden | https://bitwarden.com/download/ |
| `PrusaSlicer-2.9.6-setup.exe` | PrusaSlicer | https://www.prusa3d.com/prusaslicer/ |
| `EditorV11.x64.msi` | PDF-XChange Editor | https://www.pdf-xchange.com/product/pdf-xchange-editor |
| `VSCodeUserSetup-x64-1.135.0.exe` | Visual Studio Code | https://code.visualstudio.com/download |
| `Handy_0.9.4_x64-setup.exe` | Handy | https://handy.computer/download |
| `FPilot.exe` | File Pilot | https://filepilot.tech/download |
| `eddie-ui_2.26.2_windows_x64_installer.exe` | Eddie (AirVPN) | https://airvpn.org/windows/ |
| `Fusion Client Downloader.exe` | Autodesk Fusion 360 | https://www.autodesk.com/products/fusion-360 (sign-in required) |
| `AutoHotkey_2.0.27_setup.exe` | AutoHotkey v2 | https://www.autohotkey.com/ |
| `OfficeSetup.exe` | Microsoft 365 Apps (Click-to-Run) | https://www.office.com |

## No offline copy (winget only)

`Git.Git`, `Anthropic.ClaudeCode`, `RandyRants.SharpKeys`, `Python.Python.3.14` -
these install from winget only. If you want offline copies, grab:
Git (https://git-scm.com/download/win), SharpKeys
(https://github.com/randyrants/sharpkeys/releases), Python
(https://www.python.org/downloads/windows/).

## Not copied from Downloads (not on the app list)

`calibre-64bit-*.msi`, `SteamSetup.exe`, `wifiman-desktop-*.exe`,
`Framework_Laptop_13_*driver_bundle*.exe`, `Framework_Laptop_13_*BIOS*.exe`.
Drop any of these in here and add a matching
entry to `Apps` in `config.psd1` if you want them handled automatically.

## Win11Debloat\

Created at runtime by `tasks\60-debloat.ps1` (it downloads and unzips
Raphire/Win11Debloat here, then opens its menu).
