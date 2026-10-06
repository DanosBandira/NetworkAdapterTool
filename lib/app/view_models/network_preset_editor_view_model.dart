import 'package:flutter/foundation.dart';

import '../../core/models/network_preset.dart';
import '../../core/profiles/network_preset_validator.dart';

/// State of the preset editor dialog: the name and the adapter/profile lines,
/// with inline validation.
///
/// Errors show only after the user edited a field or tried to save, like in
/// the profile editor.
class NetworkPresetEditorViewModel extends ChangeNotifier {
  NetworkPresetEditorViewModel({
    required this.originalPreset,
    required List<String> availableAdapterNames,
    required this.profileNames,
    required this._otherPresetNames,
    this._validator = const NetworkPresetValidator(),
  }) : _name = originalPreset?.name ?? '',
       adapterNames = _withAdaptersOfPreset(
         availableAdapterNames,
         originalPreset,
       ) {
    for (final assignment
        in originalPreset?.assignments ?? <PresetAssignment>[]) {
      _lines.add(
        PresetLineDraft._(
          _nextLineId++,
          adapterName: assignment.adapterName,
          profileName: assignment.profileName,
        ),
      );
    }
    if (_lines.isEmpty) addLine();
  }

  /// `null` when creating a new preset.
  final NetworkPreset? originalPreset;

  /// Adapters to choose from: the ones present now plus any the edited
  /// preset names that are currently absent (e.g. an unplugged USB adapter),
  /// so editing never silently drops a line.
  final List<String> adapterNames;

  final List<String> profileNames;

  final List<String> _otherPresetNames;
  final NetworkPresetValidator _validator;

  String _name;
  final List<PresetLineDraft> _lines = [];
  int _nextLineId = 0;
  final Set<NetworkPresetField> _editedFields = {};
  bool _saveWasAttempted = false;

  bool get isNewPreset => originalPreset == null;
  String get name => _name;
  List<PresetLineDraft> get lines => List.unmodifiable(_lines);

  void updateName(String name) {
    _name = name;
    _markEdited(NetworkPresetField.name);
  }

  void addLine() {
    _lines.add(PresetLineDraft._(_nextLineId++));
    notifyListeners();
  }

  void updateLineAdapter(int lineId, String adapterName) {
    _lineWithId(lineId).adapterName = adapterName;
    _markEdited(NetworkPresetField.assignments);
  }

  void updateLineProfile(int lineId, String profileName) {
    _lineWithId(lineId).profileName = profileName;
    _markEdited(NetworkPresetField.assignments);
  }

  void removeLine(int lineId) {
    _lines.removeWhere((line) => line.id == lineId);
    _markEdited(NetworkPresetField.assignments);
  }

  /// All messages for [field] joined, or `null` when there is nothing to
  /// show (yet).
  String? errorFor(NetworkPresetField field) {
    final mayShowError = _saveWasAttempted || _editedFields.contains(field);
    if (!mayShowError) return null;
    final messages = [
      for (final error in _validate(_buildPreset()))
        if (error.field == field) error.message,
    ];
    return messages.isEmpty ? null : messages.join('\n');
  }

  /// Returns the preset to save, or `null` and reveals every error when the
  /// input is not valid.
  NetworkPreset? trySave() {
    _saveWasAttempted = true;
    final preset = _buildPreset();
    if (_validate(preset).isNotEmpty) {
      notifyListeners();
      return null;
    }
    return preset;
  }

  void _markEdited(NetworkPresetField field) {
    _editedFields.add(field);
    notifyListeners();
  }

  PresetLineDraft _lineWithId(int lineId) =>
      _lines.firstWhere((line) => line.id == lineId);

  List<NetworkPresetValidationError> _validate(NetworkPreset preset) =>
      _validator.validate(
        preset,
        existingProfileNames: profileNames,
        otherPresetNames: _otherPresetNames,
      );

  NetworkPreset _buildPreset() {
    return NetworkPreset(
      name: _name.trim(),
      assignments: [
        for (final line in _lines)
          PresetAssignment(
            adapterName: line.adapterName ?? '',
            profileName: line.profileName ?? '',
          ),
      ],
    );
  }

  static List<String> _withAdaptersOfPreset(
    List<String> availableAdapterNames,
    NetworkPreset? preset,
  ) {
    return [
      ...availableAdapterNames,
      for (final assignment in preset?.assignments ?? <PresetAssignment>[])
        if (!availableAdapterNames.contains(assignment.adapterName))
          assignment.adapterName,
    ];
  }
}

/// One editable adapter/profile line in the preset editor.
///
/// The [id] stays stable while lines are added and removed, so the view can
/// key each row to the right draft.
class PresetLineDraft {
  PresetLineDraft._(this.id, {this.adapterName, this.profileName});

  final int id;
  String? adapterName;
  String? profileName;
}
