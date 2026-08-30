<#
.SYNOPSIS
    Refresh the offline fallback installers in ..\installers\ with whatever
    winget would fetch right now, then let you commit the updated copies.

.DESCRIPTION
    For every app in config.psd1 that has an 'Offline' filename, this runs
        winget download --id <Id> ...
    (the same installer + manifest winget would use for a real install), and
    replaces the matching file in ..\installers\ if the content changed.

    Run this occasionally on your normal machine - NOT as part of a fresh-machine
    setup. setup.ps1 never calls it: on a new box you want the setup to be quick
    and you would not want a dirty git tree there. Here you refresh, eyeball
    `git status`, and commit the new LFS blobs.

.PARAMETER Only
    Only refresh these app keys (as in config.psd1), e.g. -Only handy,logioptions

.PARAMETER WhatIf
    Show what would change; download to a temp folder but do not touch installers\.

.EXAMPLE
    .\tools\refresh-installers.ps1
.EXAMPLE
    .\tools\refresh-installers.ps1 -Only logioptions -WhatIf
#>

[CmdletBinding()]
param(
    [string[]] $Only,
    [switch]   $WhatIf
)

$ErrorActionPreference = 'Stop'

# Accept -Only in any form: "a,b"  |  a b  |  -Only a -Only b
if ($Only) {
    $Only = $Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

# Paths ----------------------------------------------------------------------
$root         = Split-Path $PSScriptRoot -Parent          # ...\new_windows_autosetup
$installers   = Join-Path $root 'installers'
$configPath   = Join-Path $root 'config.psd1'
$stamp        = Get-Date -Format 'yyyy-MM-ddTHH-mm-ss'
$temp         = Join-Path $env:TEMP ("nwas-refresh-{0}" -f $stamp)

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found on PATH.'
}
New-Item -ItemType Directory -Force -Path $temp | Out-Null

# @(...) keeps this an array even when the filter leaves a single item, so
# $apps.Count is the item count (not a lone hashtable's key count).
$cfg  = Import-PowerShellDataFile $configPath
$apps = @($cfg.Apps | Where-Object { $_.Offline })
if ($Only) { $apps = @($apps | Where-Object { $Only -contains $_.Key }) }

Write-Host ("Refreshing {0} offline installer(s)  (mode: {1})" -f $apps.Count, ($(if($WhatIf){'WhatIf'}else{'apply'}))) -ForegroundColor Cyan
Write-Host ("temp: {0}" -f $temp) -ForegroundColor DarkGray
Write-Host ''

$updated   = New-Object System.Collections.Generic.List[string]
$unchanged = New-Object System.Collections.Generic.List[string]
$failed    = New-Object System.Collections.Generic.List[string]

function Get-Sha256 { param($Path) (Get-FileHash -Path $Path -Algorithm SHA256).Hash }

foreach ($app in $apps) {

    Write-Host ("---- {0}  ({1}) ----" -f $app.Name, $app.Id) -ForegroundColor White

    $destName = $app.Offline
    if ($destName -match '[\*\?]') {
        Write-Host ("  SKIP  Offline is a wildcard ('{0}') - give it a fixed filename to make it refreshable." -f $destName) -ForegroundColor Yellow
        $failed.Add($app.Key); continue
    }
    $destPath = Join-Path $installers $destName

    # --- winget download ---------------------------------------------------
    $sub  = Join-Path $temp $app.Key
    New-Item -ItemType Directory -Force -Path $sub | Out-Null

    if ($app.Source -eq 'msstore') {
        Write-Host '  SKIP  msstore packages cannot be downloaded with winget.' -ForegroundColor Yellow
        $failed.Add($app.Key); continue
    }

    $dlArgs = @('download', '--id', $app.Id, '--exact',
                '--download-directory', $sub,
                '--accept-package-agreements', '--accept-source-agreements',
                '--disable-interactivity')
    if ($app.Scope)  { $dlArgs += @('--scope', $app.Scope) }
    if ($app.Source) { $dlArgs += @('--source', $app.Source) }

    Write-Host ("  winget {0}" -f ($dlArgs -join ' ')) -ForegroundColor DarkGray
    $out = & winget @dlArgs 2>&1
    $out | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    # winget download drops the installer + a .yaml manifest; take the installer.
    $new = Get-ChildItem -Path $sub -File |
           Where-Object { $_.Extension -notin '.yaml', '.txt' } |
           Sort-Object Length -Descending | Select-Object -First 1
    if (-not $new) {
        Write-Host '  FAIL  no installer file produced.' -ForegroundColor Red
        $failed.Add($app.Key); continue
    }

    # --- compare & replace ------------------------------------------------
    $newHash = Get-Sha256 $new.FullName
    $newExt  = $new.Extension
    $dstExt  = [System.IO.Path]::GetExtension($destName)

    if ($newExt -ne $dstExt) {
        Write-Host ("  NOTE  winget produced a {0} but config.Offline expects {1}. Update config.psd1 Offline to end in {0}." -f $newExt, $dstExt) -ForegroundColor Yellow
    }

    if (Test-Path $destPath) {
        $oldHash = Get-Sha256 $destPath
        if ($oldHash -eq $newHash) {
            Write-Host ("  up to date  ({0:N1} MB, sha256 {1}...)" -f ($new.Length/1MB), $newHash.Substring(0,12)) -ForegroundColor Green
            $unchanged.Add($app.Key); continue
        }
        Write-Host ("  CHANGED  {0}  ->  {1}   ({2:N1} MB)" -f $oldHash.Substring(0,12), $newHash.Substring(0,12), ($new.Length/1MB)) -ForegroundColor Yellow
    }
    else {
        Write-Host ("  NEW  {0}  ({1:N1} MB)" -f $destName, ($new.Length/1MB)) -ForegroundColor Yellow
    }

    if ($WhatIf) {
        Write-Host '  WHATIF  would replace the file in installers\' -ForegroundColor DarkGray
        $updated.Add($app.Key); continue
    }

    Copy-Item -LiteralPath $new.FullName -Destination $destPath -Force
    Write-Host ("  wrote  {0}" -f $destPath) -ForegroundColor Green
    $updated.Add($app.Key)
}

# --- cleanup + summary --------------------------------------------------------
Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ("updated/changed : {0}" -f ($updated   -join ', '))
Write-Host ("unchanged       : {0}" -f ($unchanged -join ', '))
Write-Host ("failed/skipped  : {0}" -f ($failed    -join ', '))
Write-Host '=============================================' -ForegroundColor Cyan

if ($updated.Count -gt 0 -and -not $WhatIf) {
    Write-Host ''
    Write-Host 'Review and commit the refreshed installers:' -ForegroundColor White
    Write-Host ('  git -C "{0}" status installers' -f $root)
    Write-Host ('  git -C "{0}" add installers' -f $root)
    Write-Host ('  git -C "{0}" commit -m "refresh offline installers"' -f $root)
    Write-Host ('  git -C "{0}" push' -f $root)
    Write-Host '(the .exe/.msi files are Git LFS objects - see .gitattributes)' -ForegroundColor DarkGray
}
