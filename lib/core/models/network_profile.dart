import 'addressing_mode.dart';

/// A named set of IPv4 settings that can be applied to any network adapter.
///
/// A profile is not bound to an adapter: the user picks the target adapter
/// when applying it. Gateway and DNS servers are optional because direct
/// machine-to-machine connections usually have neither.
class NetworkProfile {
  const NetworkProfile({
    required this.name,
    required this.addressingMode,
    this.ipAddress,
    this.subnetMask,
    this.defaultGateway,
    this.dnsServers = const [],
  });

  factory NetworkProfile.fromJson(Map<String, Object?> json) {
    return NetworkProfile(
      name: json['name'] as String,
      addressingMode: AddressingMode.values.byName(
        json['addressingMode'] as String,
      ),
      ipAddress: json['ipAddress'] as String?,
      subnetMask: json['subnetMask'] as String?,
      defaultGateway: json['defaultGateway'] as String?,
      dnsServers: List<String>.from(
        json['dnsServers'] as List<Object?>? ?? const <Object?>[],
      ),
    );
  }

  final String name;
  final AddressingMode addressingMode;

  /// Required when [addressingMode] is [AddressingMode.staticIp].
  final String? ipAddress;

  /// Required when [addressingMode] is [AddressingMode.staticIp].
  final String? subnetMask;

  final String? defaultGateway;

  /// In priority order: the first entry becomes the primary DNS server.
  final List<String> dnsServers;

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'addressingMode': addressingMode.name,
      if (ipAddress != null) 'ipAddress': ipAddress,
      if (subnetMask != null) 'subnetMask': subnetMask,
      if (defaultGateway != null) 'defaultGateway': defaultGateway,
      if (dnsServers.isNotEmpty) 'dnsServers': dnsServers,
    };
  }
}
