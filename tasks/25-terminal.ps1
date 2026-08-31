# ==============================================================================
#  tasks\25-terminal.ps1  --  make PowerShell 7 the default in Windows Terminal
# ==============================================================================
#  Windows Terminal picks its default tab from  "defaultProfile"  in its
#  settings.json. PowerShell 7's auto-generated profile always has the same
#  deterministic GUID:
#       {574e775e-4f2a-5b96-ac1e-a2962a402336}
#  so we just set defaultProfile to that.
#
#  settings.json is JSON-with-comments, which PowerShell 5.1's ConvertFrom-Json
#  cannot parse - so this does a targeted text edit (swap the existing value, or
#  insert the key after the opening brace) and leaves the rest of the file,
#  comments included, untouched. A timestamped .bak is written first.
#
#  Run on its own with:   .\setup.ps1 -Task terminal
# ==============================================================================

$pwshProfileGuid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'

# Note if PowerShell 7 is not actually present (its app entry may be disabled or
# have failed). WT will just fall back to its own default + show a hint.
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Write-Log 'pwsh not found yet - setting the default anyway; it takes effect once PowerShell 7 is installed.' 'Warn'
}

# Where Windows Terminal keeps settings.json (Store build, Preview, unpackaged).
$candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
)
$settingsPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $settingsPath) {
    # Terminal has not created its settings file yet. Seed the Store-build path
    # with a minimal file; WT merges it over its built-in defaults on first run.
    $settingsPath = $candidates[0]
    $seed = @"
{
    "`$help": "https://aka.ms/terminal-documentation",
    "`$schema": "https://aka.ms/terminal-profiles-schema",
    "defaultProfile": "$pwshProfileGuid"
}
"@
    Invoke-Change ("create Windows Terminal settings.json -> {0}" -f $settingsPath) {
        $dir = Split-Path $settingsPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Set-Content -Path $settingsPath -Value $seed -Encoding utf8
    }
    Add-Result -Stage 'terminal' -Item 'WT defaultProfile' -Status 'Installed' -Detail 'seeded settings.json'
    Write-Log 'Seeded Windows Terminal settings with PowerShell 7 as the default profile.' 'Good'
    return
}

Write-Log ("Windows Terminal settings: {0}" -f $settingsPath) 'Info'
$text = Get-Content -Path $settingsPath -Raw

$existing = [regex]::Match($text, '"defaultProfile"\s*:\s*"[^"]*"')
if ($existing.Success) {
    $current = [regex]::Match($existing.Value, '"([^"]*)"\s*$').Groups[1].Value
    if ($current -eq $pwshProfileGuid) {
        Write-Log 'defaultProfile is already PowerShell 7 - nothing to do.' 'Good'
        Add-Result -Stage 'terminal' -Item 'WT defaultProfile' -Status 'Skipped' -Detail 'already pwsh'
        return
    }
    $new = $text.Replace($existing.Value, '"defaultProfile": "' + $pwshProfileGuid + '"')
    $how = ("changed defaultProfile {0} -> {1}" -f $current, $pwshProfileGuid)
}
else {
    # No key yet - insert it right after the first "{".
    $brace = $text.IndexOf('{')
    if ($brace -lt 0) { throw "settings.json at $settingsPath does not look like JSON." }
    $insert = "`r`n" + '    "defaultProfile": "' + $pwshProfileGuid + '",'
    $new = $text.Substring(0, $brace + 1) + $insert + $text.Substring($brace + 1)
    $how = 'added defaultProfile key'
}

Invoke-Change ("update Windows Terminal settings.json  ({0})" -f $how) {
    $backup = "$settingsPath.bak-" + (Get-Date -Format 'yyyy-MM-ddTHH-mm-ss')
    Copy-Item -LiteralPath $settingsPath -Destination $backup -Force
    Set-Content -Path $settingsPath -Value $new -Encoding utf8 -NoNewline
    Write-Log ("backup: {0}" -f $backup) 'Info'
}

Add-Result -Stage 'terminal' -Item 'WT defaultProfile' -Status 'Done' -Detail $how
Write-Log 'PowerShell 7 is now the Windows Terminal default profile.' 'Good'
