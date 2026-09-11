# shot.ps1 -- render the demo pages with headless Edge and save screenshots
# Usage: powershell -ExecutionPolicy Bypass -File tools/shot.ps1
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'build\shots'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$edge = @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $edge) { Write-Host "Edge not found, skip screenshots"; exit 0 }

$names = @(
    'narrow_start', 'narrow_home', 'narrow_actions', 'narrow_notch', 'narrow_relations', 'narrow_event',
    'narrow_ach', 'narrow_skill', 'narrow_god', 'narrow_ai', 'narrow_death'
)
foreach ($n in $names) {
    $html = Join-Path $root ("build\" + $n + ".html")
    if (-not (Test-Path $html)) { continue }
    $png = Join-Path $outDir ($n + ".png")
    $url = "file:///" + ($html -replace '\\', '/')
    & $edge --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files `
        --window-size=492,960 --screenshot="$png" --virtual-time-budget=8000 "$url" 2>$null | Out-Null
    Start-Sleep -Milliseconds 400
    if (Test-Path $png) {
        Write-Host ("shot " + $n + ".png  " + (Get-Item $png).Length + " bytes")
    } else {
        Write-Host ("shot failed: " + $n)
    }
}

# Also export the horizontal-overflow report for each scene
foreach ($n in $names) {
    $html = Join-Path $root ("build\" + $n + ".html")
    if (-not (Test-Path $html)) { continue }
    $url = "file:///" + ($html -replace '\\', '/')
    $domFile = Join-Path $outDir ($n + ".dom.html")
    & $edge --headless=new --disable-gpu --allow-file-access-from-files --window-size=492,960 `
        --virtual-time-budget=8000 --dump-dom "$url" 2>$null | Out-File -Encoding UTF8 $domFile
    $txt = Get-Content -Raw -Encoding UTF8 $domFile
    if ($txt -match 'data-narrow="([^"]*)"') {
        $rep = $Matches[1] -replace '&quot;', '"'
        Write-Host ("overflow " + $n + ": " + $rep)
    } else {
        Write-Host ("overflow " + $n + ": no report")
    }
}
