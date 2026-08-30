# ==============================================================================
#  tasks\85-taskbar.ps1  --  taskbar + tray tweaks
# ==============================================================================
#  RELIABLE (plain per-user registry toggles, applied by restarting Explorer):
#     * remove the search box            SearchboxTaskbarMode = 0
#     * left-align the icons             TaskbarAl            = 0
#     * hide Task View / Widgets / Chat  ShowTaskViewButton / TaskbarDa / TaskbarMn = 0
#     * show battery percentage in tray  IsBatteryPercentageEnabled = 1
#
#  BEST-EFFORT (Microsoft broke scripted taskbar pinning on Win 11 24H2/25H2):
#     * write %LOCALAPPDATA%\Microsoft\Windows\Shell\LayoutModification.xml with
#       the pin order from config.TaskbarPins. This DOES take effect on a
#       brand-new profile's first sign-in; on an already-used profile it usually
#       does nothing, so the stage also prints the desired order as a reminder.
#
#  Run on its own with:   .\setup.ps1 -Task taskbar
# ==============================================================================

$cfg      = $global:NWAS.Config
$advanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$search   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'

# ---- 1. the reliable toggles --------------------------------------------------
if ($cfg.TaskbarRemoveSearch)   { Set-RegistryValue -Path $search   -Name 'SearchboxTaskbarMode'      -Value 0 -Type DWord }
if ($cfg.TaskbarLeftAlign)      { Set-RegistryValue -Path $advanced -Name 'TaskbarAl'                 -Value 0 -Type DWord }
if ($cfg.TaskbarHideTaskView)   { Set-RegistryValue -Path $advanced -Name 'ShowTaskViewButton'       -Value 0 -Type DWord }
if ($cfg.TaskbarHideWidgets)    { Set-RegistryValue -Path $advanced -Name 'TaskbarDa'                 -Value 0 -Type DWord }
if ($cfg.TaskbarHideChat)       { Set-RegistryValue -Path $advanced -Name 'TaskbarMn'                 -Value 0 -Type DWord }
if ($cfg.TaskbarBatteryPercent) { Set-RegistryValue -Path $advanced -Name 'IsBatteryPercentageEnabled' -Value 1 -Type DWord }

Add-Result -Stage 'taskbar' -Item 'tweaks' -Status 'Done' -Detail 'search/align/taskview/widgets/chat/battery %'

# ---- 2. best-effort pin layout ---------------------------------------------
$pins = @($cfg.TaskbarPins)
if ($pins.Count -gt 0) {

    # How to identify each app. 'link' = a .lnk path (vars expanded);
    # 'match' = name patterns to look up live via Get-StartApps.
    $known = @{
        explorer = @{ match = @('File Explorer'); link = '%APPDATA%\Microsoft\Windows\Start Menu\Programs\System Tools\File Explorer.lnk' }
        terminal = @{ match = @('Windows Terminal', 'Terminal') }
        brave    = @{ match = @('Brave') }
        spotify  = @{ match = @('Spotify') }
        whatsapp = @{ match = @('WhatsApp') }
        discord  = @{ match = @('Discord') }
        handy    = @{ match = @('Handy') }
        vscode   = @{ match = @('Visual Studio Code', 'VS Code') }
    }

    # One live lookup of every Start-menu app -> its AppUserModelID.
    $startApps = @()
    try { $startApps = Get-StartApps } catch { }

    $xmlItems = New-Object System.Collections.Generic.List[string]

    foreach ($key in $pins) {
        if (-not $known.ContainsKey($key)) {
            Write-Log ("  pin '{0}': no rule for this key - skipped" -f $key) 'Warn'
            continue
        }
        $rule = $known[$key]

        # (a) try to resolve a live AppUserModelID by name
        $hit = $null
        foreach ($pattern in @($rule.match)) {
            if (-not $pattern) { continue }
            $hit = $startApps | Where-Object { $_.Name -like "*$pattern*" } | Select-Object -First 1
            if ($hit) { break }
        }

        if ($hit) {
            Write-Log ("  pin '{0}': {1}  ->  {2}" -f $key, $hit.Name, $hit.AppID) 'Info'
            if ($hit.AppID -match '!') {
                # packaged app (Store) - AppUserModelID form
                $xmlItems.Add(('      <taskbar:UWA AppUserModelID="{0}" />' -f $hit.AppID))
            }
            else {
                $xmlItems.Add(('      <taskbar:DesktopApp DesktopApplicationID="{0}" />' -f $hit.AppID))
            }
            continue
        }

        # (b) fall back to a fixed .lnk path if the rule has one
        if ($rule.link) {
            Write-Log ("  pin '{0}': using link path {1}" -f $key, $rule.link) 'Info'
            $xmlItems.Add(('      <taskbar:DesktopApp DesktopApplicationLinkPath="{0}" />' -f $rule.link))
            continue
        }

        Write-Log ("  pin '{0}': not installed yet - re-run  .\setup.ps1 -Task taskbar  after installing it" -f $key) 'Warn'
    }

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
$($xmlItems -join "`r`n")
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@

    $layoutPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Shell\LayoutModification.xml'
    Invoke-Change ("write taskbar layout -> {0}" -f $layoutPath) {
        $dir = Split-Path $layoutPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Set-Content -Path $layoutPath -Value $xml -Encoding utf8
    }

    Add-NeedsSignin ("Taskbar pins: Windows may ignore the scripted layout on an existing profile. Desired order: " + ($pins -join ' , '))
    Add-Result -Stage 'taskbar' -Item 'pins' -Status 'Done' -Detail 'LayoutModification.xml written (best-effort)'
}

# ---- 3. apply -----------------------------------------------------------------
Invoke-Change 'restart Explorer to apply taskbar changes' {
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 1
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
}

Write-Log 'Taskbar tweaks applied (Explorer restarted).' 'Good'
