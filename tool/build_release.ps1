# Builds the release version and packs it into dist\NetworkAdapterTool.zip,
# ready to share.
#
# The exe cannot run on its own: it loads flutter_windows.dll, the VC++
# runtime DLLs and the data folder from its own directory. The zip therefore
# contains the whole Release folder; unpack it anywhere and create a shortcut
# to NetworkAdapterTool\network_adapter_tool.exe.
#
# Usage (from the repository root):
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -Run       # build, zip and start
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -NoPause   # do not wait for a key

param(
    [switch]$Run,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$releaseSucceeded = $false

try {
    # Terminals opened before Flutter was added to PATH keep the old PATH and
    # cannot find `flutter`; reload it from the registry.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' +
        [Environment]::GetEnvironmentVariable('Path', 'Machine')

    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw 'flutter was not found on PATH. Install the Flutter SDK and add its bin folder to PATH.'
    }

    # A running app locks its exe, and the linker then fails with the
    # unhelpful "LNK1168: cannot open ... for writing".
    if (Get-Process network_adapter_tool -ErrorAction SilentlyContinue) {
        throw 'Network Adapter Tool is still running. Close it and run this script again.'
    }

    $repositoryRoot = Split-Path $PSScriptRoot -Parent
    $releaseFolder = Join-Path $repositoryRoot 'build\windows\x64\runner\Release'
    $executablePath = Join-Path $releaseFolder 'network_adapter_tool.exe'
    $distFolder = Join-Path $repositoryRoot 'dist'
    $stagingFolder = Join-Path $distFolder 'NetworkAdapterTool'
    $zipPath = Join-Path $distFolder 'NetworkAdapterTool.zip'

    Push-Location $repositoryRoot
    try {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }

    Write-Host ''
    Write-Host "BUILD SUCCEEDED: $executablePath" -ForegroundColor Green

    # A clean staging copy keeps leftovers from older builds (e.g. the
    # pre-rename exe) out of the zip; *.pdb debug symbols are not needed to
    # run the app.
    if (Test-Path $stagingFolder) { Remove-Item $stagingFolder -Recurse -Force }
    New-Item -ItemType Directory -Force $stagingFolder | Out-Null
    Copy-Item (Join-Path $releaseFolder '*') $stagingFolder -Recurse -Exclude '*.pdb', 'network_profile_switcher.exe'

    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path $stagingFolder -DestinationPath $zipPath
    Remove-Item $stagingFolder -Recurse -Force

    $releaseSucceeded = $true
    $zipSize = (Get-Item $zipPath).Length / 1MB
    Write-Host ('PACKAGE CREATED: {0} ({1:N1} MB)' -f $zipPath, $zipSize) -ForegroundColor Green

    if ($Run) {
        # The exe requires administrator rights, so Windows shows a UAC prompt.
        Start-Process $executablePath
    }
} catch {
    Write-Host ''
    Write-Host "RELEASE FAILED: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    # Keeps the window open when the script was started by double-click or a
    # shortcut, so the result can be read. ReadKey is not available in every
    # host (e.g. PowerShell ISE), hence the Read-Host fallback.
    if (-not $NoPause) {
        Write-Host ''
        Write-Host 'Press any key to close...'
        try {
            [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        } catch {
            Read-Host 'Press Enter to close' | Out-Null
        }
    }
}

if (-not $releaseSucceeded) { exit 1 }
