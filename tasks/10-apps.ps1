# ==============================================================================
#  tasks\10-apps.ps1  --  install the app list from config.psd1
# ==============================================================================
#  For each app, in order:
#     1. ManualOnly app            -> add to the "install by hand" list, skip.
#     2. already installed         -> log SKIP, move on.
#     3. config.PreferOffline = $true and we have a local installer
#                                  -> queue that GUI installer, skip winget.
#     4. otherwise                 -> silent  winget install .
#           success + Interactive  -> still remind you to finish it by hand.
#           success + NeedsSignin  -> remind you to log in.
#           failure + local file   -> queue the GUI installer as a fallback.
#           failure + no file      -> add to the "install by hand" list.
#
#  Any queued GUI installers are launched ALL AT ONCE at the end of the stage
#  (see Start-FallbackInstallers in lib\common.ps1) for you to click through.
#
#  Run on its own with:   .\setup.ps1 -Task apps
# ==============================================================================

$apps = $global:NWAS.Config.Apps
Write-Log ("{0} apps in the list." -f $apps.Count) 'Info'

foreach ($app in $apps) {

    $name = $app.Name
    Write-Log '' 'Info'
    Write-Log ("---- {0} ----" -f $name) 'Step'

    # --- 1. ManualOnly -----------------------------------------------------
    if ($app.ManualOnly) {
        $msg = $name
        if ($app.Note) { $msg += '  --  ' + $app.Note }
        Add-ManualInstall $msg
        Add-Result -Stage 'apps' -Item $name -Status 'Manual' -Detail 'ManualOnly in config'
        Write-Log 'Marked for manual install (ManualOnly).' 'Warn'
        continue
    }

    # Kill any Store app-execution-alias stubs this app asks us to (e.g. python.exe)
    # - do it every run, whether the app installs, skips, or fails.
    if ($app.DisableAppExecutionAlias) {
        Remove-AppExecutionAlias -Name $app.DisableAppExecutionAlias
    }

    # --- 2. Already installed? -------------------------------------------
    if (Test-AppInstalled -App $app) {
        Add-Result -Stage 'apps' -Item $name -Status 'Skipped' -Detail 'already installed'
        Write-Log 'Already installed - skipping.' 'Good'
        continue
    }

    # Helper: locate this app's offline installer (may be $null).
    $offline = $null
    if ($app.Offline) { $offline = Find-OfflineInstaller $app.Offline }

    # --- 3. PreferOffline shortcut ------------------------------------------
    if ($global:NWAS.Config.PreferOffline -and $offline) {
        Add-Fallback -Path $offline -AppName $name
        Add-Result -Stage 'apps' -Item $name -Status 'Manual' -Detail ("offline GUI queued: " + (Split-Path $offline -Leaf))
        Write-Log ("PreferOffline: queued GUI installer {0}" -f (Split-Path $offline -Leaf)) 'Info'
        continue
    }

    # --- 4. winget install ------------------------------------------------
    if (-not $app.Id) {
        Write-Log 'No winget Id and not ManualOnly - nothing to do. Check config.psd1.' 'Warn'
        Add-Result -Stage 'apps' -Item $name -Status 'Failed' -Detail 'no Id in config'
        continue
    }

    $result = Invoke-Winget -App $app

    if ($result.Success) {
        Add-Result -Stage 'apps' -Item $name -Status 'Installed' -Detail ("exit {0}" -f $result.ExitCode)
        Write-Log 'Installed.' 'Good'

        if ($app.Interactive) {
            $msg = $name + '  --  ' + $(if ($app.Note) { $app.Note } else { 'finish the installer / sign-in by hand.' })
            Add-ManualInstall $msg
            Write-Log 'Attempted, but you still need to finish this one by hand (see reminders).' 'Warn'
        }
        elseif ($app.NeedsSignin -and $app.Note) {
            Add-NeedsSignin ($name + '  --  ' + $app.Note)
        }
        elseif ($app.NeedsSignin) {
            Add-NeedsSignin ($name + '  --  sign in.')
        }
        continue
    }

    # winget failed --------------------------------------------------------
    Write-Log ("winget install failed (exit {0})." -f $result.ExitCode) 'Warn'

    if ($offline) {
        Add-Fallback -Path $offline -AppName $name
        Add-Result -Stage 'apps' -Item $name -Status 'Failed' -Detail ("winget exit {0}; GUI fallback: {1}" -f $result.ExitCode, (Split-Path $offline -Leaf))
        $line = $name + '  --  winget failed; the offline installer ' + (Split-Path $offline -Leaf) + ' will open.'
        if ($app.Note) { $line += '  ' + $app.Note }
        Add-ManualInstall $line
    }
    else {
        Add-Result -Stage 'apps' -Item $name -Status 'Failed' -Detail ("winget exit {0}; no offline installer" -f $result.ExitCode)
        $line = $name + '  --  winget failed (exit ' + $result.ExitCode + ') and no offline installer was found.'
        if ($app.Note) { $line += '  ' + $app.Note }
        Add-ManualInstall $line
    }
}

Write-Log '' 'Info'
Write-Log '---- offline fallback installers ----' 'Step'
Start-FallbackInstallers
