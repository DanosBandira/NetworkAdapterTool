import 'package:network_adapter_tool/core/contracts/network_profile_repository.dart';
import 'package:network_adapter_tool/core/models/network_preset.dart';
import 'package:network_adapter_tool/core/models/network_profile.dart';
import 'package:network_adapter_tool/core/models/network_profile_library.dart';

/// A [NetworkProfileRepository] that keeps the library in memory, optionally
/// failing like a broken or locked profile file would.
class InMemoryNetworkProfileRepository implements NetworkProfileRepository {
  InMemoryNetworkProfileRepository({
    List<NetworkProfile> storedProfiles = const [],
    List<NetworkPreset> storedPresets = const [],
    this.loadError,
    this.saveError,
  }) : storedLibrary = NetworkProfileLibrary(
         profiles: List.of(storedProfiles),
         presets: List.of(storedPresets),
       );

  NetworkProfileLibrary storedLibrary;
  final NetworkProfileStorageException? loadError;
  final NetworkProfileStorageException? saveError;

  List<NetworkProfile> get storedProfiles => storedLibrary.profiles;
  List<NetworkPreset> get storedPresets => storedLibrary.presets;

  @override
  Future<NetworkProfileLibrary> loadLibrary() async {
    if (loadError != null) throw loadError!;
    return storedLibrary;
  }

  @override
  Future<void> saveLibrary(NetworkProfileLibrary library) async {
    if (saveError != null) throw saveError!;
    storedLibrary = library;
  }

  /// Snapshots taken by [backupLibrary], oldest first.
  final List<NetworkProfileLibrary> backups = [];

  @override
  Future<String?> backupLibrary() async {
    backups.add(storedLibrary);
    return 'backup-${backups.length}.json';
  }
}
