# Shared build steps for build_debug.ps1 and build_release.ps1; not meant to
# be run directly.

function Invoke-WindowsBuild {
    param(
        [Parameter(Mandatory)][ValidateSet('debug', 'release')][string]$BuildMode,
        [switch]$Run
    )

    $ErrorActionPreference = 'Stop'

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
    $outputFolder = if ($BuildMode -eq 'release') { 'Release' } else { 'Debug' }
    $executablePath = Join-Path $repositoryRoot "build\windows\x64\runner\$outputFolder\network_adapter_tool.exe"

    Push-Location $repositoryRoot
    try {
        flutter build windows "--$BuildMode"
        if ($LASTEXITCODE -ne 0) { throw "flutter build failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }

    "Built $executablePath"

    if ($Run) {
        # The exe requires administrator rights, so Windows shows a UAC prompt.
        Start-Process $executablePath
    }
}
