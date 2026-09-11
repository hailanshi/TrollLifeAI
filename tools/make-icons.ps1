# make-icons.ps1 -- generate app icons (opaque square PNG, no transparency)
# Output: ios-shell/TrollLifeApp/Resources/AppIcon60x60@2x.png (120x120)
#         ios-shell/TrollLifeApp/Resources/AppIcon60x60@3x.png (180x180)
# Usage:  powershell -ExecutionPolicy Bypass -File tools/make-icons.ps1
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$resDir = Join-Path $root 'ios-shell\TrollLifeApp\Resources'
New-Item -ItemType Directory -Force -Path $resDir | Out-Null

function New-TrollIcon {
    param([int]$Size, [string]$Path)

    # Format24bppRgb -> no alpha channel at all, icon is fully opaque (TrollStore requirement)
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    # dark background (#0D0F12)
    $bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 13, 15, 18))
    $g.FillRectangle($bg, 0, 0, $Size, $Size)

    # soft glow
    $glow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 22, 33, 30))
    $g.FillEllipse($glow, [int](-$Size * 0.35), [int](-$Size * 0.35), [int]($Size * 1.7), [int]($Size * 1.7))

    # green ring
    $penW = [float]($Size * 0.055)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 43, 140, 104)), $penW
    $pad = [int]($Size * 0.17)
    $g.DrawEllipse($pen, $pad, $pad, $Size - 2 * $pad, $Size - 2 * $pad)

    # inner thin ring
    $pen2 = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 127, 209, 174)), ([float]($Size * 0.018))
    $pad2 = [int]($Size * 0.255)
    $g.DrawEllipse($pen2, $pad2, $pad2, $Size - 2 * $pad2, $Size - 2 * $pad2)

    # "TL" text
    $fontSize = [float]($Size * 0.34)
    $font = New-Object System.Drawing.Font('Arial', $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 232, 245, 238))
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF(0, [float](-$Size * 0.02), [float]$Size, [float]$Size)
    $g.DrawString('TL', $font, $brush, $rect, $fmt)

    # three dots at the bottom
    $dotBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 107, 118, 132))
    $dotSize = [int]($Size * 0.035)
    for ($i = -1; $i -le 1; $i++) {
        $x = [int]($Size / 2 + $i * $dotSize * 2.4 - $dotSize / 2)
        $y = [int]($Size * 0.74)
        $g.FillEllipse($dotBrush, $x, $y, $dotSize, $dotSize)
    }

    $g.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host ("wrote " + $Path)
}

New-TrollIcon -Size 120 -Path (Join-Path $resDir 'AppIcon60x60@2x.png')
New-TrollIcon -Size 180 -Path (Join-Path $resDir 'AppIcon60x60@3x.png')
New-TrollIcon -Size 1024 -Path (Join-Path $resDir 'AppIcon-1024-preview.png')

Get-ChildItem $resDir -Filter 'AppIcon*.png' | ForEach-Object {
    $img = [System.Drawing.Image]::FromFile($_.FullName)
    Write-Host ("check {0}: {1}x{2} pixelFormat={3}" -f $_.Name, $img.Width, $img.Height, $img.PixelFormat.ToString())
    $img.Dispose()
}
