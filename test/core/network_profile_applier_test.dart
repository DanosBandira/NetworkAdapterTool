import 'package:flutter_test/flutter_test.dart';
import 'package:network_profile_switcher/core/contracts/network_adapter_configurator.dart';
import 'package:network_profile_switcher/core/contracts/network_adapter_reader.dart';
import 'package:network_profile_switcher/core/models/addressing_mode.dart';
import 'package:network_profile_switcher/core/models/network_adapter.dart';
import 'package:network_profile_switcher/core/models/network_profile.dart';
import 'package:network_profile_switcher/core/network_profile_applier.dart';
import 'package:network_profile_switcher/core/profiles/network_profile_validator.dart';

import '../fakes/fake_network_adapter_reader.dart';
import '../fakes/recording_network_adapter_configurator.dart';

void main() {
  const adapterName = 'Ethernet';

  const staticProfile = NetworkProfile(
    name: 'Machine',
    addressingMode: AddressingMode.staticIp,
    ipAddress: '192.168.0.10',
    subnetMask: '255.255.255.0',
    defaultGateway: '192.168.0.1',
    dnsServers: ['8.8.8.8', '1.1.1.1'],
  );

  const dhcpProfile = NetworkProfile(
    name: 'Office',
    addressingMode: AddressingMode.dhcp,
  );

  NetworkAdapter adapterSnapshot({
    AddressingMode? addressingMode = AddressingMode.staticIp,
    String? ipAddress = '192.168.0.10',
    String? subnetMask = '255.255.255.0',
    String? defaultGateway = '192.168.0.1',
    List<String> dnsServers = const ['8.8.8.8', '1.1.1.1'],
  }) {
    return NetworkAdapter(
      name: adapterName,
      description: 'Intel(R) Ethernet',
      status: NetworkAdapterStatus.connected,
      addressingMode: addressingMode,
      ipAddress: ipAddress,
      subnetMask: subnetMask,
      defaultGateway: defaultGateway,
      dnsServers: dnsServers,
    );
  }

  late RecordingNetworkAdapterConfigurator configurator;

  setUp(() {
    configurator = RecordingNetworkAdapterConfigurator();
  });

  NetworkProfileApplier applierReading(NetworkAdapterReader reader) {
    return NetworkProfileApplier(
      validator: const NetworkProfileValidator(),
      configurator: configurator,
      reader: reader,
      delayBetweenVerificationAttempts: Duration.zero,
    );
  }

  group('successful apply', () {
    test(
      'applies a static profile and returns the adapter read back',
      () async {
        final activeAdapter = adapterSnapshot();
        final applier = applierReading(
          FakeNetworkAdapterReader([activeAdapter]),
        );

        final outcome = await applier.applyProfileToAdapter(
          staticProfile,
          adapterName,
        );

        expect(outcome, isA<ProfileApplied>());
        expect((outcome as ProfileApplied).adapter, same(activeAdapter));
        expect(configurator.appliedProfiles.single, (
          staticProfile,
          adapterName,
        ));
      },
    );

    test('accepts a DHCP adapter that still has an APIPA address', () async {
      final applier = applierReading(
        FakeNetworkAdapterReader([
          adapterSnapshot(
            addressingMode: AddressingMode.dhcp,
            ipAddress: '169.254.10.20',
            subnetMask: '255.255.0.0',
            defaultGateway: null,
            dnsServers: [],
          ),
        ]),
      );

      final outcome = await applier.applyProfileToAdapter(
        dhcpProfile,
        adapterName,
      );

      expect(outcome, isA<ProfileApplied>());
    });

    test('waits until the setting becomes active', () async {
      final reader = FakeNetworkAdapterReader([
        adapterSnapshot(addressingMode: AddressingMode.dhcp),
        adapterSnapshot(ipAddress: '169.254.1.1'),
        adapterSnapshot(),
      ]);

      final outcome = await applierReading(reader)
          .applyProfileToAdapter(staticProfile, adapterName);

      expect(outcome, isA<ProfileApplied>());
      expect(reader.readCount, 3);
    });

    test('treats a blank gateway in the profile as no gateway', () async {
      const profileWithBlankGateway = NetworkProfile(
        name: 'Machine',
        addressingMode: AddressingMode.staticIp,
        ipAddress: '192.168.0.10',
        subnetMask: '255.255.255.0',
        defaultGateway: '',
      );
      final applier = applierReading(
        FakeNetworkAdapterReader([
          adapterSnapshot(defaultGateway: null, dnsServers: []),
        ]),
      );

      final outcome = await applier.applyProfileToAdapter(
        profileWithBlankGateway,
        adapterName,
      );

      expect(outcome, isA<ProfileApplied>());
    });
  });

  group('failed apply', () {
    test('does not touch the adapter when the profile is invalid', () async {
      const invalidProfile = NetworkProfile(
        name: 'Broken',
        addressingMode: AddressingMode.staticIp,
        ipAddress: '192.168.0.300',
        subnetMask: '255.255.255.0',
      );
      final reader = FakeNetworkAdapterReader([adapterSnapshot()]);

      final outcome = await applierReading(reader)
          .applyProfileToAdapter(invalidProfile, adapterName);

      expect(outcome, isA<ProfileInvalid>());
      expect(
        (outcome as ProfileInvalid).validationErrors.single.field,
        NetworkProfileField.ipAddress,
      );
      expect(configurator.appliedProfiles, isEmpty);
      expect(reader.readCount, 0);
    });

    test('reports a netsh error without verifying', () async {
      const netshError = NetworkConfigurationException(
        failedCommand: 'netsh.exe interface ipv4 set address',
        exitCode: 1,
        output: 'The parameter is incorrect.',
      );
      configurator = RecordingNetworkAdapterConfigurator(
        errorToThrow: netshError,
      );
      final reader = FakeNetworkAdapterReader([adapterSnapshot()]);

      final outcome = await applierReading(reader)
          .applyProfileToAdapter(staticProfile, adapterName);

      expect(outcome, isA<ProfileRejectedBySystem>());
      expect((outcome as ProfileRejectedBySystem).error, same(netshError));
      expect(reader.readCount, 0);
    });

    test(
      'lists every setting that is still different after all attempts',
      () async {
        final reader = FakeNetworkAdapterReader([
          adapterSnapshot(defaultGateway: null, dnsServers: ['8.8.8.8']),
        ]);

        final outcome = await applierReading(reader)
            .applyProfileToAdapter(staticProfile, adapterName);

        expect(outcome, isA<ProfileNotActive>());
        final mismatches = (outcome as ProfileNotActive).mismatches;
        expect(mismatches.map((mismatch) => mismatch.setting), [
          AdapterSetting.defaultGateway,
          AdapterSetting.dnsServers,
        ]);
        expect(mismatches.first.expected, '192.168.0.1');
        expect(mismatches.first.actual, isNull);
        expect(reader.readCount, 3);
      },
    );

    test('reports DNS servers in a different order as not active', () async {
      final applier = applierReading(
        FakeNetworkAdapterReader([
          adapterSnapshot(dnsServers: ['1.1.1.1', '8.8.8.8']),
        ]),
      );

      final outcome = await applier.applyProfileToAdapter(
        staticProfile,
        adapterName,
      );

      expect(
        (outcome as ProfileNotActive).mismatches.single.setting,
        AdapterSetting.dnsServers,
      );
    });

    test(
      'reports a DHCP profile on a still-static adapter as not active',
      () async {
        final applier = applierReading(
          FakeNetworkAdapterReader([adapterSnapshot()]),
        );

        final outcome = await applier.applyProfileToAdapter(
          dhcpProfile,
          adapterName,
        );

        final mismatch = (outcome as ProfileNotActive).mismatches.single;
        expect(mismatch.setting, AdapterSetting.addressingMode);
        expect(mismatch.expected, 'dhcp');
        expect(mismatch.actual, 'staticIp');
      },
    );

    // netsh's "DHCP already enabled" exit code also covers an unknown
    // adapter, so only the verification step can catch this.
    test('reports an adapter that does not exist', () async {
      final applier = applierReading(FakeNetworkAdapterReader([null]));

      final outcome = await applier.applyProfileToAdapter(
        dhcpProfile,
        'Ethernet 9',
      );

      final mismatch = (outcome as ProfileNotActive).mismatches.single;
      expect(mismatch.setting, AdapterSetting.adapter);
      expect(mismatch.expected, 'Ethernet 9');
    });

    test('reports when the adapter cannot be read back', () async {
      const readError = NetworkAdapterReadException('PowerShell exited');
      final applier = applierReading(
        FakeNetworkAdapterReader([], readError: readError),
      );

      final outcome = await applier.applyProfileToAdapter(
        staticProfile,
        adapterName,
      );

      expect(outcome, isA<ProfileNotVerified>());
      expect(configurator.appliedProfiles, hasLength(1));
    });
  });
}
