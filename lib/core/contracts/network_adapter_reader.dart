import '../models/network_adapter.dart';

/// Reads network adapters and their current IPv4 settings from the system.
abstract interface class NetworkAdapterReader {
  /// Throws [NetworkAdapterReadException] when the system cannot be queried.
  Future<List<NetworkAdapter>> readAllAdapters();

  /// Returns `null` when no adapter with [adapterName] exists.
  ///
  /// Throws [NetworkAdapterReadException] when the system cannot be queried.
  Future<NetworkAdapter?> readAdapterByName(String adapterName);
}

/// Thrown when the adapter list cannot be read from the system.
class NetworkAdapterReadException implements Exception {
  const NetworkAdapterReadException(this.reason);

  final String reason;

  @override
  String toString() => 'NetworkAdapterReadException: $reason';
}
