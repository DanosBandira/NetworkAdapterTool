# Builds the debug version for testing on this PC. Never share this build:
# it needs the debug Visual C++ runtime, which only exists where Visual
# Studio or the Build Tools are installed.
#
# Usage (from the repository root):
#   powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1
#   powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1 -Run   # build and start

param([switch]$Run)

. (Join-Path $PSScriptRoot 'build_common.ps1')
Invoke-WindowsBuild -BuildMode debug -Run:$Run
