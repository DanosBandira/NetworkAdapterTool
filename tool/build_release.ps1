# Builds the release version into build\windows\x64\runner\Release. That
# whole folder runs on any Windows 10/11 PC; use package_release.ps1 to get
# it as a zip.
#
# Usage (from the repository root):
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -Run   # build and start

param([switch]$Run)

$ErrorActionPreference = 'Stop'

# Terminals opened before Flutter was added to PATH keep the old PATH and
# cannot find `flutter`; reload it from the registry.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' +
    [Environment]::GetEnvironmentVariable('Path', 'Machine')

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'flutter was not found on PATH. Install the Flutter SDK and add its bin folder to PATH.'
}

# A running app locks its exe, and the linker then fails with the unhelpful
# "LNK1168: cannot open ... for writing".
if (Get-Process network_adapter_tool -ErrorAction SilentlyContinue) {
    throw 'Network Adapter Tool is still running. Close it and run this script again.'
}

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$executablePath = Join-Path $repositoryRoot 'build\windows\x64\runner\Release\network_adapter_tool.exe'

Push-Location $repositoryRoot
try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}

"Built $executablePath"

if ($Run) {
    # The exe requires administrator rights, so Windows shows a UAC prompt.
    Start-Process $executablePath
}
