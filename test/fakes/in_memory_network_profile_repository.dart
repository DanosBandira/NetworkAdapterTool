import 'package:network_profile_switcher/core/contracts/network_profile_repository.dart';
import 'package:network_profile_switcher/core/models/network_profile.dart';

/// A [NetworkProfileRepository] that keeps profiles in memory, optionally
/// failing like a broken or locked profile file would.
class InMemoryNetworkProfileRepository implements NetworkProfileRepository {
  InMemoryNetworkProfileRepository({
    List<NetworkProfile> storedProfiles = const [],
    this.loadError,
    this.saveError,
  }) : storedProfiles = List.of(storedProfiles);

  List<NetworkProfile> storedProfiles;
  final NetworkProfileStorageException? loadError;
  final NetworkProfileStorageException? saveError;

  @override
  Future<List<NetworkProfile>> loadAllProfiles() async {
    if (loadError != null) throw loadError!;
    return List.of(storedProfiles);
  }

  @override
  Future<void> saveAllProfiles(List<NetworkProfile> profiles) async {
    if (saveError != null) throw saveError!;
    storedProfiles = List.of(profiles);
  }
}
