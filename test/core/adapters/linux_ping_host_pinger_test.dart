import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/adapters/linux_ping_host_pinger.dart';

import '../../fakes/recording_command_runner.dart';

// Output in the format of iputils ping on Linux; written from its manual,
// replace with captured output once a Linux machine is available.
const _replyOfTwelveMilliseconds = '''
PING 10.100.10.1 (10.100.10.1) 56(84) bytes of data.
64 bytes from 10.100.10.1: icmp_seq=1 ttl=64 time=12.3 ms
''';
const _replyBelowOneMillisecond = '''
PING 10.100.10.1 (10.100.10.1) 56(84) bytes of data.
64 bytes from 10.100.10.1: icmp_seq=1 ttl=64 time=0.045 ms
''';

void main() {
  Future<Duration?> pingWithOutput(String output, {int exitCode = 0}) {
    final commandRunner = RecordingCommandRunner(
      exitCodeForEveryCall: exitCode,
      standardOutputForEveryCall: output,
    );
    return LinuxPingHostPinger(commandRunner)
        .pingOnce('10.100.10.1', const Duration(seconds: 1));
  }

  test('sends one echo request with a timeout in whole seconds', () async {
    final commandRunner = RecordingCommandRunner(
      standardOutputForEveryCall: _replyOfTwelveMilliseconds,
    );

    await LinuxPingHostPinger(commandRunner)
        .pingOnce('10.100.10.1', const Duration(milliseconds: 1500));

    final command = commandRunner.recordedCommands.single;
    expect(command.executable, 'ping');
    expect(command.arguments, ['-n', '-c', '1', '-W', '2', '10.100.10.1']);
  });

  test('reads the round-trip time of a reply', () async {
    expect(
      await pingWithOutput(_replyOfTwelveMilliseconds),
      const Duration(milliseconds: 12),
    );
  });

  test('reports a reply below 1 ms as zero', () async {
    expect(await pingWithOutput(_replyBelowOneMillisecond), Duration.zero);
  });

  test('a non-zero exit code means no reply', () async {
    expect(await pingWithOutput('', exitCode: 1), isNull);
  });
}
