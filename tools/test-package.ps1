param(
    [Parameter(Mandatory)][string]$Zip,
    [Parameter(Mandatory)][string]$Godot
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('visual-inventory-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Zip))
try {
    foreach ($entry in $archive.Entries) {
        if (($entry.FullName -ne 'addons/' -and $entry.FullName -notmatch '^addons/visual_inventory/') -or $entry.FullName -match '(^|/)(\.|\.\.|\.git|\.godot|\.aws|\.env)(/|$)' -or $entry.FullName.Contains('\')) {
            throw "Unsafe or unrelated ZIP entry: $($entry.FullName)"
        }
    }
} finally { $archive.Dispose() }
[IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path -LiteralPath $Zip), $testRoot)
$project = @'
config_version=5
[application]
config/name="Visual Inventory package regression"
[rendering]
renderer/rendering_method="gl_compatibility"
[visual_inventory]
package_test=true
[editor_plugins]
enabled=PackedStringArray("res://addons/visual_inventory/plugin.cfg")
'@
[IO.File]::WriteAllText((Join-Path $testRoot 'project.godot'), $project)
function Invoke-TestEditor([string]$Name, [string[]]$ExtraArgs) {
    $stdout = Join-Path $testRoot "$Name.stdout.log"
    $stderr = Join-Path $testRoot "$Name.stderr.log"
    $arguments = @('--headless', '--editor', '--path', ('"' + $testRoot + '"')) + $ExtraArgs
    $process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $process.WaitForExit(120000)) {
        $process.Kill()
        throw "Godot timed out; logs: $testRoot"
    }
    $output = (Get-Content -LiteralPath $stdout -Raw) + (Get-Content -LiteralPath $stderr -Raw)
    if ($process.ExitCode -ne 0 -or $output -match '(?m)(SCRIPT ERROR:|ERROR:|FAIL:)') {
        $errors = ($output -split "`n" | Where-Object { $_ -match 'ERROR:|FAIL:|at:|HOST_FEATURE_TESTS' }) -join "`n"
        throw "Godot $Name failed (exit $($process.ExitCode)); logs: $testRoot`n$errors"
    }
    return $output
}
Write-Output "Clean test project: $testRoot"
$importOutput = Invoke-TestEditor 'import' @('--import')
if ($importOutput -notmatch 'VisualInventory') { throw 'Packaged plugin did not initialize.' }
$testAddon = Join-Path $testRoot 'addons/package_regression'
New-Item -ItemType Directory -Path $testAddon | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'tests/host_feature_catalog_test.gd') -Destination (Join-Path $testAddon 'test.gd')
[IO.File]::WriteAllText((Join-Path $testAddon 'plugin.cfg'), "[plugin]`nname=`"Package regression`"`ndescription=`"Disposable test harness`"`nauthor=`"Visual Inventory`"`nversion=`"1`"`nscript=`"test.gd`"`n")
$project = [IO.File]::ReadAllText((Join-Path $testRoot 'project.godot')).Replace('PackedStringArray("res://addons/visual_inventory/plugin.cfg")', 'PackedStringArray("res://addons/visual_inventory/plugin.cfg", "res://addons/package_regression/plugin.cfg")')
[IO.File]::WriteAllText((Join-Path $testRoot 'project.godot'), $project)
$testOutput = Invoke-TestEditor 'regression' @('--quit-after', '1800')
if ($testOutput -notmatch 'HOST_FEATURE_TESTS: PASS') { throw "Regression test did not complete; logs: $testRoot`n$testOutput" }
Write-Output ($testOutput -split "`n" | Where-Object { $_ -match 'Built-in feature|HOST_FEATURE_TESTS|VisualInventory' })
Write-Output "Package validation passed; logs and saved Host resource: $testRoot"
