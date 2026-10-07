import 'package:network_adapter_tool/core/contracts/network_profile_library_transfer.dart';
import 'package:network_adapter_tool/core/contracts/network_profile_repository.dart';
import 'package:network_adapter_tool/core/models/network_profile_library.dart';

/// A [NetworkProfileLibraryTransfer] backed by a map of "files", so tests can
/// export and import without touching the disk.
class InMemoryNetworkProfileLibraryTransfer
    implements NetworkProfileLibraryTransfer {
  final Map<String, NetworkProfileLibrary> filesByPath = {};

  @override
  Future<void> exportLibrary(
    NetworkProfileLibrary library,
    String filePath,
  ) async {
    filesByPath[filePath] = library;
  }

  @override
  Future<NetworkProfileLibrary> importLibrary(String filePath) async {
    final library = filesByPath[filePath];
    if (library == null) {
      throw NetworkProfileStorageException('$filePath does not exist.');
    }
    return library;
  }
}
