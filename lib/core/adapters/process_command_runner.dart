import 'dart:convert';
import 'dart:io';

import '../contracts/command_runner.dart';

/// Runs external commands as child processes via `dart:io`.
///
/// By default output is decoded with the system code page, which matches
/// what netsh writes. That text is localized, so callers should decide on
/// exit codes rather than on parsing the output.
class ProcessCommandRunner implements CommandRunner {
  const ProcessCommandRunner();

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    Encoding? outputEncoding,
  }) async {
    final encoding = outputEncoding ?? systemEncoding;
    final processResult = await Process.run(
      executable,
      arguments,
      stdoutEncoding: encoding,
      stderrEncoding: encoding,
    );
    return CommandResult(
      exitCode: processResult.exitCode,
      standardOutput: processResult.stdout as String,
      standardError: processResult.stderr as String,
    );
  }
}
