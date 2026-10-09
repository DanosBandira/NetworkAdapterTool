import 'dart:async';

import 'package:network_adapter_tool/core/contracts/program_launcher.dart';

/// A [ProgramLauncher] that starts nothing. Each start is recorded; the
/// program finishes right away with [exitCode] and [output], or, with
/// [finishImmediately] false, when the test calls [LaunchedProgram.finish]
/// or stops it.
class ScriptedProgramLauncher implements ProgramLauncher {
  ScriptedProgramLauncher({
    this.exitCode = 0,
    this.output = '',
    this.finishImmediately = true,
    this.startFailure,
  });

  int exitCode;
  String output;
  bool finishImmediately;

  /// When set, every start throws a [ProgramStartException] with this reason.
  String? startFailure;

  final List<LaunchedProgram> launchedPrograms = [];

  @override
  Future<RunningProgram> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    final startFailure = this.startFailure;
    if (startFailure != null) throw ProgramStartException(startFailure);
    final program = LaunchedProgram(
      executable,
      List.of(arguments),
      workingDirectory,
    );
    launchedPrograms.add(program);
    if (finishImmediately) program.finish(exitCode: exitCode, output: output);
    return program;
  }
}

class LaunchedProgram implements RunningProgram {
  LaunchedProgram(this.executable, this.arguments, this.workingDirectory);

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final _result = Completer<ProgramResult>();
  bool wasStopped = false;

  @override
  Future<ProgramResult> get result => _result.future;

  void finish({int exitCode = 0, String output = ''}) {
    if (_result.isCompleted) return;
    _result.complete(ProgramResult(exitCode: exitCode, output: output));
  }

  @override
  Future<void> stop() async {
    wasStopped = true;
    finish(exitCode: 1, output: 'terminated');
  }
}
