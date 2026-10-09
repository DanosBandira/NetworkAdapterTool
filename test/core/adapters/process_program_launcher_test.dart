import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/adapters/process_program_launcher.dart';
import 'package:network_adapter_tool/core/contracts/program_launcher.dart';

// Uses harmless cmd.exe built-ins and a ping to the local machine only.
void main() {
  const launcher = ProcessProgramLauncher();
  final workingDirectory = Directory.systemTemp.path;

  test('returns exit code and output of the program', () async {
    final program = await launcher.start('cmd.exe', [
      '/c',
      'echo hello& echo oops 1>&2& exit 3',
    ], workingDirectory: workingDirectory);

    final result = await program.result;

    expect(result.exitCode, 3);
    expect(result.output, contains('hello'));
    expect(result.output, contains('oops'));
  });

  // Compares by a file inside the folder: the temp path may be reported as
  // a short 8.3 name on one side and a long name on the other.
  test('runs the program in the given folder', () async {
    final folder = await Directory.systemTemp.createTemp('launcher_test');
    addTearDown(() => folder.delete(recursive: true));
    await File('${folder.path}${Platform.pathSeparator}marker.txt').create();
    final program = await launcher.start('cmd.exe', [
      '/c',
      'dir',
      '/b',
    ], workingDirectory: folder.path);

    final result = await program.result;

    expect(result.output.trim(), 'marker.txt');
  });

  test('stops a program that keeps running', () async {
    final program = await launcher.start('ping.exe', [
      '-n',
      '30',
      '127.0.0.1',
    ], workingDirectory: workingDirectory);

    await program.stop();
    final result = await program.result.timeout(const Duration(seconds: 10));

    expect(result.exitCode, isNot(0));
  });

  test('throws when the program does not exist', () async {
    await expectLater(
      launcher.start(
        r'C:\does\not\exist.exe',
        const [],
        workingDirectory: workingDirectory,
      ),
      throwsA(isA<ProgramStartException>()),
    );
  });
}
