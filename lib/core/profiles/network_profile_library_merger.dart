import '../models/network_preset.dart';
import '../models/network_profile_library.dart';

/// Adds an imported library to the current one without overwriting anything.
///
/// An imported profile or preset whose name already exists (ignoring case,
/// like the validators) is renamed to "NAME (imported)", "NAME (imported 2)",
/// and so on; imported presets follow the renames of their profiles.
class NetworkProfileLibraryMerger {
  const NetworkProfileLibraryMerger();

  LibraryMergeResult merge(
    NetworkProfileLibrary current,
    NetworkProfileLibrary imported,
  ) {
    final takenProfileNames = _lowerCaseNames(
      current.profiles.map((p) => p.name),
    );
    final newProfileNamesByImportedName = <String, String>{};
    final importedProfiles = [
      for (final profile in imported.profiles)
        profile.withName(
          newProfileNamesByImportedName[profile.name] = _claimUniqueName(
            profile.name,
            takenProfileNames,
          ),
        ),
    ];

    final takenPresetNames = _lowerCaseNames(
      current.presets.map((p) => p.name),
    );
    final importedPresets = [
      for (final preset in imported.presets)
        _withProfilesRenamed(
          preset,
          newProfileNamesByImportedName,
        ).withName(_claimUniqueName(preset.name, takenPresetNames)),
    ];

    final renamedProfileCount = imported.profiles
        .where(
          (profile) =>
              newProfileNamesByImportedName[profile.name] != profile.name,
        )
        .length;
    final renamedPresetCount = [
      for (var index = 0; index < imported.presets.length; index++)
        if (importedPresets[index].name != imported.presets[index].name) index,
    ].length;

    return LibraryMergeResult(
      // copyWith keeps the current personal settings (e.g. helpWasShown).
      library: current.copyWith(
        profiles: [...current.profiles, ...importedProfiles],
        presets: [...current.presets, ...importedPresets],
      ),
      renamedCount: renamedProfileCount + renamedPresetCount,
    );
  }

  // One lookup per line on the original name: renaming one profile after the
  // other could rename a line twice when a new name equals another imported
  // name (e.g. "A" → "A (imported)" while "A (imported)" is also imported).
  NetworkPreset _withProfilesRenamed(
    NetworkPreset preset,
    Map<String, String> newProfileNamesByImportedName,
  ) {
    return NetworkPreset(
      name: preset.name,
      assignments: [
        for (final assignment in preset.assignments)
          PresetAssignment(
            adapterName: assignment.adapterName,
            profileName:
                newProfileNamesByImportedName[assignment.profileName] ??
                assignment.profileName,
          ),
      ],
    );
  }

  // Returns [name] if it is free, otherwise the first free "(imported)"
  // variant, and marks the result as taken.
  String _claimUniqueName(String name, Set<String> takenLowerCaseNames) {
    var candidate = name;
    var attempt = 1;
    while (takenLowerCaseNames.contains(candidate.toLowerCase())) {
      candidate = attempt == 1
          ? '$name (imported)'
          : '$name (imported $attempt)';
      attempt++;
    }
    takenLowerCaseNames.add(candidate.toLowerCase());
    return candidate;
  }

  Set<String> _lowerCaseNames(Iterable<String> names) => {
    for (final name in names) name.toLowerCase(),
  };
}

class LibraryMergeResult {
  const LibraryMergeResult({required this.library, required this.renamedCount});

  final NetworkProfileLibrary library;

  /// How many imported profiles and presets got an "(imported)" name.
  final int renamedCount;
}
