import '../contracts/network_adapter_configurator.dart';
import '../contracts/network_adapter_reader.dart';
import '../models/addressing_mode.dart';
import '../models/ipv4_address.dart';
import '../models/network_profile.dart';
import 'nmcli_client.dart';
import 'nmcli_network_adapter_reader.dart';

/// Applies a [NetworkProfile] on Linux by changing the NetworkManager
/// connection of the device and activating it.
///
/// `nmcli` rather than `ip`: `ip` only changes the live kernel state (gone
/// after a reboot or replug), does no DHCP or DNS, and NetworkManager
/// overwrites it. Changing the connection persists like netsh does. As on
/// Windows, settings a profile leaves out (gateway, DNS) are cleared
/// explicitly, so values from a previous profile do not linger.
class NmcliNetworkAdapterConfigurator implements NetworkAdapterConfigurator {
  const NmcliNetworkAdapterConfigurator(this._nmcli);

  // A DHCP server can take a while to answer; without a limit "connection
  // up" could block the app for NetworkManager's full DHCP timeout.
  static const _activationTimeoutSeconds = '30';

  final NmcliClient _nmcli;

  @override
  Future<void> applyProfileToAdapter(
    NetworkProfile profile,
    String adapterName,
  ) async {
    final device = await _deviceNamed(adapterName);
    final connectionUuid = await _connectionUuidFor(device);
    await _changeConnection(connectionUuid, profile);
    await _activateIfPossible(connectionUuid, device);
  }

  Future<NmcliDevice> _deviceNamed(String adapterName) async {
    final devices = await _readOrFail(_nmcli.readDevices, 'device show');
    final device = devices
        .where((device) => device.name == adapterName)
        .firstOrNull;
    if (device == null) {
      throw NetworkConfigurationException(
        failedCommand: '${NmcliClient.executable} device show',
        exitCode: 10,
        output: 'No network device named "$adapterName".',
      );
    }
    return device;
  }

  // A wired device without a connection gets one named after it. A Wi-Fi
  // connection needs a network name and password, so the user connects
  // once through the desktop's network settings instead.
  Future<String> _connectionUuidFor(NmcliDevice device) async {
    final existing = await _findConnectionUuid(device);
    if (existing != null) return existing;
    if (device.type != 'ethernet') {
      throw NetworkConfigurationException(
        failedCommand: '${NmcliClient.executable} connection show',
        exitCode: 10,
        output:
            '${device.name} has no saved connection. Connect it to a Wi-Fi '
            'network once in the system settings, then try again.',
      );
    }
    await _runOrFail([
      'connection',
      'add',
      'type',
      'ethernet',
      'ifname',
      device.name,
      'con-name',
      device.name,
    ]);
    final created = await _findConnectionUuid(device);
    if (created == null) {
      throw NetworkConfigurationException(
        failedCommand: '${NmcliClient.executable} connection add',
        exitCode: 0,
        output: 'The new connection for ${device.name} was not found.',
      );
    }
    return created;
  }

  Future<String?> _findConnectionUuid(NmcliDevice device) async {
    final connections = await _readOrFail(
      _nmcli.readNetworkConnections,
      'connection show',
    );
    return NmcliNetworkAdapterReader.connectionOf(device, connections)?.uuid;
  }

  Future<void> _changeConnection(String uuid, NetworkProfile profile) async {
    await _runOrFail([
      'connection',
      'modify',
      'uuid',
      uuid,
      ...switch (profile.addressingMode) {
        AddressingMode.dhcp => _dhcpSettings(),
        AddressingMode.staticIp => _staticSettings(profile),
      },
    ]);
  }

  // DHCP: clear the static values too, so switching back to static later
  // starts clean and nothing stale is listed in the connection.
  List<String> _dhcpSettings() => [
    'ipv4.method',
    'auto',
    'ipv4.addresses',
    '',
    'ipv4.gateway',
    '',
    'ipv4.dns',
    '',
    'ipv4.ignore-auto-dns',
    'no',
  ];

  // All settings in one "modify": NetworkManager checks the result as a
  // whole, while "manual" set on its own is refused without an address.
  List<String> _staticSettings(NetworkProfile profile) {
    final prefixLength = Ipv4Address.tryParse(profile.subnetMask ?? '')
        ?.prefixLengthAsSubnetMask;
    final gateway = profile.defaultGateway?.trim() ?? '';
    return [
      'ipv4.method',
      'manual',
      'ipv4.addresses',
      '${profile.ipAddress}/$prefixLength',
      'ipv4.gateway',
      gateway,
      'ipv4.dns',
      profile.dnsServers.join(','),
      'ipv4.ignore-auto-dns',
      'yes',
    ];
  }

  // Without a cable the device is "unavailable" and cannot be activated; the
  // changed connection is stored and NetworkManager uses it once the cable
  // is plugged in. That matches Windows storing settings of a disconnected
  // adapter.
  Future<void> _activateIfPossible(String uuid, NmcliDevice device) async {
    if (device.stateCode <= NmcliDevice.unavailableStateCode) return;
    await _runOrFail([
      '--wait',
      _activationTimeoutSeconds,
      'connection',
      'up',
      'uuid',
      uuid,
      'ifname',
      device.name,
    ]);
  }

  Future<void> _runOrFail(List<String> arguments) async {
    final result = await _nmcli.runForResult(arguments);
    if (result.exitCode != 0) {
      throw NetworkConfigurationException(
        failedCommand: '${NmcliClient.executable} ${arguments.join(' ')}',
        exitCode: result.exitCode,
        output: '${result.standardOutput}${result.standardError}'.trim(),
      );
    }
  }

  Future<T> _readOrFail<T>(
    Future<T> Function() read,
    String description,
  ) async {
    try {
      return await read();
    } on NetworkAdapterReadException catch (error) {
      throw NetworkConfigurationException(
        failedCommand: '${NmcliClient.executable} $description',
        exitCode: 1,
        output: error.reason,
      );
    }
  }
}
