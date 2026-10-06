import '../contracts/command_runner.dart';
import '../contracts/host_pinger.dart';

/// Pings through `ping.exe`, because Dart has no ICMP support of its own.
class PingExeHostPinger implements HostPinger {
  const PingExeHostPinger(this._commandRunner);

  static const _pingExecutable = 'ping.exe';

  // ping.exe also exits with 0 when a router answers "Destination host
  // unreachable", so a real echo reply is recognized by "TTL=", which only
  // appears in replies from the target and is not localized.
  static const _echoReplyMarker = 'TTL=';

  // Matches "time=3ms", "tijd<1ms", "Zeit=12ms": the label is localized,
  // the "=" or "<" and the "ms" unit are not.
  static final _roundTripTimePattern = RegExp(r'([=<])\s*(\d+)\s*ms');

  final CommandRunner _commandRunner;

  @override
  Future<Duration?> pingOnce(String ipAddress, Duration timeout) async {
    final result = await _commandRunner.run(_pingExecutable, [
      '-4',
      '-n',
      '1',
      '-w',
      '${timeout.inMilliseconds}',
      ipAddress,
    ]);
    final isEchoReply =
        result.exitCode == 0 &&
        result.standardOutput.toUpperCase().contains(_echoReplyMarker);
    return isEchoReply ? _roundTripTimeIn(result.standardOutput) : null;
  }

  Duration _roundTripTimeIn(String output) {
    final match = _roundTripTimePattern.firstMatch(output);
    if (match == null || match[1] == '<') return Duration.zero;
    return Duration(milliseconds: int.parse(match[2]!));
  }
}
