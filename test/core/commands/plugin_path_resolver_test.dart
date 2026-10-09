import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/commands/plugin_path_resolver.dart';
import 'package:path/path.dart' as path;

void main() {
  final resolver = PluginPathResolver(
    r'C:\App\plugins',
    pathContext: path.windows,
  );

  test('looks up a bare file name in the plugin folder', () {
    expect(resolver.resolve('tool.exe'), r'C:\App\plugins\tool.exe');
  });

  test('looks up a relative path inside the plugin folder', () {
    expect(
      resolver.resolve(r'scripts\map drive.ps1'),
      r'C:\App\plugins\scripts\map drive.ps1',
    );
  });

  test('keeps an absolute path', () {
    expect(resolver.resolve(r'D:\Tools\viewer.exe'), r'D:\Tools\viewer.exe');
  });

  test('keeps a network path', () {
    expect(
      resolver.resolve(r'\\server\share\tool.exe'),
      r'\\server\share\tool.exe',
    );
  });

  test('ignores surrounding spaces and accepts forward slashes', () {
    expect(resolver.resolve('  C:/Tools/viewer.exe '), r'C:\Tools\viewer.exe');
  });

  test('gives the folder a resolved command runs in', () {
    expect(
      resolver.folderOf(r'C:\App\plugins\scripts\map.ps1'),
      r'C:\App\plugins\scripts',
    );
  });
}
