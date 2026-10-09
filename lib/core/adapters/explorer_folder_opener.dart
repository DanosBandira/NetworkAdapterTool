import 'dart:io';

import '../contracts/command_runner.dart';
import '../contracts/folder_opener.dart';

/// Opens a folder in Windows Explorer.
class ExplorerFolderOpener implements FolderOpener {
  const ExplorerFolderOpener(this._commandRunner);

  static const _explorerExecutable = 'explorer.exe';

  final CommandRunner _commandRunner;

  // explorer.exe exits with 1 even when the window opened, so its exit code
  // is ignored.
  @override
  Future<void> openFolder(String folderPath) async {
    try {
      await Directory(folderPath).create(recursive: true);
    } on FileSystemException catch (error) {
      throw FolderOpenException('Cannot create $folderPath: ${error.message}');
    }
    await _commandRunner.run(_explorerExecutable, [folderPath]);
  }
}
