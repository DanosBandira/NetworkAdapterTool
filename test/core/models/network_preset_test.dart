import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/models/network_preset.dart';

void main() {
  const preset = NetworkPreset(
    name: 'Line 1',
    assignments: [
      PresetAssignment(adapterName: 'Ethernet', profileName: 'Machine'),
      PresetAssignment(adapterName: 'Wi-Fi', profileName: 'Office'),
    ],
  );

  test('survives a JSON round trip', () {
    final restored = NetworkPreset.fromJson(preset.toJson());

    expect(restored.name, 'Line 1');
    expect(restored.assignments, preset.assignments);
  });

  test('knows which profiles it uses', () {
    expect(preset.usesProfile('Machine'), isTrue);
    expect(preset.usesProfile('Lab'), isFalse);
  });

  test('renames a profile in every line that uses it', () {
    final renamed = preset.withProfileRenamed('Machine', 'Machine 2');

    expect(renamed.assignments, const [
      PresetAssignment(adapterName: 'Ethernet', profileName: 'Machine 2'),
      PresetAssignment(adapterName: 'Wi-Fi', profileName: 'Office'),
    ]);
  });
}
