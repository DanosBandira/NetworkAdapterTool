import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/app/view_models/network_preset_editor_view_model.dart';
import 'package:network_adapter_tool/core/models/network_preset.dart';
import 'package:network_adapter_tool/core/profiles/network_preset_validator.dart';

void main() {
  NetworkPresetEditorViewModel newPresetEditor() {
    return NetworkPresetEditorViewModel(
      originalPreset: null,
      availableAdapterNames: const ['Ethernet', 'Wi-Fi'],
      profileNames: const ['Machine', 'Office'],
      otherPresetNames: const ['Evening'],
    );
  }

  test('starts a new preset with one empty line and no errors', () {
    final editor = newPresetEditor();

    expect(editor.isNewPreset, isTrue);
    expect(editor.lines, hasLength(1));
    expect(editor.errorFor(NetworkPresetField.name), isNull);
    expect(editor.errorFor(NetworkPresetField.assignments), isNull);
  });

  test('builds a preset from the edited lines', () {
    final editor = newPresetEditor()..updateName(' Morning ');
    final firstLine = editor.lines.single;
    editor
      ..updateLineAdapter(firstLine.id, 'Ethernet')
      ..updateLineProfile(firstLine.id, 'Machine')
      ..addLine();
    final secondLine = editor.lines.last;
    editor
      ..updateLineAdapter(secondLine.id, 'Wi-Fi')
      ..updateLineProfile(secondLine.id, 'Office');

    final savedPreset = editor.trySave()!;

    expect(savedPreset.name, 'Morning');
    expect(savedPreset.assignments, const [
      PresetAssignment(adapterName: 'Ethernet', profileName: 'Machine'),
      PresetAssignment(adapterName: 'Wi-Fi', profileName: 'Office'),
    ]);
  });

  test('reveals errors when saving incomplete input', () {
    final editor = newPresetEditor();

    expect(editor.trySave(), isNull);
    expect(editor.errorFor(NetworkPresetField.name), isNotNull);
    expect(editor.errorFor(NetworkPresetField.assignments), isNotNull);
  });

  test('rejects the name of another preset', () {
    final editor = newPresetEditor()..updateName('evening');

    expect(editor.errorFor(NetworkPresetField.name), isNotNull);
  });

  test('removes a line', () {
    final editor = newPresetEditor()..addLine();

    editor.removeLine(editor.lines.first.id);

    expect(editor.lines, hasLength(1));
  });

  test('keeps an adapter of the edited preset that is absent right now', () {
    final editor = NetworkPresetEditorViewModel(
      originalPreset: const NetworkPreset(
        name: 'Morning',
        assignments: [
          PresetAssignment(adapterName: 'USB LAN', profileName: 'Machine'),
        ],
      ),
      availableAdapterNames: const ['Ethernet'],
      profileNames: const ['Machine'],
      otherPresetNames: const [],
    );

    expect(editor.adapterNames, ['Ethernet', 'USB LAN']);
    expect(editor.lines.single.adapterName, 'USB LAN');
    expect(editor.trySave()!.assignments.single.adapterName, 'USB LAN');
  });
}
