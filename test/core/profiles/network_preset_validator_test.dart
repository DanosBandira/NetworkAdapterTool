import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/models/network_preset.dart';
import 'package:network_adapter_tool/core/profiles/network_preset_validator.dart';

void main() {
  const validator = NetworkPresetValidator();
  const existingProfileNames = ['Machine', 'Office'];

  NetworkPreset preset({
    String name = 'Line 1',
    List<PresetAssignment> assignments = const [
      PresetAssignment(adapterName: 'Ethernet', profileName: 'Machine'),
    ],
  }) {
    return NetworkPreset(name: name, assignments: assignments);
  }

  List<NetworkPresetValidationError> validate(
    NetworkPreset preset, {
    List<String> otherPresetNames = const [],
  }) {
    return validator.validate(
      preset,
      existingProfileNames: existingProfileNames,
      otherPresetNames: otherPresetNames,
    );
  }

  test('accepts a complete preset', () {
    final completePreset = preset(
      assignments: const [
        PresetAssignment(adapterName: 'Ethernet', profileName: 'Machine'),
        PresetAssignment(adapterName: 'Wi-Fi', profileName: 'Office'),
      ],
    );

    expect(validate(completePreset), isEmpty);
  });

  test('accepts an adapter that is not present right now', () {
    final presetWithUsbAdapter = preset(
      assignments: const [
        PresetAssignment(adapterName: 'USB LAN', profileName: 'Machine'),
      ],
    );

    expect(validate(presetWithUsbAdapter), isEmpty);
  });

  test('requires a name', () {
    expect(validate(preset(name: ' ')).single.field, NetworkPresetField.name);
  });

  test('requires a unique name, ignoring case', () {
    final errors = validate(
      preset(name: 'line 1'),
      otherPresetNames: ['Line 1'],
    );

    expect(errors.single.field, NetworkPresetField.name);
  });

  test('requires at least one line', () {
    final errors = validate(preset(assignments: const []));

    expect(errors.single.message, 'Add at least one adapter.');
  });

  test('requires an adapter and a profile on every line', () {
    final errors = validate(
      preset(
        assignments: const [
          PresetAssignment(adapterName: '', profileName: 'Machine'),
        ],
      ),
    );

    expect(errors.single.field, NetworkPresetField.assignments);
  });

  test('rejects a profile that does not exist', () {
    final errors = validate(
      preset(
        assignments: const [
          PresetAssignment(adapterName: 'Ethernet', profileName: 'Gone'),
        ],
      ),
    );

    expect(errors.single.message, contains('"Gone"'));
  });

  test('rejects the same adapter twice', () {
    final errors = validate(
      preset(
        assignments: const [
          PresetAssignment(adapterName: 'Ethernet', profileName: 'Machine'),
          PresetAssignment(adapterName: 'ethernet', profileName: 'Office'),
        ],
      ),
    );

    expect(errors.single.message, contains('used more than once'));
  });
}
