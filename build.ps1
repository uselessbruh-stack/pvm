param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist')
)

$ErrorActionPreference = 'Stop'
$compilerCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compiler = $compilerCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $compiler) { throw 'The .NET Framework C# compiler was not found. Install the .NET Framework developer tools or build with Visual Studio.' }

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$launcher = Join-Path $OutputDirectory 'pvm.exe'
$setup = Join-Path $OutputDirectory 'PVM-Setup.exe'
$icon = Join-Path $OutputDirectory 'pvm.ico'

# Turn the supplied PNG favicon into a multi-size Windows icon without adding
# an image-conversion dependency to the build.
Add-Type -AssemblyName System.Drawing
$sourceIcon = New-Object System.Drawing.Bitmap((Join-Path $PSScriptRoot 'favicon.png'))
$sizes = @(16, 24, 32, 48, 64, 128, 256)
$pngImages = @()
foreach ($size in $sizes) {
    $bitmap = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $scale = [Math]::Min(($size * 0.94) / $sourceIcon.Width, ($size * 0.94) / $sourceIcon.Height)
    $width = [int][Math]::Round($sourceIcon.Width * $scale)
    $height = [int][Math]::Round($sourceIcon.Height * $scale)
    $graphics.DrawImage($sourceIcon, [int](($size - $width) / 2), [int](($size - $height) / 2), $width, $height)
    $stream = New-Object System.IO.MemoryStream
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngImages += ,$stream.ToArray()
    $stream.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}
$sourceIcon.Dispose()
$iconStream = [System.IO.File]::Create($icon)
$writer = New-Object System.IO.BinaryWriter($iconStream)
$writer.Write([UInt16]0)
$writer.Write([UInt16]1)
$writer.Write([UInt16]$sizes.Count)
$offset = 6 + (16 * $sizes.Count)
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $pixelSize = $sizes[$i]
    $dimension = if ($pixelSize -eq 256) { [byte]0 } else { [byte]$pixelSize }
    $writer.Write($dimension)
    $writer.Write($dimension)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]32)
    $writer.Write([UInt32]$pngImages[$i].Length)
    $writer.Write([UInt32]$offset)
    $offset += $pngImages[$i].Length
}
foreach ($png in $pngImages) { $writer.Write($png) }
$writer.Dispose()
$iconStream.Dispose()

& $compiler /nologo /target:exe /win32icon:$icon /out:$launcher (Join-Path $PSScriptRoot 'src\PvmLauncher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile pvm.exe.' }

& $compiler /nologo /target:exe /win32icon:$icon /out:$setup `
    /resource:$(Join-Path $PSScriptRoot 'install.ps1'),payload.install.ps1 `
    /resource:$(Join-Path $PSScriptRoot 'pvm.ps1'),payload.pvm.ps1 `
    /resource:$(Join-Path $PSScriptRoot 'pvm.cmd'),payload.pvm.cmd `
    /resource:$launcher,payload.pvm.exe `
    (Join-Path $PSScriptRoot 'src\PvmSetup.cs')
if ($LASTEXITCODE -ne 0) { throw 'Failed to compile PVM-Setup.exe.' }

Write-Host "Built $launcher"
Write-Host "Built $setup"
Write-Host "Embedded icon from $(Join-Path $PSScriptRoot 'favicon.png')"
