/// Shows a folder to the user, e.g. in Windows Explorer.
abstract interface class FolderOpener {
  /// Creates the folder first when it does not exist yet. Throws
  /// [FolderOpenException] when that fails.
  Future<void> openFolder(String folderPath);
}

class FolderOpenException implements Exception {
  const FolderOpenException(this.reason);

  final String reason;

  @override
  String toString() => 'FolderOpenException: $reason';
}
