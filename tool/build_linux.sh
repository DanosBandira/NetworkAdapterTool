#!/usr/bin/env bash
# Builds the Linux release and packs it into dist/NetworkAdapterTool-linux.tar.gz,
# ready to share. Run it on Linux (or WSL); Flutter cannot build for Linux
# from Windows.
#
# The executable cannot run on its own: it loads lib/ and data/ from its own
# folder, so the archive holds the whole bundle folder. Unpack it anywhere
# and start NetworkAdapterTool/network_adapter_tool.
#
# Build needs: flutter, clang, cmake, ninja-build, pkg-config, libgtk-3-dev.
# The app needs at runtime: NetworkManager (nmcli), iputils ping, xdg-utils
# and util-linux (setsid); bash for .sh commands, pwsh for .ps1 commands.
#
# Usage (from the repository root):
#   tool/build_linux.sh            # build, pack, then ask whether to start
#   tool/build_linux.sh --run      # build, pack and start without asking
#   tool/build_linux.sh --no-pause # do not ask (e.g. in CI)

set -euo pipefail

run_after_build=false
ask_after_build=true
for argument in "$@"; do
  case "$argument" in
    --run) run_after_build=true; ask_after_build=false ;;
    --no-pause) ask_after_build=false ;;
    *) echo "Unknown option: $argument" >&2; exit 2 ;;
  esac
done

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
bundle_folder="$repository_root/build/linux/x64/release/bundle"
executable_path="$bundle_folder/network_adapter_tool"
dist_folder="$repository_root/dist"
staging_folder="$dist_folder/NetworkAdapterTool"
archive_path="$dist_folder/NetworkAdapterTool-linux.tar.gz"

fail() {
  echo
  echo -e "\e[31mBUILD FAILED: $1\e[0m"
  exit 1
}

command -v flutter >/dev/null || fail "flutter was not found on PATH."

cd "$repository_root"
# Icon tree shaking left a stale icon font in build/ on Windows (2026-10-12),
# so newly used icons went missing; the full font costs 1.6 MB.
flutter build linux --release --no-tree-shake-icons || fail "flutter build failed."

echo
echo -e "\e[32mBUILD SUCCEEDED: $executable_path\e[0m"

# A clean staging copy keeps leftovers of older builds out of the archive. A
# config.json is written by a plugin on this PC (e.g. a saved password) and
# must not reach other users.
rm -rf "$staging_folder"
mkdir -p "$staging_folder"
cp -R "$bundle_folder/." "$staging_folder/"
find "$staging_folder/plugins" -name config.json -delete 2>/dev/null || true
rm -f "$archive_path"
tar -czf "$archive_path" -C "$dist_folder" NetworkAdapterTool
rm -rf "$staging_folder"
echo -e "\e[32mPACKAGE CREATED: $archive_path ($(du -h "$archive_path" | cut -f1))\e[0m"

if $run_after_build; then
  "$executable_path" &
elif $ask_after_build; then
  echo
  read -r -n 1 -p "Start Network Adapter Tool now? Press Y to start, any other key to close. " answer
  echo
  if [[ "$answer" =~ ^[yYjJ]$ ]]; then
    "$executable_path" &
  fi
fi
