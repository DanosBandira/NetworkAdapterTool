import '../models/addressing_mode.dart';
import '../models/ipv4_address.dart';
import '../models/network_adapter.dart';
import '../models/network_profile.dart';

/// Compares a profile with an adapter's current settings: used to verify an
/// apply, and to show which profile is active on an adapter.
///
/// A DHCP profile matches on the addressing mode only; the address itself
/// comes from the DHCP server and may still be a temporary APIPA address
/// right after switching. A static profile also matches on IP address,
/// subnet mask, gateway and DNS servers (same order).
class NetworkProfileComparer {
  const NetworkProfileComparer();

  bool isActiveOn(NetworkProfile profile, NetworkAdapter adapter) =>
      findMismatches(profile, adapter).isEmpty;

  List<AdapterSettingMismatch> findMismatches(
    NetworkProfile profile,
    NetworkAdapter adapter,
  ) {
    return [
      ..._findAddressingModeMismatch(profile, adapter),
      if (profile.addressingMode == AddressingMode.staticIp)
        ..._findStaticSettingMismatches(profile, adapter),
    ];
  }

  Iterable<AdapterSettingMismatch> _findAddressingModeMismatch(
    NetworkProfile profile,
    NetworkAdapter adapter,
  ) sync* {
    if (adapter.addressingMode != profile.addressingMode) {
      yield AdapterSettingMismatch(
        setting: AdapterSetting.addressingMode,
        expected: profile.addressingMode.name,
        actual: adapter.addressingMode?.name,
      );
    }
  }

  Iterable<AdapterSettingMismatch> _findStaticSettingMismatches(
    NetworkProfile profile,
    NetworkAdapter adapter,
  ) sync* {
    yield* _findAddressMismatch(
      AdapterSetting.ipAddress,
      profile.ipAddress,
      adapter.ipAddress,
    );
    yield* _findAddressMismatch(
      AdapterSetting.subnetMask,
      profile.subnetMask,
      adapter.subnetMask,
    );
    yield* _findAddressMismatch(
      AdapterSetting.defaultGateway,
      _blankAsNull(profile.defaultGateway),
      adapter.defaultGateway,
    );
    yield* _findDnsServersMismatch(profile.dnsServers, adapter.dnsServers);
  }

  Iterable<AdapterSettingMismatch> _findAddressMismatch(
    AdapterSetting setting,
    String? expected,
    String? actual,
  ) sync* {
    if (!_isSameAddress(expected, actual)) {
      yield AdapterSettingMismatch(
        setting: setting,
        expected: expected,
        actual: actual,
      );
    }
  }

  Iterable<AdapterSettingMismatch> _findDnsServersMismatch(
    List<String> expected,
    List<String> actual,
  ) sync* {
    final sameServersInSameOrder =
        expected.length == actual.length &&
        [
          for (var index = 0; index < expected.length; index++)
            _isSameAddress(expected[index], actual[index]),
        ].every((isSame) => isSame);
    if (!sameServersInSameOrder) {
      yield AdapterSettingMismatch(
        setting: AdapterSetting.dnsServers,
        expected: expected.join(', '),
        actual: actual.join(', '),
      );
    }
  }

  bool _isSameAddress(String? first, String? second) {
    if (first == null || second == null) return first == second;
    return Ipv4Address.tryParse(first) == Ipv4Address.tryParse(second);
  }

  String? _blankAsNull(String? text) =>
      text == null || text.trim().isEmpty ? null : text;
}

/// The adapter setting that differs from the profile.
enum AdapterSetting {
  adapter,
  addressingMode,
  ipAddress,
  subnetMask,
  defaultGateway,
  dnsServers,
}

class AdapterSettingMismatch {
  const AdapterSettingMismatch({
    required this.setting,
    required this.expected,
    required this.actual,
  });

  final AdapterSetting setting;
  final String? expected;
  final String? actual;

  @override
  String toString() =>
      '${setting.name}: expected ${expected ?? 'none'}, '
      'actual ${actual ?? 'none'}';
}
