<#
.SYNOPSIS
    One-shot setup for a fresh Windows install: install apps, WSL2, Office,
    activate Windows/Office (massgrave), un-hijack OneDrive folders, open the
    debloat tool, remap keys + AutoHotkey, and set the wallpaper.

.DESCRIPTION
    Run this from an ordinary account. It re-launches itself "as administrator"
    (a single UAC prompt) and then works through the stages in .\tasks\ in
    order. What runs is controlled by .\config.psd1 (edit that first).

    Everything printed is also written to  setup_<timestamp>.log  in this folder.

.PARAMETER Task
    Run only the named stage(s) instead of obeying the toggles in config.psd1.
    Names: prereqs apps wsl vscode office activation onedrive debloat keyboard wallpaper
    Example:  .\setup.ps1 -Task apps,wallpaper

.PARAMETER DryRun
    Change nothing and download nothing. Every action is printed as
    "-- WHATIF ...". Use this to read what a real run would do.

.PARAMETER TestRun
    Exercise the download/URL/fallback logic for real, into a temporary folder
    that is deleted at the end, but execute no installer, activation, registry
    write or wallpaper change. Proves the plumbing without touching the machine.

.PARAMETER KeepTestArtifacts
    With -TestRun, keep the temporary download folder instead of deleting it.

.PARAMETER List
    Print the stages and whether each one is enabled, then exit.

.EXAMPLE
    .\setup.ps1
    Full run, obeying config.psd1.

.EXAMPLE
    .\setup.ps1 -DryRun
    Show what a full run would do; make no changes.

.EXAMPLE
    .\setup.ps1 -Task onedrive,wallpaper
    Just re-point the user folders and set the wallpaper.
#>

[CmdletBinding()]
param(
    [string[]] $Task,
    [switch]   $DryRun,
    [switch]   $TestRun,
    [switch]   $KeepTestArtifacts,
    [switch]   $List
)

# Stop on the first unhandled error inside setup.ps1 itself; individual tasks
# catch their own errors so one bad stage does not abort the whole run.
$ErrorActionPreference = 'Stop'

# The folder this script lives in = the project root. $PSScriptRoot is filled in
# automatically by PowerShell.
$Root = $PSScriptRoot


# ==============================================================================
#  0.  Sanity checks on the parameters
# ==============================================================================
if ($DryRun -and $TestRun) {
    throw '-DryRun and -TestRun cannot be used together. Pick one.'
}

# Accept -Task in any of these forms and end up with a clean list:
#     -Task apps,wallpaper      (one comma string - how powershell.exe -File passes it)
#     -Task apps wallpaper      (two array elements)
#     -Task apps -Task wallpaper
if ($Task) {
    $Task = $Task |
        ForEach-Object { $_ -split ',' } |
        ForEach-Object { $_.Trim() } |
        Where-Object   { $_ -ne '' }
}

# Map: short stage name  ->  the config.psd1 toggle that enables it.
# 'prereqs' has no toggle - it always runs first (it just checks winget).
$StageToggle = [ordered]@{
    prereqs    = $null
    apps       = 'InstallApps'
    wsl        = 'InstallWSL'
    vscode     = 'ConfigureVSCode'
    office     = 'InstallOffice'
    activation = 'Activate'
    onedrive   = 'FixOneDrive'
    debloat    = 'RunDebloat'
    keyboard   = 'ConfigureKeyboard'
    wallpaper  = 'SetWallpaper'
    taskbar    = 'ConfigureTaskbar'
    startup    = 'ManageStartup'
}

if ($Task) {
    $unknown = $Task | Where-Object { $StageToggle.Keys -notcontains $_ }
    if ($unknown) {
        throw ("Unknown -Task value(s): {0}. Valid: {1}" -f ($unknown -join ', '), ($StageToggle.Keys -join ' '))
    }
}


# ==============================================================================
#  1.  -List : just describe the stages and exit (no admin, no log)
# ==============================================================================
if ($List) {
    $cfg = Import-PowerShellDataFile (Join-Path $Root 'config.psd1')
    Write-Host ''
    Write-Host '  Stage        Enabled by (config.psd1)      Will run?' -ForegroundColor Cyan
    Write-Host '  -----        -------------------------      ---------' -ForegroundColor Cyan
    foreach ($name in $StageToggle.Keys) {
        $toggle = $StageToggle[$name]
        if ($null -eq $toggle) {
            $enabled = 'always'
            $will    = 'yes'
        }
        else {
            $enabled = $toggle
            $will    = if ($cfg[$toggle]) { 'yes' } else { 'no' }
        }
        Write-Host ('  {0,-12} {1,-30} {2}' -f $name, $enabled, $will)
    }
    Write-Host ''
    Write-Host '  Run a subset with:  .\setup.ps1 -Task apps,wallpaper' -ForegroundColor DarkGray
    Write-Host ''
    return
}


# ==============================================================================
#  2.  Elevate to administrator if we are not already
#      (skipped for -DryRun, which only reads state and changes nothing)
# ==============================================================================
function Test-IsAdminInline {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole(
        [System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $DryRun -and -not (Test-IsAdminInline)) {
    Write-Host 'Requesting administrator rights (one UAC prompt)...' -ForegroundColor Yellow

    # Rebuild the same command line for the elevated copy.
    $relaunch = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    if ($Task)              { $relaunch += @('-Task', ($Task -join ',')) }
    if ($TestRun)           { $relaunch += '-TestRun' }
    if ($KeepTestArtifacts) { $relaunch += '-KeepTestArtifacts' }

    $hostExe = (Get-Process -Id $PID).Path   # powershell.exe running this script
    Start-Process -FilePath $hostExe -Verb RunAs -ArgumentList $relaunch
    return
}


# ==============================================================================
#  3.  Build the shared state object  $global:NWAS  and start the log
# ==============================================================================
$mode = 'Normal'
if ($DryRun)  { $mode = 'DryRun' }
if ($TestRun) { $mode = 'TestRun' }

$tempDir = $null
if ($mode -eq 'TestRun') {
    $tempDir = Join-Path $env:TEMP ('nwas-testrun-{0}' -f (Get-Date -Format 'yyyy-MM-ddTHH-mm-ss'))
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
}

$logPath = Join-Path $Root ('setup_{0}.log' -f (Get-Date -Format 'yyyy-MM-ddTHH-mm-ss'))

$global:NWAS = [pscustomobject]@{
    Root          = $Root
    Config        = Import-PowerShellDataFile (Join-Path $Root 'config.psd1')
    Mode          = $mode
    NoExecute     = ($mode -ne 'Normal')                 # DryRun + TestRun: no machine changes
    NoDownload    = ($mode -eq 'DryRun')                 # DryRun only: no network
    TempDir       = $tempDir
    LogPath       = $logPath
    RebootNeeded  = $false
    RebootReasons = (New-Object System.Collections.Generic.List[string])
    ManualInstall = (New-Object System.Collections.Generic.List[string])
    NeedsSignin   = (New-Object System.Collections.Generic.List[string])
    Results       = (New-Object System.Collections.Generic.List[object])
    FallbackQueue = (New-Object System.Collections.Generic.List[object])
    StateDir            = (Join-Path $Root '.state')
    StartupBaselineFile = (Join-Path $Root '.state\startup-baseline.txt')
}

# Start-Transcript mirrors EVERYTHING below into the .log file, so the log is a
# character-for-character copy of the console.
Start-Transcript -Path $logPath -Force | Out-Null

# Load the helper functions (defines Write-Log, Invoke-Winget, ... into scope).
. (Join-Path $Root 'lib\common.ps1')

# ------------------------------------------------------------------------------
#  Snapshot the CURRENT startup entries the very first time we ever run, BEFORE
#  any stage adds more. tasks\90-startup.ps1 treats this snapshot (plus its
#  allow-list) as "what may stay enabled". Only written on a real (Normal) run.
# ------------------------------------------------------------------------------
if (-not (Test-Path $global:NWAS.StartupBaselineFile) -and $mode -eq 'Normal') {
    if (-not (Test-Path $global:NWAS.StateDir)) {
        New-Item -ItemType Directory -Force -Path $global:NWAS.StateDir | Out-Null
    }
    $snapshot = Get-StartupEntries | Where-Object { $_.Enabled } |
                ForEach-Object { '{0}|{1}|{2}' -f $_.Kind, $_.Location, $_.Name }
    Set-Content -Path $global:NWAS.StartupBaselineFile -Value $snapshot -Encoding utf8
    Write-Log ('Startup baseline saved ({0} entries): {1}' -f $snapshot.Count, $global:NWAS.StartupBaselineFile) 'Info'
}


# ==============================================================================
#  4.  Decide which stages to run
# ==============================================================================
if ($Task) {
    # Honour the explicit list, but always run prereqs first.
    $stagesToRun = @('prereqs') + ($Task | Where-Object { $_ -ne 'prereqs' })
}
else {
    $stagesToRun = foreach ($name in $StageToggle.Keys) {
        $toggle = $StageToggle[$name]
        if ($null -eq $toggle -or $global:NWAS.Config[$toggle]) { $name }
    }
}


# ==============================================================================
#  5.  Banner
# ==============================================================================
Write-Log '' 'Info'
Write-Log '==============================================================' 'Head'
Write-Log ' New Windows Auto Setup' 'Head'
Write-Log ('  mode      : {0}' -f $mode) 'Head'
Write-Log ('  stages    : {0}' -f ($stagesToRun -join ', ')) 'Head'
Write-Log ('  log file  : {0}' -f $logPath) 'Head'
if ($tempDir) { Write-Log ('  temp dir  : {0}' -f $tempDir) 'Head' }
Write-Log '==============================================================' 'Head'
Write-Log '' 'Info'

if ($mode -eq 'DryRun') {
    Write-Log 'DRY RUN - nothing will be downloaded or changed.' 'Warn'
}
elseif ($mode -eq 'TestRun') {
    Write-Log 'TEST RUN - downloads happen into the temp folder; nothing is executed or changed.' 'Warn'
}
Write-Log '' 'Info'


# ==============================================================================
#  6.  Run each stage, catching its errors so the run continues
# ==============================================================================
foreach ($stage in $stagesToRun) {
    $file = Get-ChildItem -LiteralPath (Join-Path $Root 'tasks') -Filter ('*-{0}.ps1' -f $stage) |
            Select-Object -First 1
    if (-not $file) {
        Write-Log ("No task file found for stage '{0}' - skipping." -f $stage) 'Warn'
        continue
    }

    Write-Log '' 'Info'
    Write-Log ('===== STAGE: {0}  ({1}) =====' -f $stage, $file.Name) 'Head'

    try {
        & $file.FullName
    }
    catch {
        Write-Log ("Stage '{0}' failed: {1}" -f $stage, $_.Exception.Message) 'Error'
        Write-Log ($_.ScriptStackTrace) 'Error'
        Add-Result -Stage $stage -Item '(stage)' -Status 'Failed' -Detail $_.Exception.Message
    }
}


# ==============================================================================
#  7.  Summary + the two reminder lists
# ==============================================================================
Write-Log '' 'Info'
Write-Log '==============================================================' 'Head'
Write-Log ' SUMMARY' 'Head'
Write-Log '==============================================================' 'Head'

if ($global:NWAS.Results.Count -gt 0) {
    # Group the per-item results by status for a compact readout.
    foreach ($grp in ($global:NWAS.Results | Group-Object Status | Sort-Object Name)) {
        Write-Log ('{0}:' -f $grp.Name.ToUpper()) 'Step'
        foreach ($r in $grp.Group) {
            $line = '   {0,-12} {1}' -f $r.Stage, $r.Item
            if ($r.Detail) { $line += '  --  ' + $r.Detail }
            Write-Log $line 'Info'
        }
    }
}
else {
    Write-Log 'No per-item results were recorded.' 'Info'
}

Write-Log '' 'Info'
Write-Log '--------------------------------------------------------------' 'Head'
Write-Log ' NEEDS MANUAL INSTALL  (do these yourself)' 'Head'
Write-Log '--------------------------------------------------------------' 'Head'
if ($global:NWAS.ManualInstall.Count -gt 0) {
    foreach ($m in $global:NWAS.ManualInstall) { Write-Log ('  * ' + $m) 'Warn' }
}
else {
    Write-Log '  (nothing - everything installed)' 'Good'
}

Write-Log '' 'Info'
Write-Log '--------------------------------------------------------------' 'Head'
Write-Log ' INSTALLED - STILL NEEDS SIGN-IN / SETUP' 'Head'
Write-Log '--------------------------------------------------------------' 'Head'
if ($global:NWAS.NeedsSignin.Count -gt 0) {
    foreach ($s in $global:NWAS.NeedsSignin) { Write-Log ('  * ' + $s) 'Info' }
}
else {
    Write-Log '  (nothing)' 'Good'
}

Write-Log '' 'Info'
if ($global:NWAS.RebootNeeded) {
    Write-Log 'REBOOT REQUIRED before some changes take effect:' 'Warn'
    foreach ($reason in ($global:NWAS.RebootReasons | Select-Object -Unique)) {
        Write-Log ('  - ' + $reason) 'Warn'
    }
}
else {
    Write-Log 'No reboot required.' 'Good'
}

Write-Log '' 'Info'
Write-Log ('Full log saved to: {0}' -f $logPath) 'Head'


# ==============================================================================
#  8.  TestRun cleanup
# ==============================================================================
if ($mode -eq 'TestRun' -and $tempDir -and (Test-Path $tempDir)) {
    if ($KeepTestArtifacts) {
        Write-Log ('Kept test download folder: {0}' -f $tempDir) 'Info'
    }
    else {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log ('Deleted test download folder: {0}' -f $tempDir) 'Info'
    }
}

Stop-Transcript | Out-Null
