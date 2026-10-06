import '../../core/models/addressing_mode.dart';
import '../../core/models/network_adapter.dart';

/// Display texts for one adapter in the adapter list.
///
/// Immutable: the main view model replaces it when the adapter is re-read.
class NetworkAdapterViewModel {
  const NetworkAdapterViewModel(this.adapter);

  final NetworkAdapter adapter;

  String get name => adapter.name;

  String get description => adapter.description;

  bool get isConnected => adapter.status == NetworkAdapterStatus.connected;

  String get statusText => switch (adapter.status) {
    NetworkAdapterStatus.connected => 'Connected',
    NetworkAdapterStatus.disconnected => 'Disconnected',
    NetworkAdapterStatus.disabled => 'Disabled',
    NetworkAdapterStatus.unknown => 'Unknown',
  };

  String get addressingModeText => switch (adapter.addressingMode) {
    AddressingMode.dhcp => 'DHCP',
    AddressingMode.staticIp => 'Static',
    null => '–',
  };

  String get addressText {
    final ipAddress = adapter.ipAddress;
    if (ipAddress == null) return 'No IPv4 address';
    final subnetMask = adapter.subnetMask;
    return subnetMask == null ? ipAddress : '$ipAddress / $subnetMask';
  }

  String? get gatewayText {
    final defaultGateway = adapter.defaultGateway;
    return defaultGateway == null ? null : 'Gateway $defaultGateway';
  }

  String? get dnsServersText => adapter.dnsServers.isEmpty
      ? null
      : 'DNS ${adapter.dnsServers.join(', ')}';
}
