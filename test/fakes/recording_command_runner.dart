import 'package:network_profile_switcher/core/contracts/command_runner.dart';

/// A [CommandRunner] that records every call instead of starting a process,
/// so tests can assert on the generated commands without touching a real
/// adapter.
class RecordingCommandRunner implements CommandRunner {
  RecordingCommandRunner({this.exitCodeForEveryCall = 0});

  final int exitCodeForEveryCall;
  final List<RecordedCommand> recordedCommands = [];

  @override
  Future<CommandResult> run(String executable, List<String> arguments) async {
    recordedCommands.add(RecordedCommand(executable, List.of(arguments)));
    return CommandResult(
      exitCode: exitCodeForEveryCall,
      standardOutput: '',
      standardError: '',
    );
  }

  List<List<String>> get recordedArgumentLists =>
      [for (final command in recordedCommands) command.arguments];
}

class RecordedCommand {
  const RecordedCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}
