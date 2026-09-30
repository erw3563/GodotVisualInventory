param(
    [Parameter(Mandatory)][string]$Godot,
    [string]$Output
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not $Output) { $Output = Join-Path $repo 'dist/visual_inventory-0.5-host-feature-fix.zip' }
$Output = [IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $Output) { throw "Refusing to overwrite existing file: $Output" }
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw "Godot executable not found: $Godot" }
# Only versioned plugin files enter the package; working-tree fixes are included.
$files = @(git -C $repo -c core.quotepath=false ls-files -- addons/visual_inventory)
if ($LASTEXITCODE -ne 0 -or $files.Count -eq 0) { throw 'Cannot enumerate tracked plugin files.' }
$required = @('addons/visual_inventory/plugin.cfg', 'addons/visual_inventory/visual_inventory.gd', 'addons/visual_inventory/LICENSE')
foreach ($path in $required) { if ($path -notin $files) { throw "Missing required package file: $path" } }
foreach ($path in $files) {
    if ($path -match '(^|/)\.' -or ([IO.Path]::GetExtension($path) -notin @('.gd','.uid','.cfg','.tres','.tscn','.png','.svg','.import','.gdshader','.aseprite') -and $path -ne 'addons/visual_inventory/LICENSE')) {
        throw "Unexpected package file (review before shipping): $path"
    }
}
New-Item -ItemType Directory -Force -Path (Split-Path $Output -Parent) | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$candidate = Join-Path ([IO.Path]::GetTempPath()) ('visual-inventory-candidate-' + [guid]::NewGuid().ToString('N') + '.zip')
$archive = [IO.Compression.ZipFile]::Open($candidate, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($path in ($files | Sort-Object)) {
        $entry = $archive.CreateEntry($path, [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        $inputStream = [IO.File]::OpenRead((Join-Path $repo $path))
        $outputStream = $entry.Open()
        try { $inputStream.CopyTo($outputStream) }
        finally { $inputStream.Dispose(); $outputStream.Dispose() }
    }
} finally { $archive.Dispose() }
& (Join-Path $PSScriptRoot 'test-package.ps1') -Zip $candidate -Godot $Godot
# Publish only a tested archive. Keep existing/user ZIPs untouched.
Copy-Item -LiteralPath $candidate -Destination $Output
[PSCustomObject]@{
    Path = $Output
    SizeBytes = (Get-Item -LiteralPath $Output).Length
    SHA256 = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash
} | Format-List
