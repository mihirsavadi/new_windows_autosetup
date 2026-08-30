# installers\

Offline **fallback** installers. `tasks\10-apps.ps1` always tries `winget` first;
one of these only runs if that app's winget install *fails* on the day (and then
it opens as a visible GUI, never silent). If winget succeeds, these are untouched.

Only apps where winget has a real reason to be distrusted get one:

| File | App | Why kept |
|---|---|---|
| `Logitech.OptionsPlus.installer.exe` | Logi Options+ | winget frequently fails here with an installer-hash mismatch |
| `cjpais.Handy.installer.exe` | Handy | winget package is community-maintained, not by the Handy devs |
| `AirVPN.Eddie.installer.exe` | Eddie / AirVPN | AirVPN's own server is the only source and can be slow |
| `Ubiquiti.WiFimanDesktop.installer.exe` | WiFiman | niche app, Ubiquiti's winget presence is an afterthought |
| `AutoHotkey.AutoHotkey.installer.exe` | AutoHotkey v2 | `tasks\70-keyboard.ps1` depends on it; 3 MB to guarantee it |
| `Voidstar.FilePilot.installer.exe` | File Pilot | fast-moving 0.x beta from a solo dev; 2.5 MB |

Filenames are `<winget-id>.installer.<ext>` on purpose so the refresh tool can
find and overwrite them.

## Keeping them current

```
.\tools\refresh-installers.ps1            # re-download all via `winget download`, replace if changed
.\tools\refresh-installers.ps1 -WhatIf    # show what would change, touch nothing
.\tools\refresh-installers.ps1 -Only handy,logioptions
```

Then `git add installers && git commit && git push`. The binaries are Git LFS
objects (see `.gitattributes`).

## Committed via Git LFS

Everything here except this README. Total ~126 MB across 6 files.

## `Win11Debloat\`

Created at runtime by `tasks\60-debloat.ps1`; git-ignored.
