import 'dart:convert';

import 'package:network_adapter_tool/core/contracts/command_runner.dart';

/// A [CommandRunner] that answers nmcli the way NetworkManager would, from
/// text the test provides, and records every call. Commands that change
/// something (modify, add, up) succeed unless [exitCodeForChanges] says
/// otherwise.
///
/// The sample outputs follow `nmcli -t` as described in nmcli(1); they were
/// written without a Linux machine, so capture real output to replace them
/// once one is available.
class ScriptedNmcliCommandRunner implements CommandRunner {
  ScriptedNmcliCommandRunner({
    required this.deviceOutput,
    required this.connectionListOutput,
    this.connectionDetailsByUuid = const {},
    this.exitCodeForReads = 0,
    this.exitCodeForChanges = 0,
    this.onChange,
  });

  String deviceOutput;
  String connectionListOutput;
  Map<String, String> connectionDetailsByUuid;
  final int exitCodeForReads;
  final int exitCodeForChanges;

  /// Called for every changing command, e.g. to make a connection appear
  /// after "connection add".
  final void Function(List<String> arguments)? onChange;

  final List<List<String>> recordedArgumentLists = [];

  /// Only the commands that change something, without the reads.
  List<List<String>> get changes => [
    for (final arguments in recordedArgumentLists)
      if (!_isRead(arguments)) arguments,
  ];

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    Encoding? outputEncoding,
  }) async {
    recordedArgumentLists.add(List.of(arguments));
    if (!_isRead(arguments)) {
      onChange?.call(arguments);
      return CommandResult(
        exitCode: exitCodeForChanges,
        standardOutput: '',
        standardError: exitCodeForChanges == 0 ? '' : 'Error: refused.',
      );
    }
    return CommandResult(
      exitCode: exitCodeForReads,
      standardOutput: exitCodeForReads == 0 ? _outputFor(arguments) : '',
      standardError: exitCodeForReads == 0 ? '' : 'Error: NetworkManager.',
    );
  }

  static bool _isRead(List<String> arguments) =>
      arguments.contains('show') && !arguments.contains('modify');

  String _outputFor(List<String> arguments) {
    if (arguments.contains('device')) return deviceOutput;
    final uuidIndex = arguments.indexOf('uuid');
    if (uuidIndex >= 0) {
      return connectionDetailsByUuid[arguments[uuidIndex + 1]] ?? '';
    }
    return connectionListOutput;
  }
}
