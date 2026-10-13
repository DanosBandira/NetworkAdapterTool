import '../contracts/network_adapter_reader.dart';
import '../models/addressing_mode.dart';
import '../models/ipv4_address.dart';
import '../models/network_adapter.dart';
import 'nmcli_client.dart';

/// Reads adapters on Linux from NetworkManager: each wired or wireless
/// device together with the connection profile that holds its settings.
///
/// Like the Windows reader, a connected adapter shows its live address and
/// a disconnected static one shows the address stored in its connection, so
/// a profile can be recognized on both.
class NmcliNetworkAdapterReader implements NetworkAdapterReader {
  const NmcliNetworkAdapterReader(this._nmcli);

  static const _linkLocalPrefix = '169.254.';

  final NmcliClient _nmcli;

  @override
  Future<List<NetworkAdapter>> readAllAdapters() async {
    final devices = await _nmcli.readDevices();
    final connections = await _nmcli.readNetworkConnections();
    return [
      for (final device in devices)
        if (device.isNetworkCard)
          _adapterFrom(device, connectionOf(device, connections)),
    ];
  }

  @override
  Future<NetworkAdapter?> readAdapterByName(String adapterName) async {
    final adapters = await readAllAdapters();
    return adapters.where((adapter) => adapter.name == adapterName).firstOrNull;
  }

  /// The connection holding [device]'s settings: the active one, or else one
  /// bound to the device by name; `null` when the device has none yet.
  static NmcliConnection? connectionOf(
    NmcliDevice device,
    List<NmcliConnection> connections,
  ) {
    return connections
            .where((connection) => connection.activeDevice == device.name)
            .firstOrNull ??
        connections
            .where((connection) => connection.interfaceName == device.name)
            .firstOrNull;
  }

  NetworkAdapter _adapterFrom(NmcliDevice device, NmcliConnection? connection) {
    final usesLiveSettings = device.isConnected;
    final addressWithPrefix = usesLiveSettings
        ? _preferRoutableAddress(device.addressesWithPrefix)
        : connection?.addressesWithPrefix.firstOrNull;
    final (ipAddress, subnetMask) = _splitAddress(addressWithPrefix);
    return NetworkAdapter(
      name: device.name,
      description: _describe(device, connection),
      status: _statusOf(device),
      addressingMode: _addressingModeOf(connection),
      ipAddress: ipAddress,
      subnetMask: subnetMask,
      defaultGateway: usesLiveSettings ? device.gateway : connection?.gateway,
      dnsServers: usesLiveSettings
          ? device.dnsServers
          : connection?.dnsServers ?? const [],
    );
  }

  // Same rule as on Windows: a link-local address (169.254.x.x) only shows
  // when the device has no other address.
  String? _preferRoutableAddress(List<String> addressesWithPrefix) {
    return addressesWithPrefix
            .where((address) => !address.startsWith(_linkLocalPrefix))
            .firstOrNull ??
        addressesWithPrefix.firstOrNull;
  }

  (String?, String?) _splitAddress(String? addressWithPrefix) {
    if (addressWithPrefix == null) return (null, null);
    final [address, ...prefix] = addressWithPrefix.split('/');
    final prefixLength = int.tryParse(prefix.firstOrNull ?? '');
    final subnetMask = prefixLength == null || prefixLength > 32
        ? null
        : Ipv4Address.subnetMaskFromPrefixLength(prefixLength).toString();
    return (address, subnetMask);
  }

  String _describe(NmcliDevice device, NmcliConnection? connection) {
    final kind = device.type == 'wifi' ? 'Wi-Fi' : 'Ethernet';
    return connection == null ? kind : '$kind · ${connection.name}';
  }

  NetworkAdapterStatus _statusOf(NmcliDevice device) {
    if (device.isConnected) return NetworkAdapterStatus.connected;
    return switch (device.stateCode) {
      NmcliDevice.unmanagedStateCode => NetworkAdapterStatus.disabled,
      0 => NetworkAdapterStatus.unknown,
      _ => NetworkAdapterStatus.disconnected,
    };
  }

  // "disabled", "link-local" and "shared" have no IPv4 setting a profile
  // could describe; such an adapter shows like a disabled one on Windows.
  AddressingMode? _addressingModeOf(NmcliConnection? connection) {
    return switch (connection?.ipv4Method) {
      'auto' => AddressingMode.dhcp,
      'manual' => AddressingMode.staticIp,
      _ => null,
    };
  }
}
