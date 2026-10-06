/// Sends a single ICMP echo request to an IPv4 address.
abstract interface class HostPinger {
  /// Returns the round-trip time, or `null` when no echo reply arrived within
  /// [timeout]. A reply below 1 ms is reported as [Duration.zero].
  Future<Duration?> pingOnce(String ipAddress, Duration timeout);
}
