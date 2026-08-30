# ==============================================================================
#  tasks\50-onedrive.ps1  --  stop OneDrive owning Desktop/Documents/Pictures/...
# ==============================================================================
#  Based on the Microsoft Q&A guide the user linked. OneDrive "Backup" repoints
#  the shell folders to  C:\Users\<you>\OneDrive\<folder> . This stage points
#  them back to the real  C:\Users\<you>\<folder>  by editing two registry keys:
#
#     HKCU\...\Explorer\User Shell Folders   (the live values, with %USERPROFILE%)
#     HKCU\...\Explorer\Shell Folders        (a cached copy, absolute paths)
#
#  It runs as YOU (setup.ps1 elevates as the same user, so HKCU is your hive).
#
#  Optional extras from config.psd1:
#     OneDriveMoveContent = $true  -> robocopy existing files out of OneDrive
#     UninstallOneDrive   = $true  -> uninstall OneDrive + hide its Explorer entry
#
#  A sign-out / reboot is needed for Explorer to pick up the new paths.
#
#  Run on its own with:   .\setup.ps1 -Task onedrive
# ==============================================================================

$cfg         = $global:NWAS.Config
$usf         = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
$sf          = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
# NOTE: do not use $userProfile here - that is a built-in PowerShell variable.
$userProfile = $env:USERPROFILE

# valueName (as it appears under User Shell Folders)  ->  subfolder under the profile
$folders = [ordered]@{
    'Desktop'                                  = 'Desktop'
    'Personal'                                 = 'Documents'
    'My Pictures'                              = 'Pictures'
    'My Music'                                 = 'Music'
    'My Video'                                 = 'Videos'
    '{374DE290-123F-4565-9164-39C4925E467B}'   = 'Downloads'
    'Favorites'                                = 'Favorites'
    # Modern KnownFolder GUID aliases that Windows also reads:
    '{754DE290-123F-4565-9164-39C4925E467B}'   = 'Documents'   # (legacy alias)
    '{F42EE2D3-909F-4907-8871-4C22FC0BF756}'   = 'Documents'
    '{0DDD015D-B06C-45D5-8C4C-F59713854639}'   = 'Pictures'
    '{35286A68-3C57-41A1-BBB1-0EAE73D76C95}'   = 'Videos'
    '{A0C69A99-21C8-4671-8703-7934162FCF1D}'   = 'Music'
    '{7D83EE9B-2244-4E70-B1F5-5393042AF1E4}'   = 'Downloads'
}

Write-Log 'Re-pointing the shell folders to the local profile...' 'Step'

foreach ($name in $folders.Keys) {
    $sub      = $folders[$name]
    $absolute = Join-Path $userProfile $sub
    $expand   = '%USERPROFILE%\' + $sub

    # Only touch a GUID-style value if it already exists (don't invent new ones).
    $isGuid = $name.StartsWith('{')
    $exists = $null -ne (Get-ItemProperty -Path $usf -Name $name -ErrorAction SilentlyContinue)
    if ($isGuid -and -not $exists) { continue }

    # Make sure the real folder exists.
    if (-not (Test-Path $absolute)) {
        Invoke-Change ("create folder {0}" -f $absolute) {
            New-Item -ItemType Directory -Force -Path $absolute | Out-Null
        }
    }

    Set-RegistryValue -Path $usf -Name $name -Value $expand   -Type ExpandString
    Set-RegistryValue -Path $sf  -Name $name -Value $absolute -Type String
}

# ---- Flag any leftover values still pointing into OneDrive -------------------
$leftover = @()
Get-Item $usf | Select-Object -ExpandProperty Property | ForEach-Object {
    $val = (Get-ItemProperty -Path $usf -Name $_).$_
    if ($val -match 'OneDrive') { $leftover += ('{0} = {1}' -f $_, $val) }
}
if ($leftover) {
    Write-Log 'These User Shell Folders values still mention OneDrive - check them by hand:' 'Warn'
    $leftover | ForEach-Object { Write-Log ('  ' + $_) 'Warn' }
}

Add-Result -Stage 'onedrive' -Item 'shell folders' -Status 'Done' -Detail 'repointed to %USERPROFILE%'
Set-RebootNeeded 'OneDrive folder re-redirection (sign out/in or reboot)'

# ---- Optional: move existing files out of OneDrive --------------------------
if ($cfg.OneDriveMoveContent -and $env:OneDrive -and (Test-Path $env:OneDrive)) {
    Write-Log ("Moving files out of {0} ..." -f $env:OneDrive) 'Step'
    foreach ($sub in @('Desktop', 'Documents', 'Pictures', 'Music', 'Videos', 'Downloads', 'Favorites')) {
        $from = Join-Path $env:OneDrive $sub
        $to   = Join-Path $userProfile $sub
        if (-not (Test-Path $from)) { continue }
        Invoke-Change ("robocopy {0} -> {1}  (/MOVE)" -f $from, $to) {
            & robocopy.exe $from $to /E /MOVE /XJ /R:1 /W:1 /NFL /NDL /NP | Out-Null
        }
    }
}
elseif ($cfg.OneDriveMoveContent) {
    Write-Log 'OneDriveMoveContent is on but no OneDrive folder was found - nothing to move.' 'Info'
}

# ---- Optional: uninstall OneDrive completely -------------------------------
if ($cfg.UninstallOneDrive) {
    Write-Log 'Removing OneDrive entirely...' 'Step'

    # 1. stop it running
    Invoke-Change 'stop OneDrive.exe' {
        Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    # 2. run the built-in uninstaller (path differs by Windows build)
    $odSetup = @(
        (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'),
        (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDriveSetup.exe')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($odSetup) {
        Invoke-Change ("{0} /uninstall" -f $odSetup) {
            Start-Process -FilePath $odSetup -ArgumentList '/uninstall' -Wait
        }
    }
    else {
        Write-Log 'OneDriveSetup.exe not found - it may already be gone.' 'Info'
    }

    # 3. stop it auto-starting (per-user and per-machine Run entries)
    Invoke-Change 'remove OneDrive Run entries' {
        Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'  -Name 'OneDrive' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'  -Name 'OneDrive' -ErrorAction SilentlyContinue
    }

    # 4. remove its scheduled tasks
    Invoke-Change 'delete OneDrive* scheduled tasks' {
        Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -like 'OneDrive*' } |
            Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
    }

    # 5. hide (both bitness) the "OneDrive" item in the Explorer navigation pane
    foreach ($clsid in @(
        'HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}',
        'HKCU:\Software\Classes\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
    )) {
        Set-RegistryValue -Path $clsid -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -Type DWord
    }

    # 6. delete leftover program folders (NOT any real user data - that was
    #    already moved/left in the local profile by the steps above)
    Invoke-Change 'delete OneDrive program folders' {
        foreach ($p in @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive'),
            (Join-Path $env:ProgramData  'Microsoft OneDrive'),
            (Join-Path $env:SystemDrive  'OneDriveTemp')
        )) {
            if (Test-Path $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    Add-Result -Stage 'onedrive' -Item 'OneDrive removal' -Status 'Done' -Detail 'uninstalled + tasks + sidebar + folders'
    Write-Log 'OneDrive removed. The empty C:\Users\<you>\OneDrive folder (if any) can be deleted by hand.' 'Good'
}

Write-Log 'Done. Sign out and back in (or reboot) for Explorer to use the new folder paths.' 'Good'

