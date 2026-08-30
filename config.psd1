# ==============================================================================
#  config.psd1  --  the ONE file you edit to change what setup.ps1 does
# ==============================================================================
#
#  WHAT THIS FILE IS
#  ----------------
#  A ".psd1" is a "PowerShell Data file". It is NOT a script - it can only hold
#  plain data: text in 'quotes', numbers, $true / $false, lists written as
#  @( item1, item2 ), and tables written as @{ Key = Value }. No commands run
#  here, so it is safe to read and safe to edit.
#
#  setup.ps1 loads this file at the start of every run with:
#      Import-PowerShellDataFile .\config.psd1
#  ...and then obeys whatever it finds here.
#
#  HOW TO EDIT SAFELY
#  -----------------
#  * To turn a stage on/off, change its $true to $false (or back).
#  * To stop installing an app, put a '#' at the start of its line (that
#    "comments it out" so PowerShell ignores it).
#  * Keep the punctuation: every app line is  @{ ... }  with  Key = 'Value'
#    pairs separated by  ;  . Match the pattern of the lines around it.
#  * Paths may use %WINDOWS_STYLE% variables like %USERPROFILE% - setup.ps1
#    expands those for you. A path with no drive letter (e.g. 'assets\x.jpg')
#    is taken relative to this folder.
#
#  Every line starting with '#' is a comment and is ignored.
# ==============================================================================

@{

    # =========================================================================
    #  STAGE TOGGLES
    #  Each stage is one file in .\tasks\ . $true = run it, $false = skip it.
    #  You can also run a subset from the command line, e.g.:
    #      .\setup.ps1 -Task apps,wallpaper
    #  ...which ignores these toggles and just runs what you named.
    # =========================================================================

    InstallApps          = $true    # tasks\10-apps.ps1      - winget app installs
    InstallWSL           = $true    # tasks\15-wsl.ps1       - WSL2 + Ubuntu
    ConfigureVSCode      = $true    # tasks\20-vscode.ps1    - extensions + settings
    InstallOffice        = $true    # tasks\30-office.ps1    - Microsoft 365 Apps
    Activate             = $true    # tasks\40-activation.ps1 - MAS (massgrave)
    FixOneDrive          = $true    # tasks\50-onedrive.ps1  - un-redirect user folders (+remove OneDrive, see below)
    RunDebloat           = $true    # tasks\60-debloat.ps1   - open Win11Debloat menu
    ConfigureKeyboard    = $true    # tasks\70-keyboard.ps1  - key swap + AutoHotkey
    SetWallpaper         = $true    # tasks\80-wallpaper.ps1
    ConfigureTaskbar     = $true    # tasks\85-taskbar.ps1   - remove search, battery %, left align, pins
    ManageStartup        = $true    # tasks\90-startup.ps1   - disable startup entries added after first run

    # =========================================================================
    #  OFFICE  (tasks\30-office.ps1)
    # =========================================================================
    #  'winget' = install "Microsoft 365 Apps" via  winget install Microsoft.Office
    #             (simplest; no choices).
    #  'odt'    = use Microsoft's Office Deployment Tool with office\configuration.xml
    #             (edit that XML first if you want to pick which apps/channel).
    OfficeMethod         = 'winget'

    # =========================================================================
    #  ACTIVATION  (tasks\40-activation.ps1)  --  uses https://massgrave.dev
    # =========================================================================
    ActivateWindows      = $true    # run MAS  /HWID   (permanent Windows digital licence)
    ActivateOffice       = $true    # run MAS  /Ohook  (Office activation)
    # MAS is flagged by SmartScreen/Defender. When $true, setup.ps1 adds a
    # TEMPORARY Defender exclusion for just this step and removes it right after.
    DefenderExclusionDuringActivation = $true
    MasUrl               = 'https://get.activated.win'

    # =========================================================================
    #  WSL2 + LINUX  (tasks\15-wsl.ps1)
    # =========================================================================
    #  Distro name must be one that  wsl --list --online  offers.
    WSLDistro            = 'Ubuntu-26.04'

    # =========================================================================
    #  ONEDRIVE  (tasks\50-onedrive.ps1)
    # =========================================================================
    #  Always: repoints Desktop/Documents/Pictures/etc. from the OneDrive copy
    #  back to the real C:\Users\<you>\... folders (registry edit).
    #  Mihir does not use OneDrive at all, so the defaults below rip it out.
    OneDriveMoveContent  = $false   # ROBOCOPY existing files out of OneDrive first (pointless on a clean install / empty OneDrive)
    UninstallOneDrive    = $true    # kill + uninstall OneDrive, remove its folder, scheduled tasks, startup entry, and Explorer sidebar item

    # =========================================================================
    #  WALLPAPER  (tasks\80-wallpaper.ps1)
    # =========================================================================
    WallpaperSource      = 'assets\skyewallpaper.jpg'
    #  One of: Fill  Fit  Stretch  Tile  Center  Span
    WallpaperStyle       = 'Fill'

    # =========================================================================
    #  TASKBAR  (tasks\85-taskbar.ps1)
    # =========================================================================
    #  These are all plain registry toggles under the current user - reliable,
    #  reversible, applied by restarting Explorer at the end of the stage.
    TaskbarRemoveSearch      = $true    # hide the search box/icon completely
    TaskbarLeftAlign         = $true    # icons start at the left (like the screenshot) instead of centred
    TaskbarHideTaskView      = $true    # hide the Task View button
    TaskbarHideWidgets       = $true    # hide the Widgets (weather) button
    TaskbarHideChat          = $true    # hide the Teams/Chat button
    TaskbarBatteryPercent    = $true    # show battery percentage in the tray

    #  Pinned apps, in order. NOTE: Microsoft broke scripted taskbar pinning on
    #  Windows 11 24H2/25H2. tasks\85-taskbar.ps1 writes a LayoutModification.xml
    #  (which DOES work on a brand-new profile's first sign-in) and otherwise
    #  just prints this list as a reminder to drag them into place once.
    #  Keys map to entries inside the task; unknown keys are ignored.
    TaskbarPins = @('explorer', 'terminal', 'brave', 'spotify', 'whatsapp', 'discord', 'handy', 'vscode')

    # =========================================================================
    #  KEYBOARD  (tasks\70-keyboard.ps1)
    # =========================================================================
    #  SharpKeysRemaps: hardware-level key swaps written straight to the registry
    #  (this is exactly what the SharpKeys app does, minus the GUI). Each entry is
    #      @{ From = '<scancode you press>' ; To = '<scancode it becomes>' }
    #  Scancodes are 'HH_HH' hex. Common ones:
    #      00_1D = Left Ctrl     00_38 = Left Alt      00_3A = Caps Lock
    #      E0_5B = Left Win      00_01 = Esc           E0_38 = Right Alt
    #  The default below is Mihir's Mac-style thumb swap: Left Alt <-> Left Ctrl.
    #  Empty the list ( SharpKeysRemaps = @() ) to write nothing and just leave
    #  the SharpKeys app installed for manual use.
    #  A reboot is required for any change here to take effect.
    SharpKeysRemaps = @(
        @{ From = '00_38'; To = '00_1D' }   # Left Alt   -> Left Ctrl
        @{ From = '00_1D'; To = '00_38' }   # Left Ctrl  -> Left Alt
    )

    #  AutoHotkey scripts (looked for in .\ahk\). Each is launched now AND set to
    #  start automatically at logon.
    AhkScripts          = @('ctrl_tab_remap_and_instructions.ahk')
    #  How to make them run at logon:
    #   'Shortcut'      - a .lnk in your Startup folder (simple, per-user).
    #   'ScheduledTask' - a logon-triggered scheduled task running elevated. Use
    #                     this if Ctrl+Tab -> Alt+Tab misbehaves over admin windows.
    AhkStartupMethod    = 'Shortcut'

    # =========================================================================
    #  OFFLINE INSTALLER FALLBACK  (tasks\10-apps.ps1)
    # =========================================================================
    #  If a winget install fails, setup.ps1 looks for a matching installer file in
    #  these folders (first match wins) and, at the end of the app stage, launches
    #  every such fallback AT ONCE with its normal GUI for you to click through.
    #  It never tries to run these silently.
    OfflineInstallerSearchPaths = @('installers', '%USERPROFILE%\Downloads')

    #  Set to $true to SKIP winget entirely and go straight to the GUI installers
    #  in the folders above. (Normally leave $false.)
    PreferOffline        = $false

    # =========================================================================
    #  STARTUP APPS  (tasks\90-startup.ps1)
    # =========================================================================
    #  The FIRST time setup.ps1 runs it snapshots which startup entries are
    #  already enabled and saves that list to  .state\startup-baseline.txt .
    #  After that, this stage disables (reversibly - same flag the Settings page
    #  uses) any enabled startup entry that is NOT in the baseline and NOT
    #  matched by StartupAllow below. It never deletes anything.
    #
    #  StartupPolicy:
    #    'Enforce' - actually toggle the extras off (and always print the list)
    #    'Remind'  - only print the list + the reminder, change nothing
    StartupPolicy = 'Enforce'

    #  Always keep these enabled even if they appeared after the first run.
    #  Wildcards allowed; matched against the entry name (case-insensitive).
    StartupAllow  = @('Dropbox*', '*Handy*')

    # =========================================================================
    #  THE APP LIST  (tasks\10-apps.ps1)
    # =========================================================================
    #  Order matters (Dropbox first, etc.). Fields per app:
    #     Key         short id used on the command line and in the log
    #     Name        friendly name for the log
    #     Id          winget package id  (omit for ManualOnly apps)
    #     Source      'winget' (default) or 'msstore'
    #     Scope       'machine' or 'user' - only set if the package needs it
    #     Override    extra args passed to the app's own installer via winget --override
    #     Offline     filename (wildcards ok) of the GUI installer to fall back to
    #     ManualOnly  $true  -> never attempt; just print it in the "install by hand" list
    #     Interactive $true  -> attempt, but ALWAYS remind you to finish it by hand
    #     NeedsSignin $true  -> on success, remind you to log in / enter a licence
    #     Note        one line shown next to the app in the end-of-run reminders
    # =========================================================================
    Apps = @(
        @{ Key='dropbox';     Name='Dropbox';                Id='Dropbox.Dropbox';                   Offline='DropboxInstaller.exe';                 NeedsSignin=$true;  Note='Sign in to start syncing.' }
        @{ Key='brave';       Name='Brave browser';          Id='Brave.Brave';                       Offline='BraveBrowserSetup-*.exe';             NeedsSignin=$true;  Note='Sign in / import bookmarks; also on the taskbar (tasks\85-taskbar.ps1).' }
        @{ Key='obsidian';    Name='Obsidian';               Id='Obsidian.Obsidian';                 Offline='Obsidian-*.exe';                       NeedsSignin=$true;  Note='Open your vault; sign in to Obsidian Sync if you use it.' }
        @{ Key='spotify';     Name='Spotify';                Id='Spotify.Spotify';                   Offline='SpotifySetup.exe';                     NeedsSignin=$true;  Note='Log in. winget install can fail when elevated - the offline GUI is the fallback.' }
        @{ Key='whatsapp';    Name='WhatsApp';               Id='9NKSQGP7F2NH'; Source='msstore';    Offline='WhatsApp Installer.exe';               Interactive=$true;  Note='Finish from Microsoft Store if prompted, then link your phone.' }
        @{ Key='discord';     Name='Discord';                Id='Discord.Discord';                   Offline='DiscordSetup.exe';                     NeedsSignin=$true;  Note='Log in.' }
        @{ Key='logioptions'; Name='Logi Options+';          Id='Logitech.OptionsPlus';              Offline='logioptionsplus_installer.exe';                            Note='If winget reports a hash mismatch the GUI installer is used instead.' }
        @{ Key='qbittorrent'; Name='qBittorrent';            Id='qBittorrent.qBittorrent';           Offline='qbittorrent_*_setup.exe' }
        @{ Key='brother';     Name='Brother printer driver'; ManualOnly=$true;                                                                                          Note='Winget only has the scan-only "iPrint&Scan" utility. Install the full "Full Driver & Software Package" for your model from https://support.brother.com  (installers\Y21C_C1_ULWT_PP-inst-E1.EXE is likely it).' }
        @{ Key='bitwarden';   Name='Bitwarden';              Id='Bitwarden.Bitwarden';               Offline='Bitwarden-Installer-*.exe';            NeedsSignin=$true;  Note='Log in and unlock your vault.' }
        @{ Key='prusaslicer'; Name='PrusaSlicer';            Id='Prusa3D.PrusaSlicer';               Offline='PrusaSlicer-*-setup.exe' }
        @{ Key='pdfxchange';  Name='PDF-XChange Editor';     Id='TrackerSoftware.PDF-XChangeEditor';  Offline='EditorV11.x64.msi';                   NeedsSignin=$true;  Note='Enter your licence key, or keep using the free feature set.' }
        @{ Key='vscode';      Name='Visual Studio Code';     Id='Microsoft.VisualStudioCode';        Offline='VSCodeUserSetup-x64-*.exe';            NeedsSignin=$true;  Note='Sign in to Settings Sync. tasks\20-vscode.ps1 pre-loads your extensions and settings.json.' }
        @{ Key='handy';       Name='Handy (speech-to-text)'; Id='cjpais.Handy';                      Offline='Handy_*_x64-setup.exe';                                   Note='Community-maintained winget package; offline installer is the fallback.' }
        @{ Key='filepilot';   Name='File Pilot';             Id='Voidstar.FilePilot';                Offline='FPilot.exe' }
        @{ Key='eddie';       Name='Eddie - AirVPN';         Id='AirVPN.Eddie';                      Offline='eddie-ui_*_windows_x64_installer.exe'; NeedsSignin=$true;  Note='Enter your AirVPN credentials or import your .ovpn profile.' }
        @{ Key='fusion360';   Name='Autodesk Fusion 360';    Id='Autodesk.Fusion';                   Offline='Fusion Client Downloader.exe';         Interactive=$true;  Note='The installer is a downloader - finish it and sign in with your Autodesk account.' }
        @{ Key='autohotkey';  Name='AutoHotkey v2';          Id='AutoHotkey.AutoHotkey';             Offline='AutoHotkey_*_setup.exe';                                   Note='Used by tasks\70-keyboard.ps1.' }
        @{ Key='sharpkeys';   Name='SharpKeys';              Id='RandyRants.SharpKeys';                                                                                 Note='Installed for reference; the key swap itself is done by tasks\70-keyboard.ps1 via the registry.' }
        @{ Key='git';         Name='Git';                    Id='Git.Git' }
        @{ Key='claudecode';  Name='Claude Code CLI';        Id='Anthropic.ClaudeCode';                                                             NeedsSignin=$true;  Note='Run  claude  in a terminal and sign in.' }
        @{ Key='python';      Name='Python 3.14';            Id='Python.Python.3.14'; Scope='machine'; Override='/quiet PrependPath=1 Include_test=0 InstallAllUsers=1'; Note='Installed for all users and added to PATH; the Microsoft Store python stub is disabled so this one wins.' }
    )
}
