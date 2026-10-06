/// A named set of adapter-to-profile assignments, applied together with one
/// click (e.g. "Line 1": Ethernet → Machine, Wi-Fi → Office).
class NetworkPreset {
  const NetworkPreset({required this.name, required this.assignments});

  factory NetworkPreset.fromJson(Map<String, Object?> json) {
    return NetworkPreset(
      name: json['name'] as String,
      assignments: [
        for (final assignmentEntry in json['assignments'] as List<Object?>)
          PresetAssignment.fromJson(assignmentEntry as Map<String, Object?>),
      ],
    );
  }

  final String name;
  final List<PresetAssignment> assignments;

  bool usesProfile(String profileName) =>
      assignments.any((assignment) => assignment.profileName == profileName);

  /// The same preset with every reference to [oldProfileName] renamed.
  NetworkPreset withProfileRenamed(
    String oldProfileName,
    String newProfileName,
  ) {
    return NetworkPreset(
      name: name,
      assignments: [
        for (final assignment in assignments)
          assignment.profileName == oldProfileName
              ? PresetAssignment(
                  adapterName: assignment.adapterName,
                  profileName: newProfileName,
                )
              : assignment,
      ],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'assignments': [
        for (final assignment in assignments) assignment.toJson(),
      ],
    };
  }
}

/// One line of a preset: apply the profile named [profileName] to the adapter
/// named [adapterName].
///
/// Both are referenced by name. Profile renames are carried into presets by
/// the app; an adapter that no longer exists is reported when applying.
class PresetAssignment {
  const PresetAssignment({
    required this.adapterName,
    required this.profileName,
  });

  factory PresetAssignment.fromJson(Map<String, Object?> json) {
    return PresetAssignment(
      adapterName: json['adapterName'] as String,
      profileName: json['profileName'] as String,
    );
  }

  final String adapterName;
  final String profileName;

  Map<String, Object?> toJson() {
    return {'adapterName': adapterName, 'profileName': profileName};
  }

  @override
  bool operator ==(Object other) =>
      other is PresetAssignment &&
      other.adapterName == adapterName &&
      other.profileName == profileName;

  @override
  int get hashCode => Object.hash(adapterName, profileName);
}
