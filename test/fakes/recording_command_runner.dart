import 'dart:convert';

import 'package:network_profile_switcher/core/contracts/command_runner.dart';

/// A [CommandRunner] that records every call instead of starting a process,
/// so tests can assert on the generated commands without touching a real
/// adapter.
class RecordingCommandRunner implements CommandRunner {
  RecordingCommandRunner({
    this.exitCodeForEveryCall = 0,
    this.standardOutputForEveryCall = '',
    this.standardErrorForEveryCall = '',
  });

  final int exitCodeForEveryCall;
  final String standardOutputForEveryCall;
  final String standardErrorForEveryCall;
  final List<RecordedCommand> recordedCommands = [];

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    Encoding? outputEncoding,
  }) async {
    recordedCommands.add(
      RecordedCommand(executable, List.of(arguments), outputEncoding),
    );
    return CommandResult(
      exitCode: exitCodeForEveryCall,
      standardOutput: standardOutputForEveryCall,
      standardError: standardErrorForEveryCall,
    );
  }

  List<List<String>> get recordedArgumentLists =>
      [for (final command in recordedCommands) command.arguments];
}

class RecordedCommand {
  const RecordedCommand(this.executable, this.arguments, this.outputEncoding);

  final String executable;
  final List<String> arguments;
  final Encoding? outputEncoding;
}
