# ==============================================================================
#  tasks\90-startup.ps1  --  keep the "runs at logon" list clean
# ==============================================================================
#  setup.ps1 saved a snapshot of everything that was ALREADY enabled the first
#  time it ran, in  .state\startup-baseline.txt . This stage compares the
#  current startup list against that baseline:
#
#     * in the baseline            -> leave it alone (it was there before)
#     * matches config.StartupAllow -> leave it alone (Dropbox, Handy, ...)
#     * anything else, still enabled:
#           StartupPolicy = 'Enforce' -> flip it OFF (reversibly - it is the
#                                        exact flag Settings > Apps > Startup uses)
#           StartupPolicy = 'Remind'  -> just report it
#
#  Nothing is ever deleted. Re-enable anything from Settings > Apps > Startup,
#  or with:  .\setup.ps1 -Task startup   after editing StartupAllow.
#
#  Run on its own with:   .\setup.ps1 -Task startup
# ==============================================================================

$cfg      = $global:NWAS.Config
$policy   = $cfg.StartupPolicy
$allow    = @($cfg.StartupAllow)

# Always allow the AutoHotkey startup entries this toolkit creates itself
# (tasks\70-keyboard.ps1), so we never disable our own key-remap script.
foreach ($ahk in @($cfg.AhkScripts)) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($ahk)
    $allow += "$base*"      # e.g. ctrl_tab_remap_and_instructions*  (covers .ahk / .lnk / .exe)
}

# ---- baseline ---------------------------------------------------------------
$baseline = @()
if (Test-Path $global:NWAS.StartupBaselineFile) {
    $baseline = Get-Content $global:NWAS.StartupBaselineFile | Where-Object { $_.Trim() -ne '' }
    Write-Log ("Baseline: {0} entries (from {1})" -f $baseline.Count, $global:NWAS.StartupBaselineFile) 'Info'
}
else {
    # No baseline = we do not know what was "there before", so it is NOT safe to
    # disable anything. Downgrade to remind-only no matter what the policy says.
    Write-Log 'No startup baseline file yet (a real/Normal run creates it before any stage).' 'Warn'
    Write-Log 'Falling back to REMIND-ONLY for this run - nothing will be disabled.' 'Warn'
    $policy = 'Remind'
}

# ---- compare ----------------------------------------------------------------
$entries = Get-StartupEntries
Write-Log ("Current startup entries: {0}" -f $entries.Count) 'Info'
Write-Log '' 'Info'

$disabled = 0
foreach ($e in $entries) {
    $id = '{0}|{1}|{2}' -f $e.Kind, $e.Location, $e.Name

    $inBaseline = $baseline -contains $id
    $isAllowed  = $false
    foreach ($pat in $allow) { if ($e.Name -like $pat) { $isAllowed = $true; break } }

    $state = if ($e.Enabled) { 'ON ' } else { 'off' }

    if (-not $e.Enabled) {
        Write-Log ("  [{0}] {1,-40} (already off)" -f $state, $e.Name) 'Info'
        continue
    }
    if ($inBaseline) {
        Write-Log ("  [{0}] {1,-40} keep (was enabled before this script)" -f $state, $e.Name) 'Info'
        continue
    }
    if ($isAllowed) {
        Write-Log ("  [{0}] {1,-40} keep (matches StartupAllow)" -f $state, $e.Name) 'Good'
        continue
    }

    # This one appeared after the first run and is not allow-listed.
    if ($policy -eq 'Enforce') {
        Write-Log ("  [{0}] {1,-40} DISABLING  ({2})" -f $state, $e.Name, $e.Command) 'Warn'
        # 12-byte flag: byte 0 = 0x03 means "disabled" (0x02 = enabled).
        Set-RegistryValue -Path $e.Approved -Name $e.Name `
            -Value ([byte[]](3,0,0,0,0,0,0,0,0,0,0,0)) -Type Binary
        $disabled++
    }
    else {
        Write-Log ("  [{0}] {1,-40} would disable ({2})" -f $state, $e.Name, $e.Command) 'Warn'
    }
}

Write-Log '' 'Info'
if ($policy -eq 'Enforce') {
    Write-Log ("Disabled {0} startup entr(y/ies)." -f $disabled) 'Good'
    Add-Result -Stage 'startup' -Item 'startup entries' -Status 'Done' -Detail ("disabled {0}" -f $disabled)
}
else {
    Write-Log 'Remind-only mode - nothing changed.' 'Info'
    Add-Result -Stage 'startup' -Item 'startup entries' -Status 'Done' -Detail 'remind only'
}

Add-NeedsSignin ('Startup apps: open Settings > Apps > Startup and turn OFF anything that looks suspicious ' +
                 '(Brother adds several). Keep only what was enabled before this script plus Dropbox and Handy. ' +
                 'Re-run  .\setup.ps1 -Task startup  after any manual installs.')
