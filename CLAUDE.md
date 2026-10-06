# NetworkProfileSwitcher

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
- `tray_manager` for the tray icon, `window_manager` for hide-to-tray
- `dart:convert` for profile storage (JSON)
- `flutter_test` for tests, `flutter_lints` for analysis
- `windows/runner/runner.exe.manifest` with `requireAdministrator`
  (changing IP settings needs elevation)

## Project structure

Single Flutter project in the repository root. `lib/core/` must never import
`package:flutter`, so it stays testable as plain Dart.

```
pubspec.yaml
windows/runner/runner.exe.manifest
lib/
├── main.dart                                  (composition root)
├── core/
│   ├── models/
│   │   ├── network_profile.dart
│   │   ├── network_adapter.dart
│   │   ├── ipv4_address.dart                  (parsing + subnet arithmetic)
│   │   └── addressing_mode.dart               (dhcp | staticIp)
│   ├── contracts/
│   │   ├── network_adapter_reader.dart
│   │   ├── network_adapter_configurator.dart
│   │   ├── network_profile_repository.dart
│   │   └── command_runner.dart
│   ├── adapters/
│   │   ├── powershell_network_adapter_reader.dart
│   │   ├── netsh_network_adapter_configurator.dart
│   │   └── process_command_runner.dart
│   ├── profiles/
│   │   ├── json_network_profile_repository.dart
│   │   └── network_profile_validator.dart
│   └── network_profile_applier.dart
└── app/
    ├── view_models/
    │   ├── main_view_model.dart
    │   ├── network_adapter_view_model.dart
    │   └── network_profile_editor_view_model.dart
    ├── views/
    │   ├── main_view.dart
    │   └── network_profile_editor_view.dart
    └── tray/tray_menu_builder.dart
test/
```

## Responsibilities

| Component | Responsibility | Depends on |
|---|---|---|
| `PowerShellNetworkAdapterReader` | Read adapters and their current IPv4 settings via a PowerShell script that returns JSON | `CommandRunner` |
| `NetshNetworkAdapterConfigurator` | Translate a profile into netsh commands | `CommandRunner` |
| `ProcessCommandRunner` | Start an executable with an argument list, return exit code and output | – |
| `JsonNetworkProfileRepository` | Load/save profiles in `%APPDATA%\NetworkProfileSwitcher\profiles.json` | – |
| `NetworkProfileValidator` | Validate IP, subnet mask, gateway in same subnet, DNS addresses | – |
| `NetworkProfileApplier` | Use case: validate, apply, verify the result | validator, configurator, reader |
| View models | UI state and commands only, no network logic | applier, repository, reader |

## Model

`NetworkProfile` (immutable, with `toJson`/`fromJson`):
- `name` (String)
- `addressingMode` (dhcp | staticIp; `static` is reserved in Dart)
- `ipAddress`, `subnetMask` (required when staticIp)
- `defaultGateway` (optional)
- `dnsServers` (optional list)

A profile is independent of an adapter: the user picks the target adapter when
applying it.

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
powershell.exe -NoProfile -NonInteractive -Command <script>
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
  (`[Console]::OutputEncoding = [Text.Encoding]::UTF8`) so adapter names with
  non-ASCII characters survive.
- After applying, `NetworkProfileApplier` re-reads the adapter and compares,
  because netsh can report success before the setting is active. It retries
  the read (default 3 attempts, 1 s apart) and returns a sealed
  `ApplyProfileOutcome` (`ProfileApplied`, `ProfileInvalid`,
  `ProfileRejectedBySystem`, `ProfileNotActive` with per-setting mismatches,
  `ProfileNotVerified`) so the UI must handle every case.
- A DHCP profile is verified on addressing mode only; right after switching
  the adapter may still hold an APIPA address.
- `docs/architecture.html` visualizes the layers; update it when components
  are added or a build step is completed.
- Use `Platform.environment['APPDATA']` for the profile path instead of
  `path_provider`, which would add a company/app subfolder.
- `profiles.json` is `{"formatVersion": 1, "profiles": [...]}`, written to a
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

## UI

- Main window: adapter list (name, status, current IP, DHCP/static) on the
  left, profile list on the right, "Apply profile to selected adapter" button,
  and a "Switch to DHCP" shortcut.
- Profile editor: create, edit, delete profiles with inline validation.
- Tray icon: context menu per adapter with the profiles as items for
  one-click switching; closing the window hides it to the tray.

## Build order

1. `flutter create --platforms=windows`, manifest, lints; core models and contracts
2. `ProcessCommandRunner` + `NetshNetworkAdapterConfigurator` with tests
3. `PowerShellNetworkAdapterReader` with JSON-sample tests
4. `JsonNetworkProfileRepository` + `NetworkProfileValidator` with tests
5. `NetworkProfileApplier`
6. Flutter app: main view, profile editor
7. Tray menu
