import 'dart:io';

import '../contracts/command_runner.dart';
import '../contracts/folder_opener.dart';

/// Opens a folder in the desktop's file manager on Linux via `xdg-open`,
/// which picks Files, Dolphin, Thunar, ... from the user's settings.
class XdgFolderOpener implements FolderOpener {
  const XdgFolderOpener(this._commandRunner);

  static const _openerExecutable = 'xdg-open';

  final CommandRunner _commandRunner;

  @override
  Future<void> openFolder(String folderPath) async {
    try {
      await Directory(folderPath).create(recursive: true);
    } on FileSystemException catch (error) {
      throw FolderOpenException('Cannot create $folderPath: ${error.message}');
    }
    final CommandResult result;
    try {
      result = await _commandRunner.run(_openerExecutable, [folderPath]);
    } on ProcessException {
      throw FolderOpenException(
        'xdg-open was not found; open $folderPath yourself.',
      );
    }
    if (result.exitCode != 0) {
      throw FolderOpenException(
        'xdg-open could not open $folderPath (exit code ${result.exitCode}).',
      );
    }
  }
}
