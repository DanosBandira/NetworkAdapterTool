# Network Adapter Tool

Windows desktop tool to switch network adapters between DHCP and static IPv4
settings with saved profiles. Built for machine networks: switch a laptop to
a machine's subnet, check that the devices answer, and switch back.

## Features

- **Adapters**: all network adapters with status, IP/subnet mask, gateway,
  DNS and DHCP/static. Green cards are connected, red cards are not.
- **Profiles**: named DHCP or static settings (IP, mask, optional gateway and
  DNS servers), validated while you type. Apply a profile to the selected
  adapter with the orange arrow button.
- **Direct configuration**: double-click an adapter to switch it between
  DHCP and static and enter IP, mask, gateway and DNS right away, without
  creating a profile.
- **Verification**: after applying, the adapter is read back and compared, so
  you see exactly which setting did not take effect.
- **Ping targets**: per profile, addresses (with an optional name such as
  "PLC") that are pinged automatically after applying, or with the Ping
  button. Each target is retried for up to 10 seconds.
- **Presets**: a named set of adapter ← profile lines to switch several
  adapters with one click, with a result per line and a Ping button for all
  profiles in the preset.
- **Search** in the adapter and profile lists.
- **Import and Export** (top right) to share profiles and presets with other
  users or PCs. Changes are saved automatically; Export writes a copy to a
  file of your choice. Importing can add to your data (duplicate names get
  "(imported)") or replace it (after an automatic backup). Preset adapters
  that do not exist on this PC can be mapped to a local adapter while
  importing; preset cards warn about adapters that are missing.

Windows can only switch an adapter from DHCP to a static address while it is
connected; the app tells you to connect the cable first instead of leaving
the adapter half configured.

## Installing

1. Unpack `NetworkAdapterTool.zip` to a fixed location, e.g.
   `C:\Tools\NetworkAdapterTool`.
2. Create a shortcut to `network_adapter_tool.exe` (right-click → *Show more
   options* → *Create shortcut*) and place it on the desktop or in the Start
   menu.

Keep the exe inside its folder: it loads `flutter_windows.dll`, the Visual
C++ runtime DLLs and the `data` folder from there, so copying only the exe
fails with a missing DLL error. No other software needs to be installed on
Windows 10 or 11.

The app asks for administrator rights at start (UAC), because changing IP
settings requires elevation.

Profiles and presets are stored in
`%APPDATA%\NetworkAdapterTool\user_data.json`.

## Development

Requirements: Flutter (stable), Visual Studio Build Tools with the
"Desktop development with C++" workload, and Windows **Developer Mode**
(`start ms-settings:developers`) on the build PC, because Flutter needs
symlinks to build plugins. PCs that only run the app need none of this.

```
flutter test                      # unit and widget tests, no elevation needed
flutter run -d windows            # from an elevated terminal (requireAdministrator)
```

### Building

```
powershell -ExecutionPolicy Bypass -File tool\build_debug.ps1     # debug build, for testing on this PC
powershell -ExecutionPolicy Bypass -File tool\build_release.ps1   # release build + dist\NetworkAdapterTool.zip
```

`build_release.ps1` always packs the complete Release folder into
`dist\NetworkAdapterTool.zip`, ready to share. Never distribute the Debug
build: it depends on the debug Visual C++ runtime, which only exists on PCs
with Visual Studio installed.

Add `-Run` to start the app after building. Each script ends with a green
success line or a red failure line and waits for a key, so the result stays
readable when started by double-click; add `-NoPause` to skip the wait (e.g.
in automation). Both scripts reload PATH (so they also work in a terminal
opened before Flutter was installed) and stop with a clear message when the
app is still running, because a running app locks its exe.

Architecture, design decisions and conventions are documented in
[CLAUDE.md](CLAUDE.md); [docs/architecture.html](docs/architecture.html)
visualizes the layers and dependencies.

### App icon

The icon is generated from [icon.svg](icon.svg):

```
python tool\svg_to_ico.py icon.svg windows\runner\resources\app_icon.ico build\icon
```
