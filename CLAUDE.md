# Network Adapter Tool

Windows desktop tool to switch network adapters between DHCP and static IP
settings using saved profiles.

## Before writing code

Read and follow the coding style rules at:
https://raw.githubusercontent.com/DanosBandira/GeneralAiSkills/main/CodeStyleRules.md

Summary: orchestrating methods with small named steps (stepdown order), long
descriptive names, comments only for *why* plus a short file/class header,
composition over inheritance. Code and comments in English.

Follow Dart conventions on top of that: `snake_case` file names,
`UpperCamelCase` types, `lowerCamelCase` members, no `I` prefix on
interfaces (use `abstract interface class`).

## Stack

- Flutter (stable) with Dart 3, Windows desktop target only
- `provider` + `ChangeNotifier` view models (MVVM)
- Manual constructor injection; composition root in `lib/main.dart`
- `dart:convert` for profile storage (JSON)
- `flutter_test` for tests, `flutter_lints` for analysis
- `requireAdministrator` via `/MANIFESTUAC` in `windows/runner/CMakeLists.txt`
  (changing IP settings needs elevation). Not as a `trustInfo` block in
  `runner.exe.manifest`: the linker adds its own UAC fragment and mt.exe
  fails on the duplicate (LNK1327).

## Project structure

Single Flutter project in the repository root. `lib/core/` must never import
`package:flutter`, so it stays testable as plain Dart.

```
pubspec.yaml
windows/runner/CMakeLists.txt                  (/MANIFESTUAC requireAdministrator)
lib/
├── main.dart                                  (composition root)
├── core/
│   ├── models/
│   │   ├── network_profile.dart
│   │   ├── network_adapter.dart
│   │   ├── ipv4_address.dart                  (parsing + subnet arithmetic)
│   │   ├── ping_target.dart                   (IP + optional name)
│   │   ├── network_preset.dart                (name + adapter→profile lines)
│   │   ├── network_profile_library.dart       (profiles + presets, stored together)
│   │   └── addressing_mode.dart               (dhcp | staticIp)
│   ├── contracts/
│   │   ├── network_adapter_reader.dart
│   │   ├── network_adapter_configurator.dart
│   │   ├── network_profile_repository.dart
│   │   ├── host_pinger.dart
│   │   └── command_runner.dart
│   ├── adapters/
│   │   ├── powershell_network_adapter_reader.dart
│   │   ├── netsh_network_adapter_configurator.dart
│   │   ├── ping_exe_host_pinger.dart
│   │   └── process_command_runner.dart
│   ├── reachability/
│   │   └── ping_targets_checker.dart
│   ├── profiles/
│   │   ├── json_network_profile_repository.dart
│   │   ├── network_profile_validator.dart
│   │   └── network_preset_validator.dart
│   ├── network_profile_applier.dart
│   └── network_preset_applier.dart
└── app/
    ├── view_models/
    │   ├── main_view_model.dart
    │   ├── network_adapter_view_model.dart
    │   ├── network_profile_editor_view_model.dart
    │   └── network_preset_editor_view_model.dart
    └── views/
        ├── main_view.dart
        ├── left_arrow_border.dart
        ├── network_profile_editor_view.dart
        └── network_preset_editor_view.dart
test/
├── core/ · app/                               (mirror lib/)
└── fakes/                                     (fake reader/configurator/runner/repository)
docs/architecture.html                         (layers + dependency graph)
icon.svg                                       (app icon source)
tool/svg_to_ico.py                             (icon.svg → app_icon.ico)
```

## Responsibilities

| Component | Responsibility | Depends on |
|---|---|---|
| `PowerShellNetworkAdapterReader` | Read adapters and their current IPv4 settings via a PowerShell script that returns JSON | `CommandRunner` |
| `NetshNetworkAdapterConfigurator` | Translate a profile into netsh commands | `CommandRunner` |
| `ProcessCommandRunner` | Start an executable with an argument list, return exit code and output | – |
| `JsonNetworkProfileRepository` | Load/save the `NetworkProfileLibrary` (profiles + presets) in `%APPDATA%\NetworkAdapterTool\profiles.json`; falls back to the pre-rename `%APPDATA%\NetworkProfileSwitcher\profiles.json` while the new file does not exist and never changes that legacy file | – |
| `NetworkPresetValidator` | Preset name unique, ≥1 line, lines complete, adapter once, profile exists | – |
| `NetworkPresetApplier` | Apply preset lines one by one via `NetworkProfileApplier`; a failing line does not stop the rest | profile applier |
| `NetworkProfileValidator` | Validate IP, subnet mask, gateway in same subnet, DNS addresses | – |
| `NetworkProfileApplier` | Use case: validate, apply, verify the result | validator, configurator, reader |
| `PingExeHostPinger` | One echo request via `ping.exe`; reply = exit code 0 and `TTL=` in the output | `CommandRunner` |
| `PingTargetsChecker` | Ping all targets concurrently, retry each until it answers or 10 s pass, emit results as they resolve | `HostPinger` |
| View models | UI state and commands only, no network logic | applier, repository, reader, ping checker |

## Model

`NetworkProfile` (immutable, with `toJson`/`fromJson`):
- `name` (String)
- `addressingMode` (dhcp | staticIp; `static` is reserved in Dart)
- `ipAddress`, `subnetMask` (required when staticIp)
- `defaultGateway` (optional)
- `dnsServers` (optional list)
- `pingTargets` (optional list of `PingTarget`: `ipAddress` + optional
  `name`), for both DHCP and static profiles

A profile is independent of an adapter: the user picks the target adapter when
applying it.

`NetworkPreset`: `name` + `assignments` (list of `PresetAssignment`:
`adapterName` + `profileName`). Applies several adapters at once. Both sides
are referenced by name; adapters are not validated against the current system
(e.g. a USB adapter may be absent), failures show per line when applying.

## netsh commands

```
netsh interface ipv4 set address name=<adapter> source=dhcp
netsh interface ipv4 set dnsservers name=<adapter> source=dhcp

netsh interface ipv4 set address name=<adapter> source=static address=<ip> mask=<mask> gateway=<gateway|none>
netsh interface ipv4 set dnsservers name=<adapter> source=static address=<dns1> register=primary validate=no
netsh interface ipv4 add dnsservers name=<adapter> address=<dns2> index=2 validate=no

# static profile without DNS servers
netsh interface ipv4 set dnsservers name=<adapter> source=static address=none
```

## Reading adapters

`dart:io` `NetworkInterface.list()` only exposes names and addresses (no mask,
gateway, DNS or DHCP state), so the reader runs one PowerShell script:

```
powershell.exe -NoProfile -NonInteractive -EncodedCommand <base64 script>
```

The script combines `Get-NetAdapter`, `Get-NetIPInterface` (Dhcp),
`Get-NetIPAddress` (IPv4 + PrefixLength), `Get-NetRoute` (default gateway) and
`Get-DnsClientServerAddress`, and ends with `ConvertTo-Json`. Dart converts the
prefix length to a dotted subnet mask. The reader sits behind
`NetworkAdapterReader`, so it can be swapped for a Win32 FFI implementation
(`GetAdaptersAddresses`) later if PowerShell startup time becomes a problem.

- The script is passed with `-EncodedCommand` (Base64 of UTF-16LE), so it
  needs no command-line escaping.
- One read takes 2–5 seconds; the UI must show a loading state and never
  read adapters on the UI thread synchronously.
- APIPA addresses (169.254.x.x) are only reported when the adapter has no
  other IPv4 address, so a disconnected static adapter shows its configured
  address.
- A disconnected adapter's static gateway only exists in the route
  `PersistentStore`; the script reads both active and persistent routes.
- A disabled adapter has no IPv4 interface: `addressingMode` is `null`.

## Design decisions

- Pass arguments to `Process.run` as a list, never as one concatenated string,
  so adapter names with spaces need no manual quoting.
- Gateway and DNS are optional in a profile (direct machine connections
  usually have neither). When not set, clear them explicitly with `none`
  instead of omitting the argument, otherwise values from a previously
  applied profile linger.
- netsh returns exit code 1 when DHCP is already enabled on the interface;
  the configurator treats that as success for the DHCP commands only. netsh
  uses the same code for real errors, so the applier's verification step is
  what catches those.
- netsh output is localized and in the OEM code page; rely on exit codes, not
  on parsing netsh text.
- Force UTF-8 output in the PowerShell script
  (`[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false`,
  i.e. without BOM) so adapter names with non-ASCII characters survive.
- After applying, `NetworkProfileApplier` re-reads the adapter and compares,
  because netsh can report success before the setting is active. It retries
  the read (default 3 attempts, 1 s apart) and returns a sealed
  `ApplyProfileOutcome` (`ProfileApplied`, `ProfileInvalid`,
  `ProfileRejectedBySystem`, `ProfileNotActive` with per-setting mismatches,
  `ProfileNotVerified`) so the UI must handle every case.
- A DHCP profile is verified on addressing mode only; right after switching
  the adapter may still hold an APIPA address.
- Windows does not disable DHCP on a disconnected adapter: switching a
  disconnected DHCP adapter to static stores the address next to
  `EnableDHCP=1` (verified 2026-10-06 with netsh, `Set-NetIPInterface` and WMI
  `EnableStatic`, all reporting success). The applier therefore reads the
  adapter first for static profiles and returns
  `ProfileNeedsConnectedAdapter` without applying anything. Static-to-static
  and switching to DHCP work while disconnected. Do not write `EnableDHCP` to
  the registry directly; that bypasses the DHCP client.
- `docs/architecture.html` visualizes the layers; update it when components
  are added or a build step is completed.
- Use `Platform.environment['APPDATA']` for the profile path instead of
  `path_provider`, which would add a company/app subfolder.
- Ping targets: pinged automatically after a successful apply (`ProfileApplied`)
  and on demand with the ping button on a profile card. Each target is retried
  for up to 10 s (1 s timeout per attempt, 0.5 s pause after a failure),
  because link, ARP and devices need a few seconds after switching. Results
  show under the profile card and are dropped when the profile is edited or
  deleted. `ping.exe` exits 0 on "Destination host unreachable", so only
  output containing `TTL=` counts as a reply.
- Presets: lines are applied sequentially (parallel netsh/PowerShell runs
  only compete). Each line gets its own result under the preset card; the
  status line summarizes "x of y adapters switched". Afterwards the ping
  targets of all successfully applied profiles are pinged. Renaming a profile
  updates every preset in the same save; deleting a profile used by a preset
  is refused with a message naming the presets.
- Preset "Ping" button (shown when at least one of its profiles has ping
  targets): pings all those profiles concurrently without applying anything.
  Results show under the profile cards and, grouped per profile, in the
  preset card.
- `profiles.json` is `{"formatVersion": 3, "profiles": [...], "presets":
  [...]}` (2 added `pingTargets`, 3 added `presets`; older files still load),
  written to a
  `.tmp` file and renamed over the original. A file that cannot be parsed or
  has a newer format version raises `NetworkProfileStorageException`; never
  treat it as "no profiles", or the next save would wipe the user's data.
- IPv4 parsing rejects leading zeros (`010`), because Windows reads them as
  octal.
- The validator returns all errors at once, each tagged with a
  `NetworkProfileField`, for inline display in the editor. Name uniqueness is
  checked against `otherProfileNames` passed in by the caller.
- IPv4 only in the first version.
- Tests for the configurator use a fake `CommandRunner` and assert on the
  generated commands; the reader is tested against captured JSON samples; no
  test may change a real adapter.

## Development

- Because of `requireAdministrator`, `flutter run` must be started from an
  elevated terminal/IDE; otherwise launching the exe fails.
- `flutter test` needs no elevation (core tests use fakes).
- View models are tested with the fakes in `test/fakes/` and a real
  `NetworkProfileApplier`; widget tests in `test/app/views/` render the real
  views against those view models.

- App icon: `icon.svg` (repo root, supplied by the user) is the source;
  `windows/runner/resources/app_icon.ico` (16–256 px) is generated from it
  with `python tool/svg_to_ico.py icon.svg windows/runner/resources/app_icon.ico <work dir>`
  (headless Edge renders, standard-library Python packs the .ico; no extra
  packages). Rebuild afterwards; Explorer may show the old icon until its
  icon cache refreshes.

## UI conventions

- UI text is English, like the validator messages.
- Adapter cards sit in a grid of 1–3 columns (minimum card width 240 px,
  `Wrap` so rows grow to the tallest card) with a compact layout: header row
  with icon, name and DHCP/Static, then status and details.
- Adapter cards: light green background when connected, light red otherwise
  (muted variants in dark mode). The selected card gets a darker shade of its
  own color plus a primary-colored border.
- Profile cards: light yellow background (muted in dark mode); the selected
  card gets a darker yellow plus the border.
- Each panel has a search field: adapters match on name, description and IP;
  profiles on name, IP and gateway (case-insensitive). Searching only hides
  entries; the selection is kept.
- View models expose `can…` getters for every action; views only enable a
  button through them. While applying or loading, adapter actions are
  disabled.
- Profile editing stays disabled when `profiles.json` failed to load, so a
  save can never overwrite profiles that could not be read.
- After applying, the adapter returned by `ProfileApplied` replaces the list
  entry instead of triggering a full (slow) re-read.
- The editor shows two DNS fields like Windows; extra servers from
  `profiles.json` are kept. Switching a profile to DHCP drops its address
  fields.

## UI

- Main window: adapter grid (name, status, current IP, DHCP/static) on the
  left; on the right the profile list (top half) and the preset list (bottom
  half, light purple cards with an "Apply" button and per-line results). Below them, centered, the "Apply profile
  to selected adapter" button shaped as a left-pointing arrow
  (`LeftArrowBorder`: the profile goes right-to-left onto the adapter), orange
  (`0xFFF57C00`, white text; theme grey when disabled), with the status line
  under it.
- The "Switch to DHCP" button is hidden for now (user request, 2026-10-06);
  `MainViewModel.switchSelectedAdapterToDhcp` and its tests remain so it can
  come back.
- Profile editor: create, edit, delete profiles with inline validation.

## Build order

All done:

1. `flutter create --platforms=windows`, manifest, lints; core models and contracts
2. `ProcessCommandRunner` + `NetshNetworkAdapterConfigurator` with tests
3. `PowerShellNetworkAdapterReader` with JSON-sample tests
4. `JsonNetworkProfileRepository` + `NetworkProfileValidator` with tests
5. `NetworkProfileApplier`
6. Flutter app: main view, profile editor

## Future

Not planned yet; pick up only when the user asks.

### Tray menu

- Tray icon with a context menu: one submenu per adapter (showing name,
  connection state and DHCP/static) containing "Switch to DHCP" and every
  profile; one click applies it. The active profile gets a check mark.
  Below the adapters: "Open window", "Refresh adapters", "Exit".
- After applying, show a Windows notification with the outcome text (the same
  messages `MainViewModel` produces).
- Closing the window hides it to the tray; "Exit" really quits.
- Packages: `tray_manager` (icon + menu), `window_manager` (hide to tray).
  Planned location: `lib/app/tray/tray_menu_builder.dart`.
- Reuse `MainViewModel` for state and applying, so the apply/verify/error
  logic exists once. Build the menu from the last known adapter list and
  refresh in the background when the menu opens (a read takes 2–5 s).
- Open question: which adapters to list. The user's machine has 10, most
  virtual (Hyper-V, VPN, TAP, Bluetooth). Options: all, physical only
  (`Get-NetAdapter -Physical`, preferred), or a user-selectable list.

### Start with Windows

- Because of `requireAdministrator`, a normal autostart shows a UAC prompt at
  every login. Without the prompt it needs a scheduled task with "run with
  highest privileges" at logon.
