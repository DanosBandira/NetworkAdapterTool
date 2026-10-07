# Builds the debug version for testing on this PC. Never share this build:
# it needs the debug Visual C++ runtime, which only exists where Visual
# Studio or the Build Tools are installed.
#
# Usage (from the repository root):
#   powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1
#   powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1 -Run       # build and start
#   powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1 -NoPause   # do not wait for a key

param(
    [switch]$Run,
    [switch]$NoPause
)

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

    if ($Run) {
        # The exe requires administrator rights, so Windows shows a UAC prompt.
        Start-Process $executablePath
    }
} catch {
    Write-Host ''
    Write-Host "BUILD FAILED: $($_.Exception.Message)" -ForegroundColor Red
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

if (-not $buildSucceeded) { exit 1 }
