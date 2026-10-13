import 'dart:convert';
import 'dart:io';

import '../contracts/command_runner.dart';
import '../contracts/network_adapter_reader.dart';

/// Reads devices and connection profiles from NetworkManager through `nmcli`
/// in terse mode (`-t`), which is meant for scripts: no column alignment,
/// `:` between fields and `\:` for a colon inside a value.
///
/// NetworkManager splits what Windows calls an adapter in two: the device
/// (`enp3s0`, with its live state and addresses) and a connection profile
/// (the stored settings, DHCP or static). Both are needed to describe one
/// adapter.
class NmcliClient {
  const NmcliClient(this._commandRunner);

  static const executable = 'nmcli';

  // nmcli exits with 8 when NetworkManager is not running, e.g. on servers
  // that use systemd-networkd or a minimal install.
  static const networkManagerNotRunningExitCode = 8;

  // The shell's code for "command not found", used when nmcli is missing.
  static const notInstalledExitCode = 127;

  static const _deviceFields = [
    'GENERAL.DEVICE',
    'GENERAL.TYPE',
    'GENERAL.STATE',
    'GENERAL.CONNECTION',
    'IP4.ADDRESS',
    'IP4.GATEWAY',
    'IP4.DNS',
  ];

  static const _connectionListFields = ['NAME', 'UUID', 'TYPE', 'DEVICE'];

  static const _connectionSettingFields = [
    'connection.interface-name',
    'ipv4.method',
    'ipv4.addresses',
    'ipv4.gateway',
    'ipv4.dns',
  ];

  final CommandRunner _commandRunner;

  /// Every device NetworkManager knows, including loopback and virtual ones.
  Future<List<NmcliDevice>> readDevices() async {
    final output = await run([
      '-t',
      '-f',
      _deviceFields.join(','),
      'device',
      'show',
    ]);
    return [
      for (final record in parseTerseRecords(output))
        NmcliDevice.fromRecord(record),
    ];
  }

  /// The saved connection profiles of a wired or wireless type, with their
  /// IPv4 settings.
  Future<List<NmcliConnection>> readNetworkConnections() async {
    final output = await run([
      '-t',
      '-f',
      _connectionListFields.join(','),
      'connection',
      'show',
    ]);
    final connections = <NmcliConnection>[];
    for (final line in const LineSplitter().convert(output)) {
      if (line.trim().isEmpty) continue;
      final fields = splitTerseFields(line);
      if (fields.length < _connectionListFields.length) continue;
      final [name, uuid, type, activeDevice, ...] = fields;
      if (!NmcliConnection.isNetworkType(type)) continue;
      connections.add(
        NmcliConnection(
          name: name,
          uuid: uuid,
          type: type,
          activeDevice: activeDevice.isEmpty ? null : activeDevice,
          settings: await _readConnectionSettings(uuid),
        ),
      );
    }
    return connections;
  }

  /// Runs nmcli and returns its standard output.
  ///
  /// Throws [NetworkAdapterReadException] when nmcli fails; callers that
  /// change settings translate that into their own error.
  Future<String> run(List<String> arguments) async {
    final result = await runForResult(arguments);
    if (result.exitCode == notInstalledExitCode) {
      throw const NetworkAdapterReadException(
        'nmcli was not found. Install NetworkManager to use this app.',
      );
    }
    if (result.exitCode == networkManagerNotRunningExitCode) {
      throw const NetworkAdapterReadException(
        'NetworkManager is not running. This app changes network settings '
        'through NetworkManager (nmcli).',
      );
    }
    if (result.exitCode != 0) {
      throw NetworkAdapterReadException(
        'nmcli exited with code ${result.exitCode}: '
        '${result.standardError.trim()}',
      );
    }
    return result.standardOutput;
  }

  /// Runs nmcli and returns the result as it is, for callers that decide on
  /// the exit code themselves.
  Future<CommandResult> runForResult(List<String> arguments) async {
    try {
      // nmcli writes UTF-8 whatever the locale; connection names may contain
      // any character.
      return await _commandRunner.run(
        executable,
        arguments,
        outputEncoding: utf8,
      );
    } on ProcessException catch (error) {
      return CommandResult(
        exitCode: notInstalledExitCode,
        standardOutput: '',
        standardError: 'nmcli could not be started: ${error.message}',
      );
    }
  }

  Future<Map<String, List<String>>> _readConnectionSettings(String uuid) async {
    final output = await run([
      '-t',
      '-f',
      _connectionSettingFields.join(','),
      'connection',
      'show',
      'uuid',
      uuid,
    ]);
    final records = parseTerseRecords(output);
    return records.isEmpty ? const {} : records.first;
  }

  /// Splits `key:value` output into records, one per blank-line separated
  /// block. Numbered keys such as `IP4.ADDRESS[1]` and `IP4.ADDRESS[2]` are
  /// collected under `IP4.ADDRESS`, in order.
  static List<Map<String, List<String>>> parseTerseRecords(String output) {
    final records = <Map<String, List<String>>>[];
    var current = <String, List<String>>{};
    for (final line in const LineSplitter().convert(output)) {
      if (line.trim().isEmpty) {
        if (current.isNotEmpty) records.add(current);
        current = {};
        continue;
      }
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final key = line
          .substring(0, separator)
          .replaceFirst(RegExp(r'\[\d+\]$'), '');
      final value = _unescape(line.substring(separator + 1));
      // A field that is set on another record starts a new one, for output
      // without blank lines between devices.
      if (key == 'GENERAL.DEVICE' && current.containsKey(key)) {
        records.add(current);
        current = {};
      }
      current.putIfAbsent(key, () => []).add(value);
    }
    if (current.isNotEmpty) records.add(current);
    return records;
  }

  /// Splits one line of terse table output at the `:` that are not escaped.
  static List<String> splitTerseFields(String line) {
    final fields = <String>[];
    final field = StringBuffer();
    for (var index = 0; index < line.length; index++) {
      final character = line[index];
      if (character == r'\' && index + 1 < line.length) {
        field.write(line[++index]);
      } else if (character == ':') {
        fields.add(field.toString());
        field.clear();
      } else {
        field.write(character);
      }
    }
    fields.add(field.toString());
    return fields;
  }

  static String _unescape(String value) =>
      value.replaceAllMapped(RegExp(r'\\(.)'), (match) => match[1]!);
}

/// One NetworkManager device with its live state.
class NmcliDevice {
  const NmcliDevice({
    required this.name,
    required this.type,
    required this.stateCode,
    required this.activeConnectionName,
    required this.addressesWithPrefix,
    required this.gateway,
    required this.dnsServers,
  });

  factory NmcliDevice.fromRecord(Map<String, List<String>> record) {
    String? single(String key) => _valueOrNull(record[key]?.firstOrNull);
    return NmcliDevice(
      name: single('GENERAL.DEVICE') ?? '',
      type: single('GENERAL.TYPE') ?? '',
      stateCode: _stateCodeOf(single('GENERAL.STATE')),
      activeConnectionName: single('GENERAL.CONNECTION'),
      addressesWithPrefix: _valuesOf(record['IP4.ADDRESS']),
      gateway: single('IP4.GATEWAY'),
      dnsServers: _valuesOf(record['IP4.DNS']),
    );
  }

  // The state reads "100 (connected)"; the text is localized, the number
  // is not.
  static const connectedStateCode = 100;
  static const unmanagedStateCode = 10;

  // "unavailable": NetworkManager cannot activate the device now, for a
  // wired device usually because no cable is plugged in.
  static const unavailableStateCode = 20;

  final String name;

  /// "ethernet", "wifi", "loopback", "bridge", ...
  final String type;
  final int stateCode;
  final String? activeConnectionName;

  /// "10.100.10.4/24"
  final List<String> addressesWithPrefix;
  final String? gateway;
  final List<String> dnsServers;

  bool get isConnected => stateCode == connectedStateCode;

  /// Wired and wireless network cards; the app leaves loopback, bridges,
  /// tunnels and virtual devices alone.
  bool get isNetworkCard => type == 'ethernet' || type == 'wifi';

  static int _stateCodeOf(String? state) {
    final number = RegExp(r'^\d+').firstMatch(state ?? '')?[0];
    return number == null ? 0 : int.parse(number);
  }
}

/// One saved NetworkManager connection profile with its IPv4 settings.
class NmcliConnection {
  const NmcliConnection({
    required this.name,
    required this.uuid,
    required this.type,
    required this.activeDevice,
    required this.settings,
  });

  // Older nmcli versions list the setting name ("802-3-ethernet"), newer
  // ones the short type ("ethernet").
  static const _networkTypes = {
    'ethernet',
    '802-3-ethernet',
    'wifi',
    '802-11-wireless',
  };

  final String name;
  final String uuid;
  final String type;

  /// The device this connection is active on, `null` while inactive.
  final String? activeDevice;
  final Map<String, List<String>> settings;

  static bool isNetworkType(String type) => _networkTypes.contains(type);

  /// The device this connection is bound to, `null` when it may run on any.
  String? get interfaceName =>
      _valueOrNull(settings['connection.interface-name']?.firstOrNull);

  /// "auto" (DHCP), "manual" (static), "disabled", "link-local", "shared".
  String? get ipv4Method => _valueOrNull(settings['ipv4.method']?.firstOrNull);

  /// "10.100.10.4/24"; empty for DHCP.
  List<String> get addressesWithPrefix =>
      _listValuesOf(settings['ipv4.addresses']);

  String? get gateway => _valueOrNull(settings['ipv4.gateway']?.firstOrNull);

  List<String> get dnsServers => _listValuesOf(settings['ipv4.dns']);
}

// nmcli prints "--" for an empty value in some versions and modes.
String? _valueOrNull(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty || trimmed == '--' ? null : trimmed;
}

List<String> _valuesOf(List<String>? values) => [
  for (final value in values ?? const <String>[]) ?_valueOrNull(value),
];

// A list setting is one value separated by commas (and spaces in older
// versions), e.g. "8.8.8.8,1.1.1.1".
List<String> _listValuesOf(List<String>? values) => [
  for (final value in _valuesOf(values))
    for (final part in value.split(RegExp(r'[,\s]+')))
      if (part.isNotEmpty) part,
];
