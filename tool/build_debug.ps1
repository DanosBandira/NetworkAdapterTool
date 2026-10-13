# Builds the debug version for testing on this PC. Never share this build:
# it needs the debug Visual C++ runtime, which only exists where Visual
# Studio or the Build Tools are installed.
#
# Usage (from the repository root):
#   powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1
#   powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1 -Run       # build and start
#   powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1 -NoPause   # do not wait for a key or ask to start
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
$buildSucceeded = $false

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
    $executablePath = Join-Path $repositoryRoot 'build\windows\x64\runner\Debug\network_adapter_tool.exe'

    Push-Location $repositoryRoot
    try {
        flutter build windows --debug
        if ($LASTEXITCODE -ne 0) { throw "flutter build failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }

    $buildSucceeded = $true
    Write-Host ''
    Write-Host "BUILD SUCCEEDED: $executablePath" -ForegroundColor Green

    if ($Run) { Start-App $executablePath }
} catch {
    Write-Host ''
    Write-Host "BUILD FAILED: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    # Keeps the window open when the script was started by double-click or a
    # shortcut, so the result can be read. After a successful build it offers
    # to start the app right away, for testing.
    if (-not $NoPause) {
        if ($buildSucceeded -and -not $Run) {
            $answer = Read-KeyCharacter 'Start Network Adapter Tool now? Press Y to start, any other key to close.'
            if ($answer -match '^[yYjJ]') { Start-App $executablePath }
        } else {
            [void](Read-KeyCharacter 'Press any key to close...')
        }
    }
}

if (-not $buildSucceeded) { exit 1 }
