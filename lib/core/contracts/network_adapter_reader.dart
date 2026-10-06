import '../models/network_adapter.dart';

/// Reads network adapters and their current IPv4 settings from the system.
abstract interface class NetworkAdapterReader {
  Future<List<NetworkAdapter>> readAllAdapters();

  /// Returns `null` when no adapter with [adapterName] exists.
  Future<NetworkAdapter?> readAdapterByName(String adapterName);
}
