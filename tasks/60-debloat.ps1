# ==============================================================================
#  tasks\60-debloat.ps1  --  download Win11Debloat and OPEN its menu
# ==============================================================================
#  This deliberately does NOT remove anything automatically. It fetches Raphire's
#  well-known Win11Debloat project, unzips it into installers\Win11Debloat\, and
#  opens its interactive menu so YOU choose what to strip out.
#
#  DryRun  : download nothing.
#  TestRun : download + unzip into the temp folder; do not open the menu.
#
#  Run on its own with:   .\setup.ps1 -Task debloat
# ==============================================================================

$zipUrl  = 'https://github.com/Raphire/Win11Debloat/archive/refs/heads/master.zip'
$destDir  = Join-Path $global:NWAS.Root 'installers\Win11Debloat'
$zipOut   = Join-Path $destDir 'Win11Debloat.zip'

# In TestRun, Get-RemoteFile redirects the download into the temp folder itself.
$zip = Get-RemoteFile -Url $zipUrl -OutFile $zipOut
if (-not $zip) {
    Write-Log 'Nothing downloaded (dry run) - skipping the rest of this stage.' 'WhatIf'
    Add-Result -Stage 'debloat' -Item 'Win11Debloat' -Status 'Skipped' -Detail 'dry run'
    return
}

# TestRun: we proved the download works; do not unzip or open anything.
if ($global:NWAS.Mode -eq 'TestRun') {
    Write-Log 'Downloaded OK (test run) - not extracting or opening the menu.' 'Good'
    Add-Result -Stage 'debloat' -Item 'Win11Debloat' -Status 'Done' -Detail 'download reachable; not run (test run)'
    return
}

# Unzip next to the zip we just got.
$extractRoot = Split-Path $zip -Parent
Invoke-Change ("expand {0} -> {1}" -f (Split-Path $zip -Leaf), $extractRoot) {
    Expand-Archive -Path $zip -DestinationPath $extractRoot -Force
}

# The archive expands to a  Win11Debloat-master  subfolder.
$runBat = Get-ChildItem -Path $extractRoot -Recurse -Filter 'Run.bat' -ErrorAction SilentlyContinue |
          Select-Object -First 1

if (-not $runBat) {
    Write-Log 'Could not find Run.bat inside the download. Open the folder yourself:' 'Warn'
    Write-Log ('  ' + $extractRoot) 'Warn'
    Add-Result -Stage 'debloat' -Item 'Win11Debloat' -Status 'Failed' -Detail 'Run.bat not found'
    return
}

if ($global:NWAS.NoExecute) {
    Write-Log ("WHATIF  would open the folder and launch {0}" -f $runBat.FullName) 'WhatIf'
    Add-Result -Stage 'debloat' -Item 'Win11Debloat' -Status 'Done' -Detail 'downloaded; menu not opened (dry/test run)'
    return
}

Write-Log 'Opening Win11Debloat - pick the options you want in the menu it shows.' 'Step'
Invoke-Item (Split-Path $runBat.FullName -Parent)
Start-Process -FilePath $runBat.FullName

Add-Result -Stage 'debloat' -Item 'Win11Debloat' -Status 'Done' -Detail 'menu opened - choose options yourself'
