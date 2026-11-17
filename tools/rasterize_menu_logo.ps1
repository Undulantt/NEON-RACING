# Preserve the supplied SVG; render its filters with Chromium instead of Godot's SVG importer.
$ErrorActionPreference = 'Stop'
$menuProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$menuEdgePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft/Edge/Application/msedge.exe'
if (-not (Test-Path -LiteralPath $menuEdgePath)) { throw 'Microsoft Edge is required only to regenerate this PNG.' }
$menuSvgPath = Join-Path $menuProjectRoot 'assets/ui/menu/logos/TITULO.svg'
$menuPngPath = Join-Path $menuProjectRoot 'assets/ui/menu/logos/TITULO.png'
$menuProfilePath = Join-Path $menuProjectRoot '.local/svg-render-profile'
$menuStarted = [DateTime]::UtcNow
& $menuEdgePath --headless --disable-gpu --no-first-run --hide-scrollbars --default-background-color=00000000 --force-device-scale-factor=2 --window-size=600,200 "--screenshot=$menuPngPath" "--user-data-dir=$menuProfilePath" ([System.Uri]$menuSvgPath).AbsoluteUri
# Edge's launcher can return before its headless child writes the file.
$menuDeadline = [DateTime]::UtcNow.AddSeconds(15)
do {
    if ((Test-Path -LiteralPath $menuPngPath) -and (Get-Item -LiteralPath $menuPngPath).LastWriteTimeUtc -ge $menuStarted) {
        Write-Output "Logo rendered: $menuPngPath"
        exit 0
    }
    Start-Sleep -Milliseconds 100
} while ([DateTime]::UtcNow -lt $menuDeadline)
throw 'The headless renderer did not update the logo PNG.'
