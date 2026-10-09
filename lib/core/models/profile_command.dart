/// A program or script to run for a profile, e.g. to map a network share or
/// start a tool after switching to a machine network.
///
/// [path] may be a bare file name (looked up in the plugin folder) or an
/// absolute path; see `PluginPathResolver`.
class ProfileCommand {
  const ProfileCommand({
    required this.path,
    this.arguments = const [],
    this.name,
    this.runAfterApply = true,
  });

  factory ProfileCommand.fromJson(Map<String, Object?> json) {
    return ProfileCommand(
      path: json['path'] as String,
      arguments: List<String>.from(
        json['arguments'] as List<Object?>? ?? const <Object?>[],
      ),
      name: json['name'] as String?,
      runAfterApply: json['runAfterApply'] as bool? ?? true,
    );
  }

  final String path;

  /// Passed to the program one by one, never joined into one string, so an
  /// argument with spaces needs no quoting.
  final List<String> arguments;

  /// Optional label, e.g. "Map drive".
  final String? name;

  /// Run automatically after the profile was applied successfully. The run
  /// button on the profile card runs every command regardless.
  final bool runAfterApply;

  /// The name when set, otherwise the path.
  String get displayName {
    final name = this.name;
    return name == null || name.trim().isEmpty ? path : name;
  }

  /// `null` for a file type the app cannot run.
  ProfileCommandFileType? get fileType => ProfileCommandFileType.ofPath(path);

  Map<String, Object?> toJson() {
    return {
      'path': path,
      if (arguments.isNotEmpty) 'arguments': arguments,
      if (name != null) 'name': name,
      'runAfterApply': runAfterApply,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ProfileCommand &&
      other.path == path &&
      other.name == name &&
      other.runAfterApply == runAfterApply &&
      _haveSameItems(other.arguments, arguments);

  @override
  int get hashCode =>
      Object.hash(path, name, runAfterApply, Object.hashAll(arguments));

  static bool _haveSameItems(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}

/// The kinds of files a [ProfileCommand] can run, recognized by extension.
enum ProfileCommandFileType {
  executable('.exe'),
  powerShellScript('.ps1'),
  batchFile('.bat'),
  commandScript('.cmd');

  const ProfileCommandFileType(this.extension);

  final String extension;

  static ProfileCommandFileType? ofPath(String path) {
    final lowerCasePath = path.trim().toLowerCase();
    for (final fileType in values) {
      if (lowerCasePath.endsWith(fileType.extension)) return fileType;
    }
    return null;
  }

  /// `.bat` and `.cmd` both run through cmd.exe.
  bool get runsThroughCmd =>
      this == ProfileCommandFileType.batchFile ||
      this == ProfileCommandFileType.commandScript;
}
