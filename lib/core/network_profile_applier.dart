import 'contracts/network_adapter_configurator.dart';
import 'contracts/network_adapter_reader.dart';
import 'models/addressing_mode.dart';
import 'models/ipv4_address.dart';
import 'models/network_adapter.dart';
import 'models/network_profile.dart';
import 'profiles/network_profile_comparer.dart';
import 'profiles/network_profile_validator.dart';

export 'profiles/network_profile_comparer.dart'
    show AdapterSetting, AdapterSettingMismatch;

/// Use case: apply a profile to an adapter and confirm it took effect.
///
/// Steps: validate the profile, check that Windows can apply it to the
/// adapter in its current state, let the configurator apply it, then re-read
/// the adapter and compare. The re-read is needed because netsh can report
/// success before Windows activates a setting, and because netsh's
/// "DHCP already enabled" exit code also hides real errors.
class NetworkProfileApplier {
  const NetworkProfileApplier({
    required this._validator,
    required this._configurator,
    required this._reader,
    this._comparer = const NetworkProfileComparer(),
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
  final NetworkProfileComparer _comparer;

  Future<ApplyProfileOutcome> applyProfileToAdapter(
    NetworkProfile profile,
    String adapterName,
  ) async {
    final validationErrors = _validator.validate(profile);
    if (validationErrors.isNotEmpty) {
      return ProfileInvalid(validationErrors);
    }

    if (await _isDisconnectedDhcpAdapterGettingStaticAddress(
      profile,
      adapterName,
    )) {
      return const ProfileNeedsConnectedAdapter();
    }

    try {
      await _configurator.applyProfileToAdapter(profile, adapterName);
    } on NetworkConfigurationException catch (error) {
      return _explainRejection(profile, adapterName, error);
    }

    return _verifyProfileIsActive(profile, adapterName);
  }

  // Windows keeps DHCP enabled when a disconnected adapter is switched from
  // DHCP to a static address: netsh, Set-NetIPInterface and WMI EnableStatic
  // all report success but only store the address next to DHCP. Applying
  // anyway would leave that mixed state, so it is refused up front.
  // Static-to-static and switching to DHCP work while disconnected.
  //
  // Costs one extra adapter read, only for static profiles. When the read
  // fails the profile is applied anyway and verification reports the result.
  Future<bool> _isDisconnectedDhcpAdapterGettingStaticAddress(
    NetworkProfile profile,
    String adapterName,
  ) async {
    if (profile.addressingMode != AddressingMode.staticIp) return false;
    try {
      final adapter = await _reader.readAdapterByName(adapterName);
      return adapter != null &&
          adapter.addressingMode == AddressingMode.dhcp &&
          adapter.status != NetworkAdapterStatus.connected;
    } on NetworkAdapterReadException {
      return false;
    }
  }

  // Windows allows an IPv4 address on one adapter only; netsh then fails with
  // "The object already exists", also when the other adapter is
  // disconnected. netsh text is localized, so instead of parsing it the
  // other adapters are checked for the address, only after a rejection.
  Future<ApplyProfileOutcome> _explainRejection(
    NetworkProfile profile,
    String adapterName,
    NetworkConfigurationException error,
  ) async {
    final ipAddress = profile.ipAddress;
    if (profile.addressingMode != AddressingMode.staticIp ||
        ipAddress == null) {
      return ProfileRejectedBySystem(error);
    }
    try {
      final adapters = await _reader.readAllAdapters();
      for (final adapter in adapters) {
        final isOtherAdapter =
            adapter.name.toLowerCase() != adapterName.toLowerCase();
        if (isOtherAdapter &&
            Ipv4Address.tryParse(adapter.ipAddress ?? '') ==
                Ipv4Address.tryParse(ipAddress)) {
          return ProfileAddressInUse(
            ipAddress: ipAddress,
            otherAdapterName: adapter.name,
            error: error,
          );
        }
      }
    } on NetworkAdapterReadException {
      // The plain rejection below still tells the user what Windows said.
    }
    return ProfileRejectedBySystem(error);
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
    return _comparer.findMismatches(profile, adapter);
  }
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

/// Nothing was applied: Windows only switches an adapter from DHCP to a
/// static address while it is connected.
final class ProfileNeedsConnectedAdapter extends ApplyProfileOutcome {
  const ProfileNeedsConnectedAdapter();
}

/// Windows refused a setting; the adapter may be partly changed.
final class ProfileRejectedBySystem extends ApplyProfileOutcome {
  const ProfileRejectedBySystem(this.error);

  final NetworkConfigurationException error;
}

/// The commands succeeded, but the adapter still differs from the profile
/// after all verification attempts.
/// Windows refused the profile because its IP address is already set on
/// another adapter (possibly a disconnected one).
final class ProfileAddressInUse extends ApplyProfileOutcome {
  const ProfileAddressInUse({
    required this.ipAddress,
    required this.otherAdapterName,
    required this.error,
  });

  final String ipAddress;
  final String otherAdapterName;
  final NetworkConfigurationException error;
}

final class ProfileNotActive extends ApplyProfileOutcome {
  const ProfileNotActive(this.mismatches);

  final List<AdapterSettingMismatch> mismatches;
}

/// The profile was applied, but the adapter could not be read back.
final class ProfileNotVerified extends ApplyProfileOutcome {
  const ProfileNotVerified(this.error);

  final NetworkAdapterReadException error;
}
