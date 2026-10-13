import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/commands/plugin_path_resolver.dart';
import 'package:network_adapter_tool/core/commands/profile_command_runner.dart';
import 'package:network_adapter_tool/core/models/profile_command.dart';
import 'package:network_adapter_tool/core/platform/host_platform.dart';
import 'package:path/path.dart' as path;

import '../../fakes/scripted_program_launcher.dart';

void main() {
  late ScriptedProgramLauncher launcher;
  late Set<String> missingFiles;
  late ProfileCommandRunner runner;

  setUp(() {
    launcher = ScriptedProgramLauncher();
    missingFiles = {};
    runner = ProfileCommandRunner(
      launcher: launcher,
      pathResolver: PluginPathResolver(
        r'C:\App\plugins',
        pathContext: path.windows,
      ),
      fileExists: (filePath) async => !missingFiles.contains(filePath),
    );
  });

  group('starting by file type', () {
    test('starts an exe from the plugin folder with its arguments', () async {
      await runner
          .start(
            const ProfileCommand(
              path: 'tool.exe',
              arguments: ['--port', 'COM 3'],
            ),
          )
          .outcome;

      final program = launcher.launchedPrograms.single;
      expect(program.executable, r'C:\App\plugins\tool.exe');
      expect(program.arguments, ['--port', 'COM 3']);
      expect(program.workingDirectory, r'C:\App\plugins');
    });

    test('runs a PowerShell script through powershell.exe -File', () async {
      await runner
          .start(
            const ProfileCommand(
              path: r'D:\Scripts\map drive.ps1',
              arguments: ['-Drive', 'Z:'],
            ),
          )
          .outcome;

      final program = launcher.launchedPrograms.single;
      expect(program.executable, 'powershell.exe');
      expect(program.arguments, [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        r'D:\Scripts\map drive.ps1',
        '-Drive',
        'Z:',
      ]);
      expect(program.workingDirectory, r'D:\Scripts');
    });

    test('starts a batch file directly, not through cmd.exe /c', () async {
      await runner
          .start(const ProfileCommand(path: 'setup.cmd', arguments: ['a b']))
          .outcome;

      final program = launcher.launchedPrograms.single;
      expect(program.executable, r'C:\App\plugins\setup.cmd');
      expect(program.arguments, ['a b']);
    });

    test('does not start a shell script on Windows', () async {
      final outcome = await runner
          .start(const ProfileCommand(path: 'mount.sh'))
          .outcome;

      expect((outcome as CommandNotStarted).reason, contains('Windows'));
      expect(launcher.launchedPrograms, isEmpty);
    });
  });

  group('starting on Linux', () {
    late ProfileCommandRunner linuxRunner;

    setUp(() {
      linuxRunner = ProfileCommandRunner(
        launcher: launcher,
        pathResolver: PluginPathResolver(
          '/opt/network-adapter-tool/plugins',
          pathContext: path.posix,
        ),
        platform: HostPlatform.linux,
        fileExists: (_) async => true,
      );
    });

    test('runs a shell script through bash', () async {
      await linuxRunner
          .start(
            const ProfileCommand(path: 'mount.sh', arguments: ['//nas/data']),
          )
          .outcome;

      final program = launcher.launchedPrograms.single;
      expect(program.executable, 'bash');
      expect(program.arguments, [
        '/opt/network-adapter-tool/plugins/mount.sh',
        '//nas/data',
      ]);
      expect(program.workingDirectory, '/opt/network-adapter-tool/plugins');
    });

    test('runs a PowerShell script through pwsh', () async {
      await linuxRunner
          .start(const ProfileCommand(path: '/home/me/route.ps1'))
          .outcome;

      final program = launcher.launchedPrograms.single;
      expect(program.executable, 'pwsh');
      expect(program.arguments, [
        '-NoProfile',
        '-NonInteractive',
        '-File',
        '/home/me/route.ps1',
      ]);
    });

    test('does not start Windows file types', () async {
      for (final windowsFile in ['tool.exe', 'setup.bat', 'setup.cmd']) {
        final outcome = await linuxRunner
            .start(ProfileCommand(path: windowsFile))
            .outcome;

        expect((outcome as CommandNotStarted).reason, contains('Linux'));
      }
      expect(launcher.launchedPrograms, isEmpty);
    });
  });

  group('outcome', () {
    test('reports exit code and output', () async {
      launcher
        ..exitCode = 2
        ..output = 'Drive Z: is in use';

      final outcome = await runner
          .start(const ProfileCommand(path: 'tool.exe'))
          .outcome;

      final finished = outcome as CommandFinished;
      expect(finished.exitCode, 2);
      expect(finished.isSuccess, isFalse);
      expect(finished.output, 'Drive Z: is in use');
    });

    test('reports a missing file without starting anything', () async {
      missingFiles.add(r'C:\App\plugins\tool.exe');

      final outcome = await runner
          .start(const ProfileCommand(path: 'tool.exe'))
          .outcome;

      expect(
        (outcome as CommandFileNotFound).resolvedPath,
        r'C:\App\plugins\tool.exe',
      );
      expect(launcher.launchedPrograms, isEmpty);
    });

    test('refuses a file type it cannot run', () async {
      final outcome = await runner
          .start(const ProfileCommand(path: 'notes.txt'))
          .outcome;

      expect(outcome, isA<CommandNotStarted>());
      expect(launcher.launchedPrograms, isEmpty);
    });

    test('reports a program that could not start', () async {
      launcher.startFailure = 'Access is denied.';

      final outcome = await runner
          .start(const ProfileCommand(path: 'tool.exe'))
          .outcome;

      expect((outcome as CommandNotStarted).reason, 'Access is denied.');
    });
  });

  group('stopping', () {
    test('stops a running program', () async {
      launcher.finishImmediately = false;
      final run = runner.start(const ProfileCommand(path: 'server.exe'));
      await pumpEventQueue();

      await run.stop();
      final outcome = await run.outcome;

      expect(launcher.launchedPrograms.single.wasStopped, isTrue);
      expect((outcome as CommandStopped).output, 'terminated');
    });

    test('never starts a program stopped before it started', () async {
      final run = runner.start(const ProfileCommand(path: 'server.exe'));

      await run.stop();
      final outcome = await run.outcome;

      expect(outcome, isA<CommandStopped>());
      expect(launcher.launchedPrograms, isEmpty);
    });
  });
}
