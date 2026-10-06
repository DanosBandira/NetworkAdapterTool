/// An IPv4 address or subnet mask held as a 32-bit unsigned integer, so
/// subnet arithmetic is plain bit masking.
class Ipv4Address {
  const Ipv4Address._(this.value);

  factory Ipv4Address.subnetMaskFromPrefixLength(int prefixLength) {
    if (prefixLength < 0 || prefixLength > 32) {
      throw RangeError.range(prefixLength, 0, 32, 'prefixLength');
    }
    return Ipv4Address._((_allBits << (32 - prefixLength)) & _allBits);
  }

  static const _allBits = 0xFFFFFFFF;

  // Leading zeros are rejected because Windows parses "010" as octal (8),
  // which would silently apply a different address than the user typed.
  static final _dottedQuadPattern = RegExp(
    r'^(0|[1-9]\d{0,2})\.(0|[1-9]\d{0,2})\.(0|[1-9]\d{0,2})\.(0|[1-9]\d{0,2})$',
  );

  /// Parses strict dotted-quad notation; returns `null` for anything else.
  static Ipv4Address? tryParse(String text) {
    final match = _dottedQuadPattern.firstMatch(text.trim());
    if (match == null) return null;

    final octets = [
      for (var group = 1; group <= 4; group++) int.parse(match[group]!),
    ];
    if (octets.any((octet) => octet > 255)) return null;

    return Ipv4Address._(
      octets.fold(0, (accumulated, octet) => (accumulated << 8) | octet),
    );
  }

  final int value;

  int get firstOctet => value >> 24;

  /// The prefix length when this is a valid subnet mask (contiguous ones
  /// followed by zeros), otherwise `null`.
  int? get prefixLengthAsSubnetMask {
    final hostBits = ~value & _allBits;
    final hostBitsAreContiguous = (hostBits & (hostBits + 1)) == 0;
    return hostBitsAreContiguous ? 32 - hostBits.bitLength : null;
  }

  /// True for addresses a host interface may carry: excludes 0.0.0.0/8,
  /// loopback, multicast and the reserved/broadcast range.
  bool get isAssignableToHost =>
      firstOctet != 0 && firstOctet != 127 && firstOctet < 224;

  Ipv4Address networkAddress(Ipv4Address subnetMask) =>
      Ipv4Address._(value & subnetMask.value);

  Ipv4Address broadcastAddress(Ipv4Address subnetMask) =>
      Ipv4Address._(value | (~subnetMask.value & _allBits));

  bool isInSameSubnetAs(Ipv4Address other, Ipv4Address subnetMask) =>
      networkAddress(subnetMask) == other.networkAddress(subnetMask);

  @override
  bool operator ==(Object other) =>
      other is Ipv4Address && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() =>
      [24, 16, 8, 0].map((shift) => (value >> shift) & 0xFF).join('.');
}
