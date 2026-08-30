# ==============================================================================
#  tasks\00-prereqs.ps1  --  make sure winget is usable before anything else
# ==============================================================================
#  This stage always runs first. It does not install anything itself; it just
#  checks that the Windows Package Manager (winget) is present and refreshes its
#  sources so the later stages do not each hit a first-run agreement prompt.
#
#  Run on its own with:   .\setup.ps1 -Task prereqs
# ==============================================================================

Write-Log 'Checking for winget (Windows Package Manager)...' 'Step'

$winget = Get-Command winget -ErrorAction SilentlyContinue

if (-not $winget) {
    Write-Log 'winget was not found on this machine.' 'Error'
    Write-Log 'Fix it, then re-run setup.ps1:' 'Info'
    Write-Log '  1. Open the Microsoft Store.' 'Info'
    Write-Log '  2. Search for "App Installer" and install / update it.' 'Info'
    Write-Log '     (or:  https://aka.ms/getwinget )' 'Info'
    Write-Log '  3. Close and reopen your terminal so PATH refreshes.' 'Info'
    Add-Result -Stage 'prereqs' -Item 'winget' -Status 'Failed' -Detail 'not installed'
    return
}

# Show the version so it is captured in the log.
$version = (& winget --version) 2>$null
Write-Log ("winget found: {0}  ({1})" -f $winget.Source, $version) 'Good'

# Accept the source agreements once and refresh the package index. These are
# read-only-ish maintenance actions, but still gate them on the run mode.
Invoke-Change 'winget: accept source agreements + update sources' {
    & winget source update --accept-source-agreements | Out-Null
}

Add-Result -Stage 'prereqs' -Item 'winget' -Status 'Done' -Detail $version
