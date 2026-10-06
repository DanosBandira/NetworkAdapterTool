import '../models/network_profile.dart';

/// Applies the IPv4 settings of a profile to a network adapter.
///
/// Implementations do not validate the profile and do not verify the
/// result; both are the responsibility of the caller.
abstract interface class NetworkAdapterConfigurator {
  /// Throws [NetworkConfigurationException] when the system rejects a setting.
  Future<void> applyProfileToAdapter(NetworkProfile profile, String adapterName);
}

/// Thrown when the system refuses to apply a network setting.
class NetworkConfigurationException implements Exception {
  const NetworkConfigurationException({
    required this.failedCommand,
    required this.exitCode,
    required this.output,
  });

  final String failedCommand;
  final int exitCode;
  final String output;

  @override
  String toString() =>
      'NetworkConfigurationException: "$failedCommand" failed with exit code '
      '$exitCode: $output';
}
