import '../models/network_profile.dart';

/// Persists the user's network profiles.
///
/// The profile list is small, so it is always loaded and saved as a whole.
abstract interface class NetworkProfileRepository {
  /// Returns an empty list when no profiles have been saved yet.
  ///
  /// Throws [NetworkProfileStorageException] when stored profiles exist but
  /// cannot be read, so they are never silently replaced by an empty list.
  Future<List<NetworkProfile>> loadAllProfiles();

  /// Throws [NetworkProfileStorageException] when the profiles cannot be
  /// written.
  Future<void> saveAllProfiles(List<NetworkProfile> profiles);
}

/// Thrown when profiles cannot be read from or written to storage.
class NetworkProfileStorageException implements Exception {
  const NetworkProfileStorageException(this.reason);

  final String reason;

  @override
  String toString() => 'NetworkProfileStorageException: $reason';
}
