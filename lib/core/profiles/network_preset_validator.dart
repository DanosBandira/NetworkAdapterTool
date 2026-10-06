import '../models/network_preset.dart';

/// The preset input a validation error belongs to.
enum NetworkPresetField { name, assignments }

class NetworkPresetValidationError {
  const NetworkPresetValidationError(this.field, this.message);

  final NetworkPresetField field;
  final String message;

  @override
  String toString() => '${field.name}: $message';
}

/// Checks that a preset can be saved: a unique name, at least one line, every
/// line complete, each adapter only once and every profile existing.
///
/// Adapters are not checked against the current system on purpose: a preset
/// may name an adapter that is only present sometimes (e.g. a USB adapter);
/// that is reported when the preset is applied.
class NetworkPresetValidator {
  const NetworkPresetValidator();

  List<NetworkPresetValidationError> validate(
    NetworkPreset preset, {
    required Iterable<String> existingProfileNames,
    Iterable<String> otherPresetNames = const [],
  }) {
    return [
      ..._validateName(preset.name, otherPresetNames),
      ..._validateAssignments(preset.assignments, existingProfileNames.toSet()),
    ];
  }

  Iterable<NetworkPresetValidationError> _validateName(
    String name,
    Iterable<String> otherPresetNames,
  ) sync* {
    if (name.trim().isEmpty) {
      yield const NetworkPresetValidationError(
        NetworkPresetField.name,
        'Enter a preset name.',
      );
    } else if (otherPresetNames.any((other) => _isSameName(other, name))) {
      yield const NetworkPresetValidationError(
        NetworkPresetField.name,
        'A preset with this name already exists.',
      );
    }
  }

  Iterable<NetworkPresetValidationError> _validateAssignments(
    List<PresetAssignment> assignments,
    Set<String> existingProfileNames,
  ) sync* {
    if (assignments.isEmpty) {
      yield const NetworkPresetValidationError(
        NetworkPresetField.assignments,
        'Add at least one adapter.',
      );
      return;
    }
    final seenAdapterNames = <String>{};
    for (final assignment in assignments) {
      if (assignment.adapterName.trim().isEmpty ||
          assignment.profileName.trim().isEmpty) {
        yield const NetworkPresetValidationError(
          NetworkPresetField.assignments,
          'Choose an adapter and a profile on every line.',
        );
      } else if (!existingProfileNames.contains(assignment.profileName)) {
        yield NetworkPresetValidationError(
          NetworkPresetField.assignments,
          'Profile "${assignment.profileName}" does not exist.',
        );
      } else if (!seenAdapterNames.add(assignment.adapterName.toLowerCase())) {
        // One adapter can only hold one profile at a time.
        yield NetworkPresetValidationError(
          NetworkPresetField.assignments,
          'Adapter "${assignment.adapterName}" is used more than once.',
        );
      }
    }
  }

  bool _isSameName(String first, String second) =>
      first.trim().toLowerCase() == second.trim().toLowerCase();
}
