import 'dart:io';

import '../contracts/command_runner.dart';

/// Runs external commands as child processes via `dart:io`.
///
/// Output is decoded with the system code page (the `Process.run` default),
/// which matches what netsh writes. That text is localized, so callers should
/// decide on exit codes rather than on parsing the output.
class ProcessCommandRunner implements CommandRunner {
  const ProcessCommandRunner();

  @override
  Future<CommandResult> run(String executable, List<String> arguments) async {
    final processResult = await Process.run(executable, arguments);
    return CommandResult(
      exitCode: processResult.exitCode,
      standardOutput: processResult.stdout as String,
      standardError: processResult.stderr as String,
    );
  }
}
