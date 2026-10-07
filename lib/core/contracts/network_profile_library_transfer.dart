import '../models/network_profile_library.dart';

/// Saves the user's profiles and presets to a file of their choice, or reads
/// such a file, so they can be shared with other users or PCs.
abstract interface class NetworkProfileLibraryTransfer {
  /// Throws [NetworkProfileStorageException] when the file cannot be written.
  Future<void> exportLibrary(NetworkProfileLibrary library, String filePath);

  /// Throws [NetworkProfileStorageException] when the file does not exist,
  /// cannot be read, is not a valid user data file or comes from a newer app
  /// version.
  Future<NetworkProfileLibrary> importLibrary(String filePath);
}
