import '../models/network_profile.dart';

/// Persists the user's network profiles.
///
/// The profile list is small, so it is always loaded and saved as a whole.
abstract interface class NetworkProfileRepository {
  /// Returns an empty list when no profiles have been saved yet.
  Future<List<NetworkProfile>> loadAllProfiles();

  Future<void> saveAllProfiles(List<NetworkProfile> profiles);
}
