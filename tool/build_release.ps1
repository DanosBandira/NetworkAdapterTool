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
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -NoPause   # do not wait for a key or ask to start
#
# Without -Run or -NoPause the script asks after a successful build whether
# to start the app (Y starts it, any other key closes).

param(
    [switch]$Run,
    [switch]$NoPause
)

# One key press without Enter. ReadKey is not available in every host (e.g.
# PowerShell ISE), hence the Read-Host fallback.
function Read-KeyCharacter([string]$prompt) {
    Write-Host ''
    Write-Host $prompt
    try {
        return [string]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').Character
    } catch {
        return Read-Host 'Type your answer and press Enter'
    }
}

# The exe requires administrator rights, so Windows shows a UAC prompt;
# declining it makes Start-Process fail.
function Start-App([string]$executablePath) {
    try {
        Start-Process $executablePath
    } catch {
        Write-Host "App not started: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

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
        # Icon tree shaking left a stale icon font in build\ (2026-10-12):
        # icons added later were silently missing. The full font costs 1.6 MB.
        flutter build windows --release --no-tree-shake-icons
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

    # The plugins folder comes from the repository via the CMake install step.
    # A config.json is written by a plugin on this PC (e.g. a saved password)
    # and must not reach other users.
    $pluginFolder = Join-Path $stagingFolder 'plugins'
    if (Test-Path $pluginFolder) {
        Get-ChildItem $pluginFolder -Recurse -Filter 'config.json' | Remove-Item -Force
    }

    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path $stagingFolder -DestinationPath $zipPath
    Remove-Item $stagingFolder -Recurse -Force

    $releaseSucceeded = $true
    $zipSize = (Get-Item $zipPath).Length / 1MB
    Write-Host ('PACKAGE CREATED: {0} ({1:N1} MB)' -f $zipPath, $zipSize) -ForegroundColor Green

    if ($Run) { Start-App $executablePath }
} catch {
    Write-Host ''
    Write-Host "RELEASE FAILED: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    # Keeps the window open when the script was started by double-click or a
    # shortcut, so the result can be read. After a successful build it offers
    # to start the app right away, for testing.
    if (-not $NoPause) {
        if ($releaseSucceeded -and -not $Run) {
            $answer = Read-KeyCharacter 'Start Network Adapter Tool now? Press Y to start, any other key to close.'
            if ($answer -match '^[yYjJ]') { Start-App $executablePath }
        } else {
            [void](Read-KeyCharacter 'Press any key to close...')
        }
    }
}

if (-not $releaseSucceeded) { exit 1 }
