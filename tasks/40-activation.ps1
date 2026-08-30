# ==============================================================================
#  tasks\40-activation.ps1  --  activate Windows and Office with MAS
# ==============================================================================
#  MAS = "Microsoft Activation Scripts" from https://massgrave.dev  (open source).
#  Unattended form (from massgrave.dev/command_line_switches):
#
#     & ([ScriptBlock]::Create((irm https://get.activated.win))) /HWID /Ohook /S
#
#       /HWID   permanent Windows digital licence
#       /Ohook  Office activation
#       /S      silent (any switch => fully unattended)
#
#  config.psd1 controls this:
#     ActivateWindows / ActivateOffice   -> which switches are added
#     MasUrl                             -> the script URL
#     DefenderExclusionDuringActivation  -> add a TEMPORARY Defender exclusion
#                                           around this one step, removed after
#
#  DryRun  : fetch nothing, run nothing.
#  TestRun : download the MAS script to the temp folder to prove it is reachable,
#            but DO NOT run it.
#
#  Run on its own with:   .\setup.ps1 -Task activation
# ==============================================================================

$cfg = $global:NWAS.Config

# ---- Build the switch list ------------------------------------------------
$switches = @()
if ($cfg.ActivateWindows) { $switches += '/HWID' }
if ($cfg.ActivateOffice)  { $switches += '/Ohook' }

if ($switches.Count -eq 0) {
    Write-Log 'Both ActivateWindows and ActivateOffice are $false in config.psd1 - nothing to do.' 'Info'
    Add-Result -Stage 'activation' -Item 'MAS' -Status 'Skipped' -Detail 'no switches enabled'
    return
}
$switches += '/S'
Write-Log ("MAS switches: {0}" -f ($switches -join ' ')) 'Info'
Write-Log ("MAS URL     : {0}" -f $cfg.MasUrl) 'Info'

# ---- DryRun: stop here ------------------------------------------------------
if ($global:NWAS.Mode -eq 'DryRun') {
    Write-Log ("WHATIF  would run:  & ([ScriptBlock]::Create((irm {0}))) {1}" -f $cfg.MasUrl, ($switches -join ' ')) 'WhatIf'
    Add-Result -Stage 'activation' -Item 'MAS' -Status 'Skipped' -Detail 'dry run'
    return
}

# ---- TestRun: fetch only --------------------------------------------------
if ($global:NWAS.Mode -eq 'TestRun') {
    $probe = Get-RemoteFile -Url $cfg.MasUrl -OutFile (Join-Path $global:NWAS.TempDir 'MAS.cmd')
    if ($probe) {
        Write-Log 'MAS script is reachable. Not executing (test run).' 'Good'
        Add-Result -Stage 'activation' -Item 'MAS' -Status 'Done' -Detail 'reachable; not executed (test run)'
    }
    else {
        Add-Result -Stage 'activation' -Item 'MAS' -Status 'Failed' -Detail 'could not fetch MAS script'
    }
    return
}

# ---- Normal run --------------------------------------------------------
# Make sure a modern TLS is selected (harmless on Win 11, saves grief elsewhere).
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 } catch { }

$exclusions = @()
if ($cfg.DefenderExclusionDuringActivation) {
    $exclusions = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')) | Sort-Object -Unique
    foreach ($path in $exclusions) {
        try {
            Add-MpPreference -ExclusionPath $path -ErrorAction Stop
            Write-Log ("temporary Defender exclusion added: {0}" -f $path) 'Info'
        }
        catch {
            Write-Log ("could not add Defender exclusion for {0}: {1}" -f $path, $_.Exception.Message) 'Warn'
        }
    }
}

try {
    Write-Log 'Running MAS...' 'Step'
    $mas = Invoke-RestMethod -Uri $cfg.MasUrl -UseBasicParsing
    & ([ScriptBlock]::Create($mas)) @switches
    Write-Log ("MAS finished (exit {0})." -f $LASTEXITCODE) 'Info'
    Add-Result -Stage 'activation' -Item 'MAS' -Status 'Done' -Detail ($switches -join ' ')
}
catch {
    Write-Log ("MAS run failed: {0}" -f $_.Exception.Message) 'Error'
    Add-Result -Stage 'activation' -Item 'MAS' -Status 'Failed' -Detail $_.Exception.Message
}
finally {
    foreach ($path in $exclusions) {
        try {
            Remove-MpPreference -ExclusionPath $path -ErrorAction Stop
            Write-Log ("temporary Defender exclusion removed: {0}" -f $path) 'Info'
        }
        catch {
            Write-Log ("could not remove Defender exclusion for {0} - remove it by hand in Windows Security." -f $path) 'Warn'
        }
    }
}

# ---- Verify --------------------------------------------------------------
Write-Log '' 'Info'
Write-Log 'Windows licence status:' 'Step'
try { & cscript.exe //nologo (Join-Path $env:SystemRoot 'System32\slmgr.vbs') /xpr } catch { Write-Log $_.Exception.Message 'Warn' }

$osppPaths = @(
    (Join-Path $env:ProgramFiles       'Microsoft Office\Office16\ospp.vbs'),
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Office\Office16\ospp.vbs')
)
$ospp = $osppPaths | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if ($ospp) {
    Write-Log 'Office licence status:' 'Step'
    try { & cscript.exe //nologo $ospp /dstatus } catch { Write-Log $_.Exception.Message 'Warn' }
}
