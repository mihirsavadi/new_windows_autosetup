# ==============================================================================
#  tasks\20-vscode.ps1  --  restore VS Code extensions + settings
# ==============================================================================
#  This uses the two files captured from Mihir's current machine:
#     vscode\extensions.txt   one extension id per line
#     vscode\settings.json    a copy of %APPDATA%\Code\User\settings.json
#
#  It installs each extension, and copies settings.json ONLY if the target
#  machine does not already have one (so it never clobbers a newer file).
#  Signing in to Settings Sync afterwards is the real long-term mechanism and
#  cannot be scripted - it is added to the sign-in reminder list.
#
#  Run on its own with:   .\setup.ps1 -Task vscode
# ==============================================================================

# ---- Find the 'code' command -----------------------------------------------
$code = (Get-Command code -ErrorAction SilentlyContinue).Source
if (-not $code) {
    foreach ($candidate in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'),
        (Join-Path $env:ProgramFiles  'Microsoft VS Code\bin\code.cmd')
    )) {
        if (Test-Path $candidate) { $code = $candidate; break }
    }
}

if (-not $code) {
    Write-Log 'VS Code not found. Run the apps stage first (it installs it), then re-run:  .\setup.ps1 -Task vscode' 'Warn'
    Add-Result -Stage 'vscode' -Item 'VS Code' -Status 'Failed' -Detail 'code command not found'
    return
}
Write-Log ("Using: {0}" -f $code) 'Info'

# ---- Extensions -----------------------------------------------------------
$extFile = Join-Path $global:NWAS.Root 'vscode\extensions.txt'
if (Test-Path $extFile) {
    $wanted = Get-Content $extFile | Where-Object { $_.Trim() -ne '' }
    Write-Log ("{0} extensions listed in extensions.txt" -f $wanted.Count) 'Info'

    # What is already there? (lowercased for comparison)
    $installed = @()
    try { $installed = (& $code --list-extensions) | ForEach-Object { $_.ToLower() } } catch { }

    foreach ($ext in $wanted) {
        if ($installed -contains $ext.ToLower()) {
            Write-Log ("  present : {0}" -f $ext) 'Info'
            continue
        }
        Invoke-Change ("  install : {0}" -f $ext) {
            & $code --install-extension $ext --force | Out-Null
        }
    }
    Add-Result -Stage 'vscode' -Item 'extensions' -Status 'Done' -Detail ("{0} listed" -f $wanted.Count)
}
else {
    Write-Log 'vscode\extensions.txt not found - skipping extensions.' 'Warn'
}

# ---- settings.json ------------------------------------------------------
$srcSettings = Join-Path $global:NWAS.Root 'vscode\settings.json'
$dstSettings = Join-Path $env:APPDATA 'Code\User\settings.json'

if (Test-Path $srcSettings) {
    if (Test-Path $dstSettings) {
        Write-Log ("Target already has a settings.json - leaving it untouched. Reference copy: {0}" -f $srcSettings) 'Info'
        Add-Result -Stage 'vscode' -Item 'settings.json' -Status 'Skipped' -Detail 'target already had one'
    }
    else {
        Invoke-Change ("copy settings.json -> {0}" -f $dstSettings) {
            $dstDir = Split-Path $dstSettings -Parent
            if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
            Copy-Item -LiteralPath $srcSettings -Destination $dstSettings -Force
        }
        Add-Result -Stage 'vscode' -Item 'settings.json' -Status 'Installed' -Detail 'copied'
    }
}
else {
    Write-Log 'vscode\settings.json not found - skipping.' 'Warn'
}

Add-NeedsSignin 'VS Code: open the account menu (bottom-left) > "Backup and Sync Settings" and sign in, so settings/extensions stay in sync from here on.'
