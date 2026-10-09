/// Starts an external program and keeps a handle to wait for or stop it.
///
/// Unlike `CommandRunner`, which waits for short system tools such as netsh,
/// this is for user programs that may run for a long time and must be
/// stoppable.
abstract interface class ProgramLauncher {
  /// Throws [ProgramStartException] when the program cannot be started.
  Future<RunningProgram> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  });
}

abstract interface class RunningProgram {
  /// Completes when the program has exited and its output was read.
  Future<ProgramResult> get result;

  /// Ends the program together with the processes it started (a script's
  /// child programs would otherwise keep running).
  Future<void> stop();
}

class ProgramResult {
  const ProgramResult({required this.exitCode, required this.output});

  final int exitCode;

  /// Standard output and standard error in the order they arrived; only the
  /// last part when the program wrote a lot.
  final String output;
}

class ProgramStartException implements Exception {
  const ProgramStartException(this.reason);

  final String reason;

  @override
  String toString() => 'ProgramStartException: $reason';
}
