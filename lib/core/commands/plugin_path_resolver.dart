import 'package:path/path.dart' as path;

/// Turns the path of a profile command into the file to run.
///
/// An absolute path (`C:\Tools\x.exe`, `\server\share\x.exe`) is used as
/// is; anything else (`x.exe`, `tools\x.ps1`) is looked up in the plugin
/// folder next to the app, so commands keep working when the app folder is
/// moved or copied to another PC.
class PluginPathResolver {
  PluginPathResolver(this.pluginFolderPath, {path.Context? pathContext})
    : _pathContext = pathContext ?? path.context;

  final String pluginFolderPath;
  final path.Context _pathContext;

  String resolve(String commandPath) {
    final trimmedPath = commandPath.trim();
    if (_pathContext.isAbsolute(trimmedPath)) {
      return _pathContext.normalize(trimmedPath);
    }
    return _pathContext.normalize(
      _pathContext.join(pluginFolderPath, trimmedPath),
    );
  }

  /// The folder a resolved command runs in, so a script finds the files next
  /// to it.
  String folderOf(String resolvedPath) => _pathContext.dirname(resolvedPath);
}
