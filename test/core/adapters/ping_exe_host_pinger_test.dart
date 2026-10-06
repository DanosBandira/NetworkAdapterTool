import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/adapters/ping_exe_host_pinger.dart';

import '../../fakes/recording_command_runner.dart';

// Output samples as printed by ping.exe on Windows 11.
const _englishReply = '''
Pinging 10.100.10.1 with 32 bytes of data:
Reply from 10.100.10.1: bytes=32 time=3ms TTL=64
''';
const _dutchReplyBelowOneMillisecond = '''
Pingen naar 10.100.10.1 met 32 bytes aan gegevens:
Antwoord van 10.100.10.1: bytes=32 tijd<1ms TTL=128
''';
const _dutchHostUnreachable = '''
Pingen naar 10.100.10.9 met 32 bytes aan gegevens:
Antwoord van 10.100.10.4: Doelhost onbereikbaar.
''';
const _englishTimeout = '''
Pinging 10.100.10.9 with 32 bytes of data:
Request timed out.
''';

void main() {
  Future<Duration?> pingWithOutput(String output, {int exitCode = 0}) {
    final commandRunner = RecordingCommandRunner(
      exitCodeForEveryCall: exitCode,
      standardOutputForEveryCall: output,
    );
    return PingExeHostPinger(commandRunner)
        .pingOnce('10.100.10.1', const Duration(seconds: 1));
  }

  test('sends one IPv4 echo request with the timeout in ms', () async {
    final commandRunner = RecordingCommandRunner(
      standardOutputForEveryCall: _englishReply,
    );

    await PingExeHostPinger(commandRunner)
        .pingOnce('10.100.10.1', const Duration(milliseconds: 1500));

    final command = commandRunner.recordedCommands.single;
    expect(command.executable, 'ping.exe');
    expect(command.arguments, ['-4', '-n', '1', '-w', '1500', '10.100.10.1']);
  });

  test('reads the round-trip time of a reply', () async {
    expect(
      await pingWithOutput(_englishReply),
      const Duration(milliseconds: 3),
    );
  });

  test('reports a reply below 1 ms as zero, in a localized output', () async {
    expect(await pingWithOutput(_dutchReplyBelowOneMillisecond), Duration.zero);
  });

  test(
    'treats "destination host unreachable" with exit code 0 as no reply',
    () async {
      expect(await pingWithOutput(_dutchHostUnreachable), isNull);
    },
  );

  test('treats a timeout as no reply', () async {
    expect(await pingWithOutput(_englishTimeout, exitCode: 1), isNull);
  });
}
