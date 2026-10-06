import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/contracts/network_adapter_reader.dart';
import 'package:network_adapter_tool/core/models/addressing_mode.dart';
import 'package:network_adapter_tool/core/models/network_adapter.dart';
import 'package:network_adapter_tool/core/models/network_preset.dart';
import 'package:network_adapter_tool/core/models/network_profile.dart';
import 'package:network_adapter_tool/core/network_preset_applier.dart';
import 'package:network_adapter_tool/core/network_profile_applier.dart';
import 'package:network_adapter_tool/core/profiles/network_profile_validator.dart';

import '../fakes/recording_network_adapter_configurator.dart';

void main() {
  const officeProfile = NetworkProfile(
    name: 'Office',
    addressingMode: AddressingMode.dhcp,
  );
  const labProfile = NetworkProfile(
    name: 'Lab',
    addressingMode: AddressingMode.dhcp,
  );

  late RecordingNetworkAdapterConfigurator configurator;

  setUp(() {
    configurator = RecordingNetworkAdapterConfigurator();
  });

  NetworkPresetApplier presetApplierWithAdapters(List<String> adapterNames) {
    return NetworkPresetApplier(
      NetworkProfileApplier(
        validator: const NetworkProfileValidator(),
        configurator: configurator,
        reader: _DhcpAdaptersReader(adapterNames),
        verificationAttempts: 1,
      ),
    );
  }

  test('applies every line in order', () async {
    const preset = NetworkPreset(
      name: 'Line 1',
      assignments: [
        PresetAssignment(adapterName: 'Ethernet', profileName: 'Office'),
        PresetAssignment(adapterName: 'Wi-Fi', profileName: 'Lab'),
      ],
    );

    final results = await presetApplierWithAdapters(['Ethernet', 'Wi-Fi'])
        .applyPreset(preset, [officeProfile, labProfile])
        .toList();

    expect(results.every((result) => result.isSuccess), isTrue);
    expect(configurator.appliedProfiles, [
      (officeProfile, 'Ethernet'),
      (labProfile, 'Wi-Fi'),
    ]);
  });

  test('continues after a failing line', () async {
    const preset = NetworkPreset(
      name: 'Line 1',
      assignments: [
        PresetAssignment(adapterName: 'Missing adapter', profileName: 'Office'),
        PresetAssignment(adapterName: 'Wi-Fi', profileName: 'Lab'),
      ],
    );

    final results = await presetApplierWithAdapters(['Wi-Fi'])
        .applyPreset(preset, [officeProfile, labProfile])
        .toList();

    expect(results.map((result) => result.isSuccess), [false, true]);
    expect(results.first.outcome, isA<ProfileNotActive>());
  });

  test('reports a line whose profile no longer exists', () async {
    const preset = NetworkPreset(
      name: 'Line 1',
      assignments: [
        PresetAssignment(adapterName: 'Ethernet', profileName: 'Gone'),
      ],
    );

    final result = (await presetApplierWithAdapters([
      'Ethernet',
    ]).applyPreset(preset, [officeProfile]).toList()).single;

    expect(result.isSuccess, isFalse);
    expect(result.outcome, isNull);
    expect(result.profile, isNull);
    expect(configurator.appliedProfiles, isEmpty);
  });
}

/// Reports every named adapter as connected and on DHCP.
class _DhcpAdaptersReader implements NetworkAdapterReader {
  _DhcpAdaptersReader(this._adapterNames);

  final List<String> _adapterNames;

  @override
  Future<List<NetworkAdapter>> readAllAdapters() async => [
    for (final name in _adapterNames) _dhcpAdapter(name),
  ];

  @override
  Future<NetworkAdapter?> readAdapterByName(String adapterName) async =>
      _adapterNames.contains(adapterName) ? _dhcpAdapter(adapterName) : null;

  NetworkAdapter _dhcpAdapter(String name) => NetworkAdapter(
    name: name,
    description: name,
    status: NetworkAdapterStatus.connected,
    addressingMode: AddressingMode.dhcp,
  );
}
