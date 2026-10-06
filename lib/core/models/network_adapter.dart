import 'addressing_mode.dart';

/// Connection state of a network adapter as reported by Windows.
enum NetworkAdapterStatus { connected, disconnected, disabled, unknown }

/// A snapshot of a network adapter and its current IPv4 settings, as read
/// from the system at one moment in time.
class NetworkAdapter {
  const NetworkAdapter({
    required this.name,
    required this.description,
    required this.status,
    required this.addressingMode,
    this.ipAddress,
    this.subnetMask,
    this.defaultGateway,
    this.dnsServers = const [],
  });

  /// The interface alias (e.g. "Ethernet 2"); this is the name netsh expects.
  final String name;

  /// The hardware description (e.g. "Intel(R) Ethernet Connection I219-LM").
  final String description;

  final NetworkAdapterStatus status;
  final AddressingMode addressingMode;
  final String? ipAddress;
  final String? subnetMask;
  final String? defaultGateway;
  final List<String> dnsServers;
}
