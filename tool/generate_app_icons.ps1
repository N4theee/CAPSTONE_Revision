param([string]$Source = 'assets/branding/app-logo.png')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$sourcePath = Join-Path $root $Source
$sourceImage = [Drawing.Bitmap]::new($sourcePath)
function Make-Icon([int]$size, [bool]$maskable = $false) {
  $bitmap = [Drawing.Bitmap]::new($size, $size, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  $graphics.Clear([Drawing.Color]::FromArgb(5, 24, 47))
  $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $inset = 0
  if ($maskable) { $inset = [int]($size * 0.15) }
  $graphics.DrawImage($sourceImage, $inset, $inset, ($size - 2*$inset), ($size - 2*$inset))
  $graphics.Dispose()
  return $bitmap
}
$targets = @()
$targets += Get-ChildItem (Join-Path $root 'android/app/src/main/res/mipmap-*/ic_launcher.png')
$targets += Get-ChildItem (Join-Path $root 'ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png')
$targets += Get-ChildItem (Join-Path $root 'macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png')
$targets += Get-ChildItem (Join-Path $root 'web/icons/*.png')
$targets += Get-Item (Join-Path $root 'web/favicon.png')
foreach ($target in $targets) {
  $existing = [Drawing.Bitmap]::new($target.FullName)
  $size = $existing.Width
  $existing.Dispose()
  $bitmap = Make-Icon $size ($target.Name -like '*maskable*')
  $bitmap.Save($target.FullName, [Drawing.Imaging.ImageFormat]::Png)
  $bitmap.Dispose()
}
$sizes = @(16, 24, 32, 48, 64, 128, 256)
$images = @()
foreach ($size in $sizes) {
  $bitmap = Make-Icon $size
  $stream = [IO.MemoryStream]::new()
  $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
  $images += ,$stream.ToArray()
  $stream.Dispose()
  $bitmap.Dispose()
}
$stream = [IO.File]::Create((Join-Path $root 'windows/runner/resources/app_icon.ico'))
$writer = [IO.BinaryWriter]::new($stream)
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i=0; $i -lt $sizes.Count; $i++) {
  $dimension = $sizes[$i] % 256
  $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
  $writer.Write([byte]0); $writer.Write([byte]0)
  $writer.Write([uint16]1); $writer.Write([uint16]32)
  $writer.Write([uint32]$images[$i].Length); $writer.Write([uint32]$offset)
  $offset += $images[$i].Length
}
foreach ($bytes in $images) { $writer.Write([byte[]]$bytes) }
$writer.Dispose()
$sourceImage.Dispose()
Write-Output "Updated $($targets.Count) PNG icons and the Windows ICO."
