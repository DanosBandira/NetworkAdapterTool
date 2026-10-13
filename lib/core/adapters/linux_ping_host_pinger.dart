import 'dart:io';

import '../contracts/command_runner.dart';
import '../contracts/host_pinger.dart';

/// Pings through the Linux `ping` (iputils), because Dart has no ICMP
/// support of its own. Most distributions let it run without root.
///
/// Unlike ping.exe, it exits with 0 only when an echo reply arrived, so the
/// exit code alone decides.
class LinuxPingHostPinger implements HostPinger {
  const LinuxPingHostPinger(this._commandRunner);

  static const _pingExecutable = 'ping';

  // "time=0.045 ms" or "time=12.3 ms"; iputils does not translate it.
  static final _roundTripTimePattern = RegExp(r'time[=<]\s*([\d.]+)\s*ms');

  final CommandRunner _commandRunner;

  @override
  Future<Duration?> pingOnce(String ipAddress, Duration timeout) async {
    final CommandResult result;
    try {
      result = await _commandRunner.run(_pingExecutable, [
        '-n',
        '-c',
        '1',
        // Whole seconds: older iputils versions reject fractions.
        '-W',
        '${_wholeSecondsAtLeastOne(timeout)}',
        ipAddress,
      ]);
    } on ProcessException {
      return null;
    }
    return result.exitCode == 0
        ? _roundTripTimeIn(result.standardOutput)
        : null;
  }

  int _wholeSecondsAtLeastOne(Duration timeout) {
    final seconds = (timeout.inMilliseconds / 1000).ceil();
    return seconds < 1 ? 1 : seconds;
  }

  Duration _roundTripTimeIn(String output) {
    final milliseconds = double.tryParse(
      _roundTripTimePattern.firstMatch(output)?[1] ?? '',
    );
    if (milliseconds == null || milliseconds < 1) return Duration.zero;
    return Duration(milliseconds: milliseconds.round());
  }
}
