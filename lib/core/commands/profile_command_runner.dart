import 'dart:async';
import 'dart:io';

import '../contracts/program_launcher.dart';
import '../models/profile_command.dart';
import '../platform/host_platform.dart';
import 'plugin_path_resolver.dart';

/// Runs one [ProfileCommand]: finds its file, starts it the way its file type
/// needs and reports how it ended.
///
/// There is no time limit on purpose: a command may be a long-running tool,
/// so it runs until it exits or the user stops it.
class ProfileCommandRunner {
  ProfileCommandRunner({
    required this._launcher,
    required this._pathResolver,
    this._platform = HostPlatform.windows,
    Future<bool> Function(String filePath)? fileExists,
  }) : _fileExists = fileExists ?? _fileExistsOnDisk;

  // The default execution policy ("Restricted" on Windows clients) refuses
  // every script; the user picked this script explicitly, so it may run.
  static const _windowsPowerShell = [
    'powershell.exe',
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
  ];

  // PowerShell 7 ("pwsh") is the only PowerShell on Linux and has no
  // execution policy there. It is not installed by default.
  static const _linuxPowerShell = [
    'pwsh',
    '-NoProfile',
    '-NonInteractive',
    '-File',
  ];

  // bash rather than sh: most scripts written for Linux expect bash, and the
  // file does not need to be marked executable this way.
  static const _linuxShell = ['bash'];

  final ProgramLauncher _launcher;
  final PluginPathResolver _pathResolver;
  final HostPlatform _platform;
  final Future<bool> Function(String filePath) _fileExists;

  String get pluginFolderPath => _pathResolver.pluginFolderPath;

  /// The file [command] will run, e.g. to show it next to a result.
  String resolvedPathOf(ProfileCommand command) =>
      _pathResolver.resolve(command.path);

  /// See [PluginPathResolver.commandPathFor].
  String commandPathFor(String selectedFilePath) =>
      _pathResolver.commandPathFor(selectedFilePath);

  /// See [PluginPathResolver.folderToBrowseFrom].
  String folderToBrowseFrom(String commandPath) =>
      _pathResolver.folderToBrowseFrom(commandPath);

  /// Starts [command] right away; the returned run reports the outcome and
  /// can be stopped.
  ProfileCommandRun start(ProfileCommand command) {
    final run = ProfileCommandRun._();
    unawaited(_runUntilEnded(command, run));
    return run;
  }

  Future<void> _runUntilEnded(
    ProfileCommand command,
    ProfileCommandRun run,
  ) async {
    final resolvedPath = resolvedPathOf(command);
    final fileType = command.fileType;
    if (fileType == null) {
      run._finish(
        CommandNotStarted(
          '${command.path} is not an .exe, .ps1, .bat, .cmd or .sh file.',
        ),
      );
      return;
    }
    final launchPrefix = _launchPrefixFor(fileType);
    if (launchPrefix == null) {
      run._finish(
        CommandNotStarted(
          '${fileType.extension} files cannot run on '
          '${_platform == HostPlatform.linux ? 'Linux' : 'Windows'}.',
        ),
      );
      return;
    }
    if (!await _fileExists(resolvedPath)) {
      run._finish(CommandFileNotFound(resolvedPath));
      return;
    }
    if (run.stopWasRequested) {
      run._finish(const CommandStopped(output: '', duration: Duration.zero));
      return;
    }
    await _startAndWaitForExit(
      resolvedPath,
      launchPrefix,
      command.arguments,
      run,
    );
  }

  Future<void> _startAndWaitForExit(
    String resolvedPath,
    List<String> launchPrefix,
    List<String> arguments,
    ProfileCommandRun run,
  ) async {
    final stopwatch = Stopwatch()..start();
    final RunningProgram program;
    try {
      program = await _startProgram(resolvedPath, launchPrefix, arguments);
    } on ProgramStartException catch (error) {
      run._finish(CommandNotStarted(error.reason));
      return;
    }
    await run._attach(program);
    final result = await program.result;
    run._finish(
      run.stopWasRequested
          ? CommandStopped(output: result.output, duration: stopwatch.elapsed)
          : CommandFinished(
              exitCode: result.exitCode,
              output: result.output,
              duration: stopwatch.elapsed,
            ),
    );
  }

  /// The program and arguments placed before the file, empty when the file
  /// starts by itself; `null` when this platform cannot run the file type.
  ///
  /// .bat and .cmd files are started directly instead of through
  /// "cmd.exe /c": Dart then quotes the arguments for cmd.exe itself, while
  /// "cmd.exe /c" breaks on a quoted path followed by quoted arguments.
  List<String>? _launchPrefixFor(ProfileCommandFileType fileType) {
    return switch ((_platform, fileType)) {
      (HostPlatform.windows, ProfileCommandFileType.powerShellScript) =>
        _windowsPowerShell,
      (HostPlatform.windows, ProfileCommandFileType.shellScript) => null,
      (HostPlatform.windows, _) => const [],
      (HostPlatform.linux, ProfileCommandFileType.powerShellScript) =>
        _linuxPowerShell,
      (HostPlatform.linux, ProfileCommandFileType.shellScript) => _linuxShell,
      (HostPlatform.linux, _) => null,
    };
  }

  Future<RunningProgram> _startProgram(
    String resolvedPath,
    List<String> launchPrefix,
    List<String> arguments,
  ) {
    final workingDirectory = _pathResolver.folderOf(resolvedPath);
    final commandLine = [...launchPrefix, resolvedPath, ...arguments];
    return _launcher.start(
      commandLine.first,
      commandLine.skip(1).toList(),
      workingDirectory: workingDirectory,
    );
  }

  static Future<bool> _fileExistsOnDisk(String filePath) =>
      File(filePath).exists();
}

/// A started [ProfileCommand]; see [ProfileCommandRunner.start].
class ProfileCommandRun {
  ProfileCommandRun._();

  final _outcome = Completer<ProfileCommandOutcome>();
  RunningProgram? _program;
  bool _stopWasRequested = false;

  Future<ProfileCommandOutcome> get outcome => _outcome.future;

  bool get stopWasRequested => _stopWasRequested;

  /// Ends the program; [outcome] then completes with [CommandStopped].
  Future<void> stop() async {
    _stopWasRequested = true;
    await _program?.stop();
  }

  // A stop requested while the program was still starting is carried out as
  // soon as the program is known.
  Future<void> _attach(RunningProgram program) async {
    _program = program;
    if (_stopWasRequested) await program.stop();
  }

  void _finish(ProfileCommandOutcome outcome) => _outcome.complete(outcome);
}

/// How a profile command ended.
sealed class ProfileCommandOutcome {
  const ProfileCommandOutcome();
}

/// The program exited by itself; exit code 0 counts as success.
final class CommandFinished extends ProfileCommandOutcome {
  const CommandFinished({
    required this.exitCode,
    required this.output,
    required this.duration,
  });

  final int exitCode;
  final String output;
  final Duration duration;

  bool get isSuccess => exitCode == 0;
}

final class CommandStopped extends ProfileCommandOutcome {
  const CommandStopped({required this.output, required this.duration});

  final String output;
  final Duration duration;
}

final class CommandFileNotFound extends ProfileCommandOutcome {
  const CommandFileNotFound(this.resolvedPath);

  final String resolvedPath;
}

final class CommandNotStarted extends ProfileCommandOutcome {
  const CommandNotStarted(this.reason);

  final String reason;
}
