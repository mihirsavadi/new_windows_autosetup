Mihir Savadi
30th August 2026

# New Windows Auto Setup

A PowerShell toolkit that does the repetitive parts of setting up a fresh Windows
install: install apps + WSL2 + Office, activate Windows/Office (massgrave), undo
OneDrive's folder redirection, open a debloat tool, remap keys + wire up
AutoHotkey, and set the wallpaper.

Everything is driven by one settings file (`config.psd1`) and everything printed
is also saved to a timestamped `.log` in this folder.

---

## Quick start

1. Copy this whole folder onto the new machine.
2. Open `config.psd1` and check the toggles / app list (see notes in that file).
3. Right-click `setup.ps1` is not enough - open **PowerShell** in this folder and run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```

   It will ask for administrator rights once (one UAC prompt), then work through
   the stages.
4. When it finishes, read the two reminder lists it prints:
   * **NEEDS MANUAL INSTALL** - things you must install by hand.
   * **INSTALLED - STILL NEEDS SIGN-IN / SETUP** - apps that are installed but
     need you to log in / enter a licence / pair a device.
5. **Reboot** if it says a reboot is required (OneDrive, key remap, and WSL all
   need one).

---

## Run modes

| Command | What it does |
|---------|--------------|
| `.\setup.ps1` | Full run, obeying `config.psd1`. |
| `.\setup.ps1 -List` | Print the stages and whether each is enabled. Exit. |
| `.\setup.ps1 -DryRun` | Change nothing, download nothing. Prints `-- WHATIF ...` for every action. Read this first if unsure. |
| `.\setup.ps1 -TestRun` | Really downloads installers/scripts into a temp folder (deleted at the end) to prove the URLs and fallbacks work, but executes nothing and changes nothing. |
| `.\setup.ps1 -TestRun -KeepTestArtifacts` | Same, but keep the temp download folder. |
| `.\setup.ps1 -Task apps,wallpaper` | Run only the named stage(s). |
| `.\setup.ps1 -IncludeInstallerRefresh` | Also re-download the offline installers in `installers\` (in the background, concurrent with the run) and update them in place. Then `git add installers && git commit && git push` if anything changed. |

Stage names: `prereqs apps wsl vscode office activation onedrive debloat keyboard wallpaper taskbar startup`
(`prereqs` always runs first).

---

## What each stage does

| Stage | File | Summary |
|-------|------|---------|
| prereqs | `tasks\00-prereqs.ps1` | Check winget is present; refresh its sources. |
| apps | `tasks\10-apps.ps1` | Install the `Apps` list from `config.psd1`. Per app: if already present (`winget list` match or a configured exe path) -> log `SKIP` and do nothing else; otherwise `winget install` (silent, `--no-upgrade`); if that fails and the app has an `Offline` file, queue it - all queued GUI installers open together at the end. |
| wsl | `tasks\15-wsl.ps1` | `wsl --install --no-launch` + the distro in `WSLDistro` (default `Ubuntu-26.04`). Needs a reboot; first launch asks you to make a UNIX user. |
| vscode | `tasks\20-vscode.ps1` | Install the extensions in `vscode\extensions.txt`; copy `vscode\settings.json` if the machine has none. Reminds you to sign in to Settings Sync. |
| office | `tasks\30-office.ps1` | Install Microsoft 365 Apps (`OfficeMethod = 'winget'` or `'odt'`). |
| activation | `tasks\40-activation.ps1` | Run MAS (`https://get.activated.win`) with `/HWID` and/or `/Ohook` `/S`. Optional temporary Defender exclusion around this step. |
| onedrive | `tasks\50-onedrive.ps1` | Re-point Desktop/Documents/Pictures/... from the OneDrive copy back to `C:\Users\<you>\...` (registry). By default (`UninstallOneDrive = $true`) also kills + uninstalls OneDrive, removes its folder / scheduled tasks / startup entry / Explorer sidebar item. |
| debloat | `tasks\60-debloat.ps1` | Download Raphire/Win11Debloat, open its menu. **Does not remove anything on its own** - you choose. |
| keyboard | `tasks\70-keyboard.ps1` | Write the `Scancode Map` registry value from `SharpKeysRemaps` (default: Left Alt <-> Left Ctrl). Launch each `AhkScripts` script and set it to run at logon. |
| wallpaper | `tasks\80-wallpaper.ps1` | Copy `WallpaperSource` to `Pictures\`, set the registry, apply it live. |
| taskbar | `tasks\85-taskbar.ps1` | Remove the search box, left-align icons, hide Task View / Widgets / Chat, show battery %. Writes a best-effort pin layout (`TaskbarPins`) - Windows may ignore it on an existing profile, so the wanted order is also printed as a reminder. |
| startup | `tasks\90-startup.ps1` | Compare the current "runs at logon" list against a snapshot taken on the first run; reversibly disable anything added since that isn't in `StartupAllow` (Dropbox, Handy). Never deletes. |

---

## Folder layout

```
setup.ps1            the orchestrator you run
config.psd1          <-- the only file you normally edit
setup_<timestamp>.log written on every run (this folder)
lib\common.ps1       shared helper functions
tasks\               one file per stage (run in order, or pick with -Task)
tools\refresh-installers.ps1   re-download installers\ via `winget download`, replace if changed
assets\              skyewallpaper.jpg (your wallpaper)
ahk\                 your AutoHotkey scripts  (ctrl_tab_remap_and_instructions.ahk)
ahk\compiled\        compiled .exe fallback (not normally used)
vscode\              extensions.txt + settings.json captured from an existing machine
office\              configuration.xml (only used by OfficeMethod = 'odt')
installers\          offline GUI installers + a file->app map (installers\README.md)
```

---

## Things that are always manual (by nature)

* **WhatsApp** and **Fusion 360** - their installers are download stubs that need a
  Microsoft-Store / Autodesk sign-in. The script starts them; you finish them.
* **Brother printer** - winget only has the scan-only "iPrint&Scan" utility. Install
  the full "Full Driver & Software Package" for your model from
  <https://support.brother.com> (`installers\Y21C_C1_ULWT_PP-inst-E1.EXE` is likely
  it).
* **Sign-ins** - Dropbox, Spotify, Discord, Bitwarden (vault), Obsidian (vault),
  Eddie/AirVPN (credentials), PDF-XChange (licence key), VS Code (Settings Sync),
  Ubuntu/WSL (first-run user). The script lists exactly which at the end.

---

## Notes / caveats

* Written for **Windows PowerShell 5.1** (what ships with Windows). No PowerShell 7
  required.
* `Handy` uses a community-maintained winget package; if it breaks, the offline
  installer in `installers\` is the fallback.
* Spotify's winget install can fail when run elevated - that just triggers the
  offline `SpotifySetup.exe` fallback, which is fine.
* This folder is inside Dropbox; the `.log` files and `installers\` will sync. That
  is intentional (per Mihir), just be aware.
* MAS / activation requires an internet connection and is flagged by SmartScreen.
  The source is <https://massgrave.dev>.
