# ==============================================================================
#  tasks\70-keyboard.ps1  --  hardware key remap + AutoHotkey at logon
# ==============================================================================
#  PART A - the SharpKeys-style swap, done straight in the registry
#  ---------------------------------------------------------------
#  Windows reads one binary value:
#     HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout  ->  "Scancode Map"
#  Its layout:
#     bytes  0-3    header   : 00 00 00 00   (version, always zero)
#     bytes  4-7    header   : 00 00 00 00   (flags, always zero)
#     bytes  8-11   count    : (number-of-mappings + 1) as a little-endian DWORD
#     then, per mapping, 4 bytes:  <TO scancode><FROM scancode>   each a
#            little-endian 16-bit word
#     last 4 bytes  terminator: 00 00 00 00
#
#  A scancode in config.psd1 is written 'HI_LO' in hex, e.g.
#     '00_1D' -> word 0x001D -> bytes  1D 00      (Left Ctrl)
#     '00_38' -> word 0x0038 -> bytes  38 00      (Left Alt)
#     'E0_5B' -> word 0xE05B -> bytes  5B E0      (Left Win)
#
#  The default config swaps Left Alt <-> Left Ctrl, giving the 24-byte value:
#     00 00 00 00  00 00 00 00  03 00 00 00  1D 00 38 00  38 00 1D 00  00 00 00 00
#
#  Empty SharpKeysRemaps in config.psd1  ->  this part writes nothing.
#  Any change here needs a reboot.
#
#  PART B - AutoHotkey
#  -------------------
#  Each script in config.AhkScripts (found in .\ahk\) is launched now and set to
#  start at logon, using config.AhkStartupMethod ('Shortcut' or 'ScheduledTask').
#
#  Run on its own with:   .\setup.ps1 -Task keyboard
# ==============================================================================

$cfg = $global:NWAS.Config

# --------------------------------------------------------------------------
#  PART A - Scancode Map
# --------------------------------------------------------------------------
$remaps = @($cfg.SharpKeysRemaps)

if ($remaps.Count -eq 0) {
    Write-Log 'SharpKeysRemaps is empty - not writing a Scancode Map. (SharpKeys app is still installed for manual use.)' 'Info'
    Add-Result -Stage 'keyboard' -Item 'scancode map' -Status 'Skipped' -Detail 'no remaps configured'
}
else {
    # Turn 'HI_LO' into the two little-endian bytes  LO, HI .
    function Convert-Scancode {
        param([string] $Code)
        $parts = $Code -split '_'
        if ($parts.Count -ne 2) { throw "Bad scancode '$Code' - expected 'HI_LO' hex, e.g. '00_1D'." }
        $hi = [Convert]::ToByte($parts[0], 16)
        $lo = [Convert]::ToByte($parts[1], 16)
        return , @($lo, $hi)   # comma keeps it a 2-element array
    }

    $bytes = New-Object System.Collections.Generic.List[byte]
    0..7 | ForEach-Object { $bytes.Add(0) }              # 8 header bytes

    $count = $remaps.Count + 1                            # mappings + terminator
    $bytes.Add([byte]($count -band 0xFF))
    $bytes.Add([byte](($count -shr 8)  -band 0xFF))
    $bytes.Add([byte](($count -shr 16) -band 0xFF))
    $bytes.Add([byte](($count -shr 24) -band 0xFF))

    foreach ($m in $remaps) {
        $to   = Convert-Scancode $m.To      # what the key becomes
        $from = Convert-Scancode $m.From    # the physical key you press
        $bytes.Add($to[0]);   $bytes.Add($to[1])
        $bytes.Add($from[0]); $bytes.Add($from[1])
        Write-Log ("  remap  press {0}  ->  acts as {1}" -f $m.From, $m.To) 'Info'
    }

    0..3 | ForEach-Object { $bytes.Add(0) }              # 4 terminator bytes

    $blob = $bytes.ToArray()
    $hex  = ($blob | ForEach-Object { $_.ToString('X2') }) -join ' '
    Write-Log ("Scancode Map bytes: {0}" -f $hex) 'Info'

    Set-RegistryValue `
        -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout' `
        -Name 'Scancode Map' -Value $blob -Type Binary

    Add-Result -Stage 'keyboard' -Item 'scancode map' -Status 'Done' -Detail ("{0} remap(s)" -f $remaps.Count)
    Set-RebootNeeded 'keyboard Scancode Map remap'
}

# --------------------------------------------------------------------------
#  PART B - AutoHotkey
# --------------------------------------------------------------------------
$ahkScripts = @($cfg.AhkScripts)
if ($ahkScripts.Count -eq 0) {
    Write-Log 'No AhkScripts configured - skipping AutoHotkey wiring.' 'Info'
    return
}

# Find AutoHotkey v2's exe (the apps stage installs AutoHotkey.AutoHotkey).
$ahkExe = @(
    (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey.exe'),
    (Join-Path $env:ProgramFiles 'AutoHotkey\AutoHotkey.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'AutoHotkey\v2\AutoHotkey.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $ahkExe) {
    Write-Log 'AutoHotkey.exe not found. Run the apps stage first, then:  .\setup.ps1 -Task keyboard' 'Warn'
    Add-Result -Stage 'keyboard' -Item 'AutoHotkey' -Status 'Failed' -Detail 'AutoHotkey.exe not found'
    return
}
Write-Log ("AutoHotkey: {0}" -f $ahkExe) 'Info'

$startupDir = [Environment]::GetFolderPath('Startup')   # ...\Start Menu\Programs\Startup
$method     = $cfg.AhkStartupMethod

foreach ($scriptName in $ahkScripts) {
    $scriptPath = Join-Path $global:NWAS.Root ('ahk\' + $scriptName)
    if (-not (Test-Path $scriptPath)) {
        Write-Log ("AHK script not found: {0}" -f $scriptPath) 'Warn'
        continue
    }

    # 1. run it now
    Invoke-Change ("launch {0}" -f $scriptName) {
        Start-Process -FilePath $ahkExe -ArgumentList ('"{0}"' -f $scriptPath)
    }

    # 2. make it start at logon
    if ($method -eq 'ScheduledTask') {
        $taskName = 'NWAS AHK - ' + [IO.Path]::GetFileNameWithoutExtension($scriptName)
        Invoke-Change ("register logon task '{0}'" -f $taskName) {
            $action    = New-ScheduledTaskAction  -Execute $ahkExe -Argument ('"{0}"' -f $scriptPath)
            $trigger   = New-ScheduledTaskTrigger -AtLogOn
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
            $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
                -Principal $principal -Settings $settings -Force | Out-Null
        }
        Add-Result -Stage 'keyboard' -Item $scriptName -Status 'Done' -Detail "logon scheduled task"
    }
    else {
        # 'Shortcut' - a .lnk in the Startup folder
        $lnk = Join-Path $startupDir ([IO.Path]::GetFileNameWithoutExtension($scriptName) + '.lnk')
        Invoke-Change ("create startup shortcut {0}" -f $lnk) {
            $shell = New-Object -ComObject WScript.Shell
            $sc = $shell.CreateShortcut($lnk)
            $sc.TargetPath       = $ahkExe
            $sc.Arguments        = '"{0}"' -f $scriptPath
            $sc.WorkingDirectory = Split-Path $scriptPath -Parent
            $sc.Description       = 'Started by New Windows Auto Setup'
            $sc.Save()
        }
        Add-Result -Stage 'keyboard' -Item $scriptName -Status 'Done' -Detail "startup shortcut"
    }
}

Write-Log ("AutoHotkey scripts run from: {0}  (edit them there)." -f (Join-Path $global:NWAS.Root 'ahk')) 'Info'
