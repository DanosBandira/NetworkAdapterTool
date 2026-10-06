import 'contracts/network_adapter_configurator.dart';
import 'contracts/network_adapter_reader.dart';
import 'models/addressing_mode.dart';
import 'models/ipv4_address.dart';
import 'models/network_adapter.dart';
import 'models/network_profile.dart';
import 'profiles/network_profile_validator.dart';

/// Use case: apply a profile to an adapter and confirm it took effect.
///
/// Steps: validate the profile, let the configurator apply it, then re-read
/// the adapter and compare. The re-read is needed because netsh can report
/// success before Windows activates a setting, and because netsh's
/// "DHCP already enabled" exit code also hides real errors.
class NetworkProfileApplier {
  const NetworkProfileApplier({
    required this._validator,
    required this._configurator,
    required this._reader,
    this.verificationAttempts = 3,
    this.delayBetweenVerificationAttempts = const Duration(seconds: 1),
  });

  /// How often the adapter is re-read before the profile counts as not
  /// active. Each read already takes a few seconds (see the reader).
  final int verificationAttempts;
  final Duration delayBetweenVerificationAttempts;

  final NetworkProfileValidator _validator;
  final NetworkAdapterConfigurator _configurator;
  final NetworkAdapterReader _reader;

  Future<ApplyProfileOutcome> applyProfileToAdapter(
    NetworkProfile profile,
    String adapterName,
  ) async {
    final validationErrors = _validator.validate(profile);
    if (validationErrors.isNotEmpty) {
      return ProfileInvalid(validationErrors);
    }

    try {
      await _configurator.applyProfileToAdapter(profile, adapterName);
    } on NetworkConfigurationException catch (error) {
      return ProfileRejectedBySystem(error);
    }

    return _verifyProfileIsActive(profile, adapterName);
  }

  Future<ApplyProfileOutcome> _verifyProfileIsActive(
    NetworkProfile profile,
    String adapterName,
  ) async {
    try {
      var mismatches = <AdapterSettingMismatch>[];
      for (var attempt = 1; attempt <= verificationAttempts; attempt++) {
        final adapter = await _reader.readAdapterByName(adapterName);
        mismatches = _findMismatches(profile, adapterName, adapter);
        if (mismatches.isEmpty) return ProfileApplied(adapter!);
        if (attempt < verificationAttempts) {
          await Future<void>.delayed(delayBetweenVerificationAttempts);
        }
      }
      return ProfileNotActive(mismatches);
    } on NetworkAdapterReadException catch (error) {
      return ProfileNotVerified(error);
    }
  }

  List<AdapterSettingMismatch> _findMismatches(
    NetworkProfile profile,
    String adapterName,
    NetworkAdapter? adapter,
  ) {
    if (adapter == null) {
      return [
        AdapterSettingMismatch(
          setting: AdapterSetting.adapter,
          expected: adapterName,
          actual: null,
        ),
      ];
    }
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

  // DHCP profiles stop at the addressing mode: the address itself comes from
  // the DHCP server and may still be a temporary APIPA address right after
  // switching.
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

/// The adapter setting that differs from the applied profile.
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

/// Result of [NetworkProfileApplier.applyProfileToAdapter]. Sealed so the UI
/// has to handle every case.
sealed class ApplyProfileOutcome {
  const ApplyProfileOutcome();
}

/// The profile is active on the adapter.
final class ProfileApplied extends ApplyProfileOutcome {
  const ProfileApplied(this.adapter);

  /// The adapter as read back after applying.
  final NetworkAdapter adapter;
}

/// The profile was not applied because it is incomplete or inconsistent.
final class ProfileInvalid extends ApplyProfileOutcome {
  const ProfileInvalid(this.validationErrors);

  final List<NetworkProfileValidationError> validationErrors;
}

/// Windows refused a setting; the adapter may be partly changed.
final class ProfileRejectedBySystem extends ApplyProfileOutcome {
  const ProfileRejectedBySystem(this.error);

  final NetworkConfigurationException error;
}

/// The commands succeeded, but the adapter still differs from the profile
/// after all verification attempts.
final class ProfileNotActive extends ApplyProfileOutcome {
  const ProfileNotActive(this.mismatches);

  final List<AdapterSettingMismatch> mismatches;
}

/// The profile was applied, but the adapter could not be read back.
final class ProfileNotVerified extends ApplyProfileOutcome {
  const ProfileNotVerified(this.error);

  final NetworkAdapterReadException error;
}
