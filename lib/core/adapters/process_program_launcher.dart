import 'dart:async';
import 'dart:io';

import '../contracts/program_launcher.dart';

/// Starts user programs as child processes via `dart:io`.
///
/// Output is decoded with the system code page, like netsh and ping output.
class ProcessProgramLauncher implements ProgramLauncher {
  const ProcessProgramLauncher();

  @override
  Future<RunningProgram> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    try {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );
      return _RunningProcess(process);
    } on ProcessException catch (error) {
      throw ProgramStartException(
        'Could not start $executable: ${error.message.trim()}',
      );
    }
  }
}

class _RunningProcess implements RunningProgram {
  _RunningProcess(this._process) {
    _result = _collectResult();
  }

  // Enough for the status line and the output dialog; a chatty program that
  // runs for hours must not grow the app's memory without bound.
  static const _maximumOutputLength = 20000;

  final Process _process;
  String _output = '';
  bool _outputWasShortened = false;
  late final Future<ProgramResult> _result;

  @override
  Future<ProgramResult> get result => _result;

  // Process.kill only ends the process itself; a script's child programs
  // would keep running. taskkill /T ends the whole tree.
  @override
  Future<void> stop() async {
    try {
      await Process.run('taskkill.exe', [
        '/PID',
        '${_process.pid}',
        '/T',
        '/F',
      ]);
    } on ProcessException {
      // Fall through to the plain kill below.
    }
    _process.kill();
  }

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
