import 'dart:io';

import '../contracts/network_profile_library_transfer.dart';
import '../contracts/network_profile_repository.dart';
import '../models/network_profile_library.dart';
import 'json_network_profile_repository.dart';

/// Exports and imports in the same JSON format as `user_data.json`, so a
/// shared file goes through the same parsing and format version checks.
class JsonNetworkProfileLibraryTransfer
    implements NetworkProfileLibraryTransfer {
  const JsonNetworkProfileLibraryTransfer();

  @override
  Future<void> exportLibrary(
    NetworkProfileLibrary library,
    String filePath,
  ) async {
    await JsonNetworkProfileRepository(File(filePath)).saveLibrary(library);
  }

  @override
  Future<NetworkProfileLibrary> importLibrary(String filePath) async {
    final file = File(filePath);
    // The repository treats a missing file as "nothing saved yet"; for an
    // import that would silently load nothing.
    if (!await file.exists()) {
      throw NetworkProfileStorageException('$filePath does not exist.');
    }
    return JsonNetworkProfileRepository(file).loadLibrary();
  }
}
