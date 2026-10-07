# Builds the release version into build\windows\x64\runner\Release. That
# whole folder runs on any Windows 10/11 PC; use package_release.ps1 to get
# it as a zip.
#
# Usage (from the repository root):
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -Run   # build and start

param([switch]$Run)

. (Join-Path $PSScriptRoot 'build_common.ps1')
Invoke-WindowsBuild -BuildMode release -Run:$Run
