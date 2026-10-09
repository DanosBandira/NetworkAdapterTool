import 'package:network_adapter_tool/core/contracts/folder_opener.dart';

/// A [FolderOpener] that records the folders instead of opening Explorer.
class RecordingFolderOpener implements FolderOpener {
  RecordingFolderOpener({this.failure});

  /// When set, opening throws a [FolderOpenException] with this reason.
  final String? failure;
  final List<String> openedFolders = [];

  @override
  Future<void> openFolder(String folderPath) async {
    final failure = this.failure;
    if (failure != null) throw FolderOpenException(failure);
    openedFolders.add(folderPath);
  }
}
