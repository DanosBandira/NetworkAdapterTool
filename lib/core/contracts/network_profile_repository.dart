import '../models/network_profile_library.dart';

/// Persists the user's profiles and presets.
///
/// The library is small, so it is always loaded and saved as a whole.
abstract interface class NetworkProfileRepository {
  /// Returns an empty library when nothing has been saved yet.
  ///
  /// Throws [NetworkProfileStorageException] when stored data exists but
  /// cannot be read, so it is never silently replaced by an empty library.
  Future<NetworkProfileLibrary> loadLibrary();

  /// Throws [NetworkProfileStorageException] when the library cannot be
  /// written.
  Future<void> saveLibrary(NetworkProfileLibrary library);
}

/// Thrown when profiles cannot be read from or written to storage.
class NetworkProfileStorageException implements Exception {
  const NetworkProfileStorageException(this.reason);

  final String reason;

  @override
  String toString() => 'NetworkProfileStorageException: $reason';
}
