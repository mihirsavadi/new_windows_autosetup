# ==============================================================================
#  tasks\30-office.ps1  --  install Microsoft 365 Apps (Word/Excel/PowerPoint...)
# ==============================================================================
#  Two ways, chosen by config.psd1  ->  OfficeMethod :
#     'winget' : winget install --id Microsoft.Office
#                (simplest; installs "Microsoft 365 Apps", no choices)
#     'odt'    : install Microsoft's Office Deployment Tool, then run
#                   setup.exe /configure office\configuration.xml
#                Edit office\configuration.xml first to choose apps / channel.
#
#  Activation is a SEPARATE stage (tasks\40-activation.ps1 runs MAS /Ohook).
#
#  Run on its own with:   .\setup.ps1 -Task office
# ==============================================================================

# ---- Already installed? -------------------------------------------------------
$c2r = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
if (Test-Path $c2r) {
    $ids = (Get-ItemProperty $c2r -ErrorAction SilentlyContinue).ProductReleaseIds
    if ($ids) {
        Write-Log ("Office is already installed: {0}" -f $ids) 'Good'
        Add-Result -Stage 'office' -Item 'Office' -Status 'Skipped' -Detail $ids
        return
    }
}

$method = $global:NWAS.Config.OfficeMethod
Write-Log ("OfficeMethod = {0}" -f $method) 'Info'

# ---------------------------------------------------------------------------
#  Method 1: winget
# ---------------------------------------------------------------------------
if ($method -eq 'winget') {

    Write-Log 'winget install --id Microsoft.Office --silent' 'Info'

    if ($global:NWAS.NoExecute) {
        Write-Log 'WHATIF  would run the winget command above' 'WhatIf'
        Add-Result -Stage 'office' -Item 'Office' -Status 'Skipped' -Detail 'dry/test run'
        return
    }

    & winget install --id Microsoft.Office --exact --silent `
        --accept-package-agreements --accept-source-agreements --disable-interactivity
    $code = $LASTEXITCODE

    if ($code -eq 0 -or (Test-Path $c2r)) {
        Add-Result -Stage 'office' -Item 'Office' -Status 'Installed' -Detail ("winget exit {0}" -f $code)
        Write-Log 'Microsoft 365 Apps installed.' 'Good'
    }
    else {
        Add-Result -Stage 'office' -Item 'Office' -Status 'Failed' -Detail ("winget exit {0}" -f $code)
        Add-ManualInstall ("Microsoft 365 Apps  --  winget failed (exit {0}). Install from https://office.com or use OfficeMethod = 'odt'." -f $code)
        Write-Log 'Office install failed.' 'Error'
    }
    return
}

# ---------------------------------------------------------------------------
#  Method 2: Office Deployment Tool (ODT)
# ---------------------------------------------------------------------------
if ($method -eq 'odt') {

    $xml = Join-Path $global:NWAS.Root 'office\configuration.xml'
    if (-not (Test-Path $xml)) {
        Write-Log ("Missing {0}" -f $xml) 'Error'
        Add-Result -Stage 'office' -Item 'Office' -Status 'Failed' -Detail 'configuration.xml missing'
        return
    }

    # Get the ODT (provides setup.exe) via winget.
    Invoke-Change 'winget install Microsoft.OfficeDeploymentTool' {
        & winget install --id Microsoft.OfficeDeploymentTool --exact --silent `
            --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
    }

    # Locate setup.exe that the ODT dropped.
    $setup = $null
    foreach ($p in @(
        (Join-Path $env:ProgramFiles       'OfficeDeploymentTool\setup.exe'),
        (Join-Path $env:ProgramFiles       'Microsoft Office Deployment Tool\setup.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'OfficeDeploymentTool\setup.exe')
    )) {
        if ($p -and (Test-Path $p)) { $setup = $p; break }
    }
    if (-not $setup) {
        $setup = (Get-Command setup.exe -ErrorAction SilentlyContinue).Source
    }

    if (-not $setup) {
        Write-Log 'Could not find the ODT setup.exe. Install the "Office Deployment Tool" and re-run  .\setup.ps1 -Task office' 'Error'
        Add-Result -Stage 'office' -Item 'Office' -Status 'Failed' -Detail 'ODT setup.exe not found'
        return
    }

    Write-Log ("Using ODT: {0}" -f $setup) 'Info'
    Invoke-Change ("{0} /configure {1}" -f $setup, $xml) {
        & $setup /configure $xml
    }

    if (Test-Path $c2r) {
        Add-Result -Stage 'office' -Item 'Office' -Status 'Installed' -Detail 'via ODT'
        Write-Log 'Office installed via ODT.' 'Good'
    }
    else {
        Add-Result -Stage 'office' -Item 'Office' -Status 'Failed' -Detail 'ODT ran but Office not detected'
        Write-Log 'ODT ran but Office was not detected - check the output above.' 'Warn'
    }
    return
}

Write-Log ("Unknown OfficeMethod '{0}' in config.psd1 (use 'winget' or 'odt')." -f $method) 'Error'
Add-Result -Stage 'office' -Item 'Office' -Status 'Failed' -Detail "bad OfficeMethod: $method"
