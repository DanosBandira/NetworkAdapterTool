/// An address to ping after switching to a profile, e.g. a PLC or HMI on a
/// machine network.
class PingTarget {
  const PingTarget({required this.ipAddress, this.name});

  factory PingTarget.fromJson(Map<String, Object?> json) {
    return PingTarget(
      ipAddress: json['ipAddress'] as String,
      name: json['name'] as String?,
    );
  }

  final String ipAddress;

  /// Optional label shown next to the address, e.g. "PLC".
  final String? name;

  /// The name when set, otherwise the address.
  String get displayName {
    final name = this.name;
    return name == null || name.trim().isEmpty ? ipAddress : name;
  }

  Map<String, Object?> toJson() {
    return {'ipAddress': ipAddress, if (name != null) 'name': name};
  }

  @override
  bool operator ==(Object other) =>
      other is PingTarget && other.ipAddress == ipAddress && other.name == name;

  @override
  int get hashCode => Object.hash(ipAddress, name);
}
