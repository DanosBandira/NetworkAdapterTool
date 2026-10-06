import 'package:flutter_test/flutter_test.dart';
import 'package:network_profile_switcher/core/adapters/process_command_runner.dart';

// Uses harmless cmd.exe built-ins only; never netsh.
void main() {
  const commandRunner = ProcessCommandRunner();

  test('returns standard output of the process', () async {
    final result = await commandRunner.run('cmd.exe', ['/c', 'echo', 'hello']);

    expect(result.exitCode, 0);
    expect(result.standardOutput.trim(), 'hello');
  });

  test('returns the exit code of the process', () async {
    final result = await commandRunner.run('cmd.exe', ['/c', 'exit', '3']);

    expect(result.exitCode, 3);
  });
}
