# ==============================================================================
#  tasks\15-wsl.ps1  --  install WSL2 and a Linux distro (default: Ubuntu 26.04)
# ==============================================================================
#  On an up-to-date Windows 11,  wsl --install  turns on the required Windows
#  features (Virtual Machine Platform, WSL), installs the WSL2 kernel, and can
#  install a distro in one go. We pass --no-launch so it does NOT drop you into
#  a Linux shell mid-setup; you finish the distro's first-run (create a UNIX
#  username + password) yourself after the reboot.
#
#  Distro name comes from config.psd1  ->  WSLDistro  (must match one that
#  `wsl --list --online` offers).
#
#  Run on its own with:   .\setup.ps1 -Task wsl
# ==============================================================================

$distro = $global:NWAS.Config.WSLDistro
Write-Log ("Target distro: {0}" -f $distro) 'Info'

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Log 'wsl.exe not found. This needs Windows 11 (it ships the WSL launcher). Skipping.' 'Error'
    Add-Result -Stage 'wsl' -Item 'wsl' -Status 'Failed' -Detail 'wsl.exe missing'
    return
}

# ---- Is the distro already installed? -----------------------------------------
#  `wsl -l -q` prints UTF-16 with stray NUL bytes; strip them before matching.
$already = $false
try {
    $listRaw  = (& wsl.exe --list --quiet) 2>$null
    $listClean = ($listRaw | ForEach-Object { $_ -replace "`0", '' }).Trim()
    if ($listClean -contains $distro) { $already = $true }
}
catch { }

if ($already) {
    Write-Log ("{0} is already installed." -f $distro) 'Good'
    Add-Result -Stage 'wsl' -Item $distro -Status 'Skipped' -Detail 'already installed'
    return
}

# ---- Install --------------------------------------------------------------
Invoke-Change ("wsl --install --no-launch  (enable WSL2 + kernel)") {
    & wsl.exe --install --no-launch
}
Invoke-Change ("wsl --install -d {0} --no-launch" -f $distro) {
    & wsl.exe --install -d $distro --no-launch
}
Invoke-Change 'wsl --set-default-version 2' {
    & wsl.exe --set-default-version 2 | Out-Null
}
Invoke-Change 'wsl --update  (refresh the WSL2 kernel)' {
    & wsl.exe --update | Out-Null
}

Add-Result -Stage 'wsl' -Item $distro -Status 'Installed' -Detail 'via wsl --install --no-launch'
Set-RebootNeeded 'WSL2 + Linux distro (Windows features were enabled)'
Add-NeedsSignin ("Ubuntu/WSL ({0}): after the reboot, run  wsl  once to create your UNIX username + password." -f $distro)

Write-Log 'WSL install commands issued. A reboot is required before first use.' 'Good'
