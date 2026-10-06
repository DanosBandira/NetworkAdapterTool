import 'models/network_preset.dart';
import 'models/network_profile.dart';
import 'network_profile_applier.dart';

/// Use case: apply every line of a preset, one adapter at a time.
///
/// Each line goes through [NetworkProfileApplier], so validation, the
/// disconnected-adapter check and verification all apply per adapter. A
/// failing line does not stop the others; every line gets its own result.
/// Lines run one after another because each already reads adapters for a
/// few seconds, and parallel netsh/PowerShell runs would only compete.
class NetworkPresetApplier {
  const NetworkPresetApplier(this._profileApplier);

  final NetworkProfileApplier _profileApplier;

  /// Emits one result per line, in preset order, as soon as it is known.
  Stream<PresetAssignmentResult> applyPreset(
    NetworkPreset preset,
    List<NetworkProfile> profiles,
  ) async* {
    for (final assignment in preset.assignments) {
      yield await _applyAssignment(assignment, profiles);
    }
  }

  Future<PresetAssignmentResult> _applyAssignment(
    PresetAssignment assignment,
    List<NetworkProfile> profiles,
  ) async {
    final profile = profiles
        .where((profile) => profile.name == assignment.profileName)
        .firstOrNull;
    if (profile == null) {
      return PresetAssignmentResult.profileMissing(assignment);
    }
    final outcome = await _profileApplier.applyProfileToAdapter(
      profile,
      assignment.adapterName,
    );
    return PresetAssignmentResult.applied(assignment, profile, outcome);
  }
}

class PresetAssignmentResult {
  const PresetAssignmentResult.applied(
    this.assignment,
    NetworkProfile this.profile,
    ApplyProfileOutcome this.outcome,
  );

  /// The preset names a profile that no longer exists; nothing was applied.
  const PresetAssignmentResult.profileMissing(this.assignment)
    : profile = null,
      outcome = null;

  final PresetAssignment assignment;

  /// `null` when the profile was missing.
  final NetworkProfile? profile;

  /// `null` when the profile was missing.
  final ApplyProfileOutcome? outcome;

  bool get isSuccess => outcome is ProfileApplied;
}
