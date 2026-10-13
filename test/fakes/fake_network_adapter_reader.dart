import 'package:network_adapter_tool/core/contracts/network_adapter_reader.dart';
import 'package:network_adapter_tool/core/models/network_adapter.dart';

/// A [NetworkAdapterReader] that returns prepared snapshots in sequence, to
/// simulate settings that only become active after a while.
///
/// After the last snapshot it keeps returning that one.
class FakeNetworkAdapterReader implements NetworkAdapterReader {
  FakeNetworkAdapterReader(
    this._snapshotsPerRead, {
    this.readError,
    this.otherAdapters = const [],
  });

  final List<NetworkAdapter?> _snapshotsPerRead;
  final NetworkAdapterReadException? readError;

  /// Listed by [readAllAdapters] after the scripted adapter.
  final List<NetworkAdapter> otherAdapters;
  int readCount = 0;

  @override
  Future<List<NetworkAdapter>> readAllAdapters() async {
    final adapter = await readAdapterByName('');
    return [?adapter, ...otherAdapters];
  }

  @override
  Future<NetworkAdapter?> readAdapterByName(String adapterName) async {
    readCount++;
    if (readError != null) throw readError!;
    final snapshotIndex = (readCount - 1).clamp(
      0,
      _snapshotsPerRead.length - 1,
    );
    return _snapshotsPerRead[snapshotIndex];
  }
}
