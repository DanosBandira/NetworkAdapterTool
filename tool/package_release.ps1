# Builds the release version and packs the complete Release folder into
# dist\NetworkAdapterTool.zip.
#
# The exe cannot run on its own: it loads flutter_windows.dll, the VC++
# runtime DLLs and the data folder from its own directory. The zip therefore
# contains the whole folder; unpack it anywhere and create a shortcut to
# NetworkAdapterTool\network_adapter_tool.exe.
#
# Usage (from the repository root):
#   powershell -ExecutionPolicy Bypass -File tool\package_release.ps1
#   powershell -ExecutionPolicy Bypass -File tool\package_release.ps1 -SkipBuild

param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'

# Terminals opened before Flutter was added to PATH keep the old PATH and
# cannot find `flutter`; reload it from the registry.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' +
    [Environment]::GetEnvironmentVariable('Path', 'Machine')

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$releaseFolder = Join-Path $repositoryRoot 'build\windows\x64\runner\Release'
$distFolder = Join-Path $repositoryRoot 'dist'
$stagingFolder = Join-Path $distFolder 'NetworkAdapterTool'
$zipPath = Join-Path $distFolder 'NetworkAdapterTool.zip'

if (-not $SkipBuild) {
    Push-Location $repositoryRoot
    try {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path (Join-Path $releaseFolder 'network_adapter_tool.exe'))) {
    throw "No release build found in $releaseFolder"
}

# A clean staging copy keeps leftovers from older builds (e.g. the pre-rename
# exe) out of the zip; *.pdb debug symbols are not needed to run the app.
if (Test-Path $stagingFolder) { Remove-Item $stagingFolder -Recurse -Force }
New-Item -ItemType Directory -Force $stagingFolder | Out-Null
Copy-Item (Join-Path $releaseFolder '*') $stagingFolder -Recurse -Exclude '*.pdb', 'network_profile_switcher.exe'

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $stagingFolder -DestinationPath $zipPath
Remove-Item $stagingFolder -Recurse -Force

$zipSize = (Get-Item $zipPath).Length / 1MB
'Created {0} ({1:N1} MB)' -f $zipPath, $zipSize
