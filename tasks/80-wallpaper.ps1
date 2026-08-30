# ==============================================================================
#  tasks\80-wallpaper.ps1  --  set the desktop wallpaper
# ==============================================================================
#  Steps:
#    1. copy the image out of this (Dropbox) folder to a stable local path
#       %USERPROFILE%\Pictures\<name>  so it still works if this folder moves.
#    2. write HKCU\Control Panel\Desktop  ->  WallPaper / WallpaperStyle / TileWallpaper
#    3. call the Win32 API SystemParametersInfo so it applies immediately,
#       without a sign-out.
#
#  Image + fit come from config.psd1  ->  WallpaperSource , WallpaperStyle .
#
#  Run on its own with:   .\setup.ps1 -Task wallpaper
# ==============================================================================

$cfg    = $global:NWAS.Config
$source = Expand-ConfigPath $cfg.WallpaperSource

if (-not (Test-Path $source)) {
    Write-Log ("Wallpaper image not found: {0}" -f $source) 'Warn'
    Write-Log 'Put your .jpg in the assets\ folder (or fix WallpaperSource in config.psd1).' 'Info'
    Add-Result -Stage 'wallpaper' -Item 'wallpaper' -Status 'Failed' -Detail 'source image missing'
    return
}

# ---- 1. copy to a stable location --------------------------------------------
$picsDir = Join-Path $env:USERPROFILE 'Pictures'
$dest    = Join-Path $picsDir (Split-Path $source -Leaf)

Invoke-Change ("copy wallpaper -> {0}" -f $dest) {
    if (-not (Test-Path $picsDir)) { New-Item -ItemType Directory -Force -Path $picsDir | Out-Null }
    Copy-Item -LiteralPath $source -Destination $dest -Force
}

# ---- 2. registry values ---------------------------------------------------
#  WallpaperStyle / TileWallpaper pairs Windows understands:
$styleMap = @{
    'Fill'    = @{ Style = '10'; Tile = '0' }
    'Fit'     = @{ Style = '6';  Tile = '0' }
    'Stretch' = @{ Style = '2';  Tile = '0' }
    'Tile'    = @{ Style = '0';  Tile = '1' }
    'Center'  = @{ Style = '0';  Tile = '0' }
    'Span'    = @{ Style = '22'; Tile = '0' }
}
$styleName = $cfg.WallpaperStyle
if (-not $styleMap.ContainsKey($styleName)) {
    Write-Log ("Unknown WallpaperStyle '{0}' - falling back to 'Fill'." -f $styleName) 'Warn'
    $styleName = 'Fill'
}
$style = $styleMap[$styleName]

Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaper'      -Value $dest         -Type String
Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value $style.Style  -Type String
Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'TileWallpaper'  -Value $style.Tile   -Type String

# ---- 3. apply immediately via Win32 -------------------------------------------
if ($global:NWAS.NoExecute) {
    Write-Log ("WHATIF  would call SystemParametersInfo to apply {0} ({1})" -f $dest, $styleName) 'WhatIf'
    Add-Result -Stage 'wallpaper' -Item 'wallpaper' -Status 'Skipped' -Detail 'dry/test run'
    return
}

# Define the P/Invoke signature once per PowerShell session.
if (-not ([System.Management.Automation.PSTypeName]'NWAS.Wallpaper').Type) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace NWAS {
    public static class Wallpaper {
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
        // 0x0014 = SPI_SETDESKWALLPAPER ; 0x01|0x02 = update INI + broadcast change
        public static void Set(string path) { SystemParametersInfo(0x0014, 0, path, 0x01 | 0x02); }
    }
}
'@
}

Write-Log ("applying wallpaper: {0}  ({1})" -f $dest, $styleName) 'Step'
[NWAS.Wallpaper]::Set($dest)

Add-Result -Stage 'wallpaper' -Item 'wallpaper' -Status 'Done' -Detail ("{0} ({1})" -f (Split-Path $dest -Leaf), $styleName)
