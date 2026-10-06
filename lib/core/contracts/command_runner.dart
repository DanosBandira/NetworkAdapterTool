import 'dart:convert';

/// Outcome of running an external command.
class CommandResult {
  const CommandResult({
    required this.exitCode,
    required this.standardOutput,
    required this.standardError,
  });

  final int exitCode;
  final String standardOutput;
  final String standardError;
}

/// Runs an external executable such as `netsh.exe` or `powershell.exe`.
///
/// Arguments are passed as a list, never as one concatenated string, so
/// values containing spaces (like adapter names) need no manual quoting.
abstract interface class CommandRunner {
  /// Decodes the output with [outputEncoding], or with the system code page
  /// when it is `null`.
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    Encoding? outputEncoding,
  });
}
