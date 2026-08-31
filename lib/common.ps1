# ==============================================================================
#  lib\common.ps1  --  shared helper functions used by setup.ps1 and every task
# ==============================================================================
#
#  HOW THIS FILE IS USED
#  --------------------
#  setup.ps1 "dot-sources" this file:   . .\lib\common.ps1
#  Dot-sourcing means "run this file in my own scope", so every function below
#  becomes available to setup.ps1 and to each tasks\*.ps1 file, and they all
#  share one piece of state: the object  $global:NWAS  (New Windows Auto Setup),
#  which setup.ps1 creates before dot-sourcing anything.
#
#  $global:NWAS fields the helpers rely on:
#     .Root           full path to this project folder
#     .Config         the hashtable loaded from config.psd1
#     .Mode           'Normal' | 'DryRun' | 'TestRun'
#     .NoExecute      $true in DryRun AND TestRun - block machine changes
#     .NoDownload     $true in DryRun only        - block network downloads
#     .TempDir        scratch folder (TestRun only), deleted at the end
#     .RebootNeeded / .RebootReasons
#     .ManualInstall  list of "install this yourself" reminder lines
#     .NeedsSignin    list of "installed, now sign in" reminder lines
#     .Results        list of per-item {Stage,Item,Status,Detail} records
#     .FallbackQueue  offline GUI installers to launch together at stage end
#
#  Every line starting with '#' is a comment and is ignored by PowerShell.
# ==============================================================================


# ------------------------------------------------------------------------------
#  New-Timestamp
#  A date/time string safe to use in a Windows filename. Windows forbids ':' in
#  filenames, so the usual ISO-8601 "2026-08-30T14:55:33" becomes
#  "2026-08-30T14-55-33". It still sorts chronologically as plain text.
# ------------------------------------------------------------------------------
function New-Timestamp {
    Get-Date -Format 'yyyy-MM-ddTHH-mm-ss'
}


# ------------------------------------------------------------------------------
#  Write-Log
#  The ONLY way this project prints to the screen. setup.ps1 wraps the whole run
#  in Start-Transcript, which copies everything printed here into the .log file,
#  so the log ends up character-for-character identical to what you saw.
#
#  -Level picks a short tag and a colour:
#     Head   "== "  section banner (cyan)
#     Step   ">> "  an action about to happen (white)
#     Info   "   "  detail / sub-step (grey)
#     Good   "OK "  success (green)
#     Warn   "!! "  non-fatal problem (yellow)
#     Error  "XX "  failure (red)
#     WhatIf "-- "  "in DryRun/TestRun I would have done X" (dark grey)
# ------------------------------------------------------------------------------
function Write-Log {
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string] $Message,

        [Parameter(Position = 1)]
        [ValidateSet('Head', 'Step', 'Info', 'Good', 'Warn', 'Error', 'WhatIf')]
        [string] $Level = 'Info'
    )

    $time = Get-Date -Format 'HH:mm:ss'

    switch ($Level) {
        'Head'   { $tag = '== '; $colour = 'Cyan' }
        'Step'   { $tag = '>> '; $colour = 'White' }
        'Good'   { $tag = 'OK '; $colour = 'Green' }
        'Warn'   { $tag = '!! '; $colour = 'Yellow' }
        'Error'  { $tag = 'XX '; $colour = 'Red' }
        'WhatIf' { $tag = '-- '; $colour = 'DarkGray' }
        default  { $tag = '   '; $colour = 'Gray' }
    }

    Write-Host ('[{0}] {1}{2}' -f $time, $tag, $Message) -ForegroundColor $colour
}


# ------------------------------------------------------------------------------
#  Test-IsAdmin  ->  $true if this PowerShell is running "as administrator".
#  Many stages (winget machine installs, HKLM registry, WSL, activation) need it.
# ------------------------------------------------------------------------------
function Test-IsAdmin {
    $identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}


# ------------------------------------------------------------------------------
#  Expand-ConfigPath
#  Turn a path written in config.psd1 into a real absolute path:
#    * expand %USERPROFILE% and friends (ExpandEnvironmentVariables)
#    * if it has no drive letter, treat it as relative to this project folder
# ------------------------------------------------------------------------------
function Expand-ConfigPath {
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }

    $expanded = [System.Environment]::ExpandEnvironmentVariables($Path)

    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        $expanded = Join-Path $global:NWAS.Root $expanded
    }
    return $expanded
}


# ------------------------------------------------------------------------------
#  Invoke-Change
#  Wrap ANY action that changes the machine (writes a file, edits the registry,
#  runs an installer). In Normal mode it prints the description and runs the
#  script block. In DryRun/TestRun it only prints "-- WHATIF ..." and returns.
#
#  Usage:
#     Invoke-Change "set wallpaper registry value" { Set-ItemProperty ... }
# ------------------------------------------------------------------------------
function Invoke-Change {
    param(
        [Parameter(Mandatory, Position = 0)][string]      $Describe,
        [Parameter(Mandatory, Position = 1)][scriptblock] $Do
    )

    if ($global:NWAS.NoExecute) {
        Write-Log "WHATIF  $Describe" 'WhatIf'
        return
    }

    Write-Log $Describe 'Step'
    & $Do
}


# ------------------------------------------------------------------------------
#  Get-RemoteFile
#  Download a URL to a file, honouring the run mode:
#     DryRun  : download nothing, log "-- WHATIF would download ...", return $null
#     TestRun : DO download, but into $global:NWAS.TempDir (thrown away at the
#               end) instead of the real destination; return the temp path
#     Normal  : download to -OutFile; return that path
# ------------------------------------------------------------------------------
function Get-RemoteFile {
    param(
        [Parameter(Mandatory)][string] $Url,
        [Parameter(Mandatory)][string] $OutFile
    )

    if ($global:NWAS.NoDownload) {
        Write-Log "WHATIF  would download $Url" 'WhatIf'
        return $null
    }

    $dest = $OutFile
    if ($global:NWAS.Mode -eq 'TestRun') {
        $dest = Join-Path $global:NWAS.TempDir ([System.IO.Path]::GetFileName($OutFile))
    }

    $parent = Split-Path $dest -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    Write-Log "downloading $Url" 'Info'

    # Invoke-WebRequest's progress bar is very slow over a remote session; hide it.
    $savedProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing -ErrorAction Stop
    }
    finally {
        $ProgressPreference = $savedProgress
    }

    $sizeMB = (Get-Item $dest).Length / 1MB
    Write-Log ('saved -> {0}  ({1:N1} MB)' -f $dest, $sizeMB) 'Good'
    return $dest
}


# ------------------------------------------------------------------------------
#  Test-AppInstalled  ->  $true if the app already appears to be present.
#  Checks, in order:
#     1. an explicit .DetectExe path from the app entry (if given)
#     2. "winget list --id <Id>" reporting a match
# ------------------------------------------------------------------------------
function Test-AppInstalled {
    param([Parameter(Mandatory)][hashtable] $App)

    if ($App.DetectExe) {
        $exe = Expand-ConfigPath $App.DetectExe
        if (Test-Path $exe) { return $true }
    }

    if ($App.Id) {
        $source = 'winget'
        if ($App.Source) { $source = $App.Source }

        $listing = & winget list --id $App.Id --exact --source $source --accept-source-agreements 2>$null
        if ($LASTEXITCODE -eq 0 -and ($listing | Select-String -SimpleMatch $App.Id -Quiet)) {
            return $true
        }
    }

    return $false
}


# ------------------------------------------------------------------------------
#  Invoke-Winget
#  Run one silent "winget install" for an app entry from config.psd1.
#  Returns an object: @{ Success = <bool>; ExitCode = <int>; WhatIf = <bool> }
#
#  winget uses odd exit codes; a few non-zero ones still mean "fine":
#     0x8A15002B  -1978335189  no newer version to install
#     0x8A150061  -1978334623  package already installed
#  For anything else we re-check Test-AppInstalled before declaring failure.
# ------------------------------------------------------------------------------
function Invoke-Winget {
    param([Parameter(Mandatory)][hashtable] $App)

    $arguments = @(
        'install'
        '--id'; $App.Id
        '--exact'
        '--silent'
        '--accept-package-agreements'
        '--accept-source-agreements'
        '--disable-interactivity'
        '--no-upgrade'
    )
    if ($App.Source)        { $arguments += @('--source', $App.Source) }
    if ($App.Scope)         { $arguments += @('--scope', $App.Scope) }
    if ($App.InstallerType) { $arguments += @('--installer-type', $App.InstallerType) }
    if ($App.Override)      { $arguments += @('--override', $App.Override) }

    Write-Log ('winget ' + ($arguments -join ' ')) 'Info'

    if ($global:NWAS.NoExecute) {
        Write-Log 'WHATIF  would run the winget command above' 'WhatIf'
        return [pscustomobject]@{ Success = $true; ExitCode = 0; WhatIf = $true }
    }

    & winget @arguments
    $code = $LASTEXITCODE

    $benign = @(0, -1978335189, -1978334623)
    $ok = $benign -contains $code
    if (-not $ok) {
        # last resort: did it actually land despite the noisy exit code?
        $ok = Test-AppInstalled -App $App
    }

    return [pscustomobject]@{ Success = $ok; ExitCode = $code; WhatIf = $false }
}


# ------------------------------------------------------------------------------
#  Find-OfflineInstaller
#  Look through config.OfflineInstallerSearchPaths for a file matching a name
#  pattern (wildcards allowed, e.g. 'Obsidian-*.exe'). Returns the first full
#  path found, or $null.
# ------------------------------------------------------------------------------
function Find-OfflineInstaller {
    param([string] $Pattern)

    if ([string]::IsNullOrWhiteSpace($Pattern)) { return $null }

    foreach ($searchPath in $global:NWAS.Config.OfflineInstallerSearchPaths) {
        $dir = Expand-ConfigPath $searchPath
        if (-not (Test-Path $dir)) { continue }

        $match = Get-ChildItem -LiteralPath $dir -Filter $Pattern -File -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if ($match) { return $match.FullName }
    }
    return $null
}


# ------------------------------------------------------------------------------
#  Add-Fallback / Start-FallbackInstallers
#  During the app stage, every app whose winget install failed gets its offline
#  installer queued here. At the end of the stage Start-FallbackInstallers
#  launches them ALL AT ONCE with their normal GUIs (no -Wait, no silent flags)
#  so you can click through them yourself - the deliberately safe fallback.
# ------------------------------------------------------------------------------
function Add-Fallback {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $AppName
    )
    [void] $global:NWAS.FallbackQueue.Add([pscustomobject]@{ Path = $Path; App = $AppName })
}

function Start-FallbackInstallers {
    if ($global:NWAS.FallbackQueue.Count -eq 0) {
        Write-Log 'No offline fallback installers needed.' 'Info'
        return
    }

    Write-Log ('Launching {0} offline installer GUI(s) in parallel - work through them yourself:' -f `
               $global:NWAS.FallbackQueue.Count) 'Head'

    foreach ($item in $global:NWAS.FallbackQueue) {
        $leaf = Split-Path $item.Path -Leaf
        Write-Log ('  {0}   ({1})' -f $leaf, $item.App) 'Info'

        if ($global:NWAS.NoExecute) {
            Write-Log '  WHATIF  would Start-Process the file above' 'WhatIf'
            continue
        }

        try {
            if ($item.Path -match '\.msi$') {
                # .msi files are opened by Windows Installer, not run directly.
                Start-Process 'msiexec.exe' -ArgumentList @('/i', ('"{0}"' -f $item.Path))
            }
            else {
                Start-Process -FilePath $item.Path
            }
        }
        catch {
            Write-Log ('  could not launch {0}: {1}' -f $leaf, $_.Exception.Message) 'Warn'
        }
    }
}


# ------------------------------------------------------------------------------
#  Small state helpers - just tidy ways to append to the shared lists.
# ------------------------------------------------------------------------------
function Add-Result {
    param(
        [Parameter(Mandatory)][string] $Stage,
        [Parameter(Mandatory)][string] $Item,
        [Parameter(Mandatory)][ValidateSet('Installed', 'Skipped', 'Failed', 'Manual', 'Done')]
        [string] $Status,
        [string] $Detail = ''
    )
    [void] $global:NWAS.Results.Add(
        [pscustomobject]@{ Stage = $Stage; Item = $Item; Status = $Status; Detail = $Detail }
    )
}

function Add-ManualInstall {
    param([Parameter(Mandatory)][string] $Text)
    [void] $global:NWAS.ManualInstall.Add($Text)
}

function Add-NeedsSignin {
    param([Parameter(Mandatory)][string] $Text)
    [void] $global:NWAS.NeedsSignin.Add($Text)
}

function Set-RebootNeeded {
    param([string] $Reason)
    $global:NWAS.RebootNeeded = $true
    if ($Reason) { [void] $global:NWAS.RebootReasons.Add($Reason) }
}


# ------------------------------------------------------------------------------
#  Set-RegistryValue
#  Create the key path if missing, then set one value. Wrapped in Invoke-Change
#  so it is a no-op (just logged) in DryRun/TestRun.
#  -Type is a normal registry type name: String, ExpandString, DWord, Binary ...
# ------------------------------------------------------------------------------
function Set-RegistryValue {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)]         $Value,
        [Parameter(Mandatory)][ValidateSet('String', 'ExpandString', 'DWord', 'QWord', 'Binary', 'MultiString')]
        [string] $Type
    )

    # Pretty-print the value for the log: bytes as hex, everything else as-is.
    if ($Type -eq 'Binary') {
        $shown = ($Value | ForEach-Object { $_.ToString('X2') }) -join ' '
    }
    else {
        $shown = ($Value -join ' ')
    }

    Invoke-Change ("registry: {0}\{1} = {2}" -f $Path, $Name, $shown) {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    }
}


# ------------------------------------------------------------------------------
#  Get-StartupEntries
#  List every "runs at logon" entry Windows shows in Settings > Apps > Startup:
#     * HKCU / HKLM  ...\CurrentVersion\Run   (and the 32-bit WOW6432Node one)
#     * the per-user and all-users Startup folders
#  Each result has: Kind ('Run'/'Folder'), Scope, Location, Approved (the
#  registry key that stores the on/off flag), Name, Command, Enabled (bool).
#
#  The on/off flag lives under ...\Explorer\StartupApproved\... as a 12-byte
#  binary value; byte 0 has bit 0 CLEAR when enabled (0x02) and SET when
#  disabled (0x03). That is exactly the flag the Settings toggle flips.
# ------------------------------------------------------------------------------
function Get-StartupEntries {
    $entries = New-Object System.Collections.Generic.List[object]

    $runSources = @(
        @{ Scope = 'HKCU'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
           Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
        @{ Scope = 'HKLM'; Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
           Approved = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
        @{ Scope = 'HKLM'; Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
           Approved = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
    )

    foreach ($src in $runSources) {
        if (-not (Test-Path $src.Path)) { continue }
        $props = Get-ItemProperty -Path $src.Path
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -like 'PS*') { continue }   # skip PowerShell's own metadata props

            $enabled = $true
            if (Test-Path $src.Approved) {
                $flag = (Get-ItemProperty -Path $src.Approved -Name $p.Name -ErrorAction SilentlyContinue).$($p.Name)
                if ($flag -and $flag.Length -ge 1 -and (($flag[0] -band 1) -eq 1)) { $enabled = $false }
            }

            $entries.Add([pscustomobject]@{
                Kind = 'Run'; Scope = $src.Scope; Location = $src.Path; Approved = $src.Approved
                Name = $p.Name; Command = [string]$p.Value; Enabled = $enabled
            })
        }
    }

    $folderSources = @(
        @{ Scope = 'HKCU'; Path = [Environment]::GetFolderPath('Startup') }
        @{ Scope = 'HKLM'; Path = [Environment]::GetFolderPath('CommonStartup') }
    )
    $folderApproved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'

    foreach ($src in $folderSources) {
        if (-not $src.Path -or -not (Test-Path $src.Path)) { continue }
        Get-ChildItem -LiteralPath $src.Path -File -ErrorAction SilentlyContinue | ForEach-Object {
            $enabled = $true
            if (Test-Path $folderApproved) {
                $flag = (Get-ItemProperty -Path $folderApproved -Name $_.Name -ErrorAction SilentlyContinue).$($_.Name)
                if ($flag -and $flag.Length -ge 1 -and (($flag[0] -band 1) -eq 1)) { $enabled = $false }
            }
            $entries.Add([pscustomobject]@{
                Kind = 'Folder'; Scope = $src.Scope; Location = $src.Path; Approved = $folderApproved
                Name = $_.Name; Command = $_.FullName; Enabled = $enabled
            })
        }
    }

    return $entries
}
