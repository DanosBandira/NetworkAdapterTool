import 'package:network_adapter_tool/core/contracts/host_pinger.dart';

/// A [HostPinger] that answers from a script per address: each attempt takes
/// the next entry (`null` = no reply), and the last entry repeats. Addresses
/// without a script never reply.
class ScriptedHostPinger implements HostPinger {
  ScriptedHostPinger([
    Map<String, List<Duration?>> repliesPerAddress = const {},
  ]) : _repliesPerAddress = repliesPerAddress;

  final Map<String, List<Duration?>> _repliesPerAddress;
  final Map<String, int> attemptsPerAddress = {};

  @override
  Future<Duration?> pingOnce(String ipAddress, Duration timeout) async {
    final attempt = attemptsPerAddress.update(
      ipAddress,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    final replies = _repliesPerAddress[ipAddress];
    if (replies == null || replies.isEmpty) return null;
    return replies[(attempt - 1).clamp(0, replies.length - 1)];
  }
}
