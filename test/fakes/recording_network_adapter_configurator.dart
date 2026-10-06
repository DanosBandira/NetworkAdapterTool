import 'package:network_adapter_tool/core/contracts/network_adapter_configurator.dart';
import 'package:network_adapter_tool/core/models/network_profile.dart';

/// A [NetworkAdapterConfigurator] that records what it was asked to apply,
/// optionally failing like netsh would.
class RecordingNetworkAdapterConfigurator
    implements NetworkAdapterConfigurator {
  RecordingNetworkAdapterConfigurator({this.errorToThrow});

  final NetworkConfigurationException? errorToThrow;
  final List<(NetworkProfile, String)> appliedProfiles = [];

  @override
  Future<void> applyProfileToAdapter(
    NetworkProfile profile,
    String adapterName,
  ) async {
    appliedProfiles.add((profile, adapterName));
    if (errorToThrow != null) throw errorToThrow!;
  }
}
