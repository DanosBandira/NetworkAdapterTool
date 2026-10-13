import 'dart:async';
import 'dart:io';

import '../contracts/program_launcher.dart';
import '../platform/host_platform.dart';

/// Starts user programs as child processes via `dart:io`.
///
/// Output is decoded with the system code page, like netsh and ping output.
class ProcessProgramLauncher implements ProgramLauncher {
  const ProcessProgramLauncher({this._platform = HostPlatform.windows});

  // setsid runs the program as the leader of a new process group, so Stop
  // can end the group: a script and everything it started.
  static const _newProcessGroupExecutable = 'setsid';

  final HostPlatform _platform;

  @override
  Future<RunningProgram> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    final startsInOwnProcessGroup = _platform == HostPlatform.linux;
    try {
      final process = startsInOwnProcessGroup
          ? await Process.start(_newProcessGroupExecutable, [
              executable,
              ...arguments,
            ], workingDirectory: workingDirectory)
          : await Process.start(
              executable,
              arguments,
              workingDirectory: workingDirectory,
            );
      return startsInOwnProcessGroup
          ? _RunningProcess(process, _stopProcessGroup)
          : _RunningProcess(process, _stopProcessTree);
    } on ProcessException catch (error) {
      throw ProgramStartException(
        'Could not start $executable: ${error.message.trim()}',
      );
    }
  }

  // Process.kill only ends the process itself; a script's child programs
  // would keep running. taskkill /T ends the whole tree.
  static Future<void> _stopProcessTree(Process process) async {
    try {
      await Process.run('taskkill.exe', ['/PID', '${process.pid}', '/T', '/F']);
    } on ProcessException {
      // Fall through to the plain kill below.
    }
    process.kill();
  }

  // The process started by setsid leads its group, so the group id is its
  // pid; "kill -- -pid" signals the whole group.
  static Future<void> _stopProcessGroup(Process process) async {
    try {
      await Process.run('kill', ['-KILL', '--', '-${process.pid}']);
    } on ProcessException {
      // Fall through to the plain kill below.
    }
    process.kill(ProcessSignal.sigkill);
  }
}

class _RunningProcess implements RunningProgram {
  _RunningProcess(this._process, this._stopProcess) {
    _result = _collectResult();
  }

  final Future<void> Function(Process process) _stopProcess;

  // Enough for the status line and the output dialog; a chatty program that
  // runs for hours must not grow the app's memory without bound.
  static const _maximumOutputLength = 20000;

  final Process _process;
  String _output = '';
  bool _outputWasShortened = false;
  late final Future<ProgramResult> _result;

  @override
  Future<ProgramResult> get result => _result;

  @override
  Future<void> stop() => _stopProcess(_process);

  Future<ProgramResult> _collectResult() async {
    await Future.wait([
      _appendOutputOf(_process.stdout),
      _appendOutputOf(_process.stderr),
    ]);
    final exitCode = await _process.exitCode;
    return ProgramResult(exitCode: exitCode, output: _outputTail());
  }

  Future<void> _appendOutputOf(Stream<List<int>> stream) {
    return stream.transform(systemEncoding.decoder).forEach(_appendOutput);
  }

  void _appendOutput(String text) {
    _output += text;
    if (_output.length > _maximumOutputLength) {
      _output = _output.substring(_output.length - _maximumOutputLength);
      _outputWasShortened = true;
    }
  }

  String _outputTail() => _outputWasShortened ? '…$_output' : _output;
}
