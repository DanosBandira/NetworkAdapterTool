import '../contracts/command_runner.dart';
import '../contracts/network_adapter_configurator.dart';
import '../models/addressing_mode.dart';
import '../models/network_profile.dart';

/// Applies a [NetworkProfile] to an adapter by translating it into
/// `netsh interface ipv4` commands.
///
/// Settings a profile leaves out (gateway, DNS) are cleared explicitly with
/// `none`, so values from a previously applied profile do not linger.
class NetshNetworkAdapterConfigurator implements NetworkAdapterConfigurator {
  const NetshNetworkAdapterConfigurator(this._commandRunner);

  static const _netshExecutable = 'netsh.exe';
  static const _successExitCode = 0;

  // netsh exits with 1 when DHCP is already enabled. It uses the same code for
  // real errors (e.g. an unknown adapter name) and its message is localized,
  // so the two cannot be told apart here; NetworkProfileApplier catches real
  // failures by re-reading the adapter afterwards.
  static const _dhcpAlreadyEnabledExitCode = 1;

  final CommandRunner _commandRunner;

  @override
  Future<void> applyProfileToAdapter(
    NetworkProfile profile,
    String adapterName,
  ) async {
    switch (profile.addressingMode) {
      case AddressingMode.dhcp:
        await _switchAdapterToDhcp(adapterName);
      case AddressingMode.staticIp:
        await _applyStaticAddress(profile, adapterName);
        await _applyStaticDnsServers(profile.dnsServers, adapterName);
    }
  }

  Future<void> _switchAdapterToDhcp(String adapterName) async {
    await _runNetshToleratingDhcpAlreadyEnabled([
      ..._ipv4Command('set', 'address'),
      'name=$adapterName',
      'source=dhcp',
    ]);
    await _runNetshToleratingDhcpAlreadyEnabled([
      ..._ipv4Command('set', 'dnsservers'),
      'name=$adapterName',
      'source=dhcp',
    ]);
  }

  Future<void> _applyStaticAddress(
    NetworkProfile profile,
    String adapterName,
  ) async {
    await _runNetsh([
      ..._ipv4Command('set', 'address'),
      'name=$adapterName',
      'source=static',
      'address=${profile.ipAddress}',
      'mask=${profile.subnetMask}',
      'gateway=${profile.defaultGateway ?? 'none'}',
    ]);
  }

  Future<void> _applyStaticDnsServers(
    List<String> dnsServers,
    String adapterName,
  ) async {
    if (dnsServers.isEmpty) {
      await _clearDnsServers(adapterName);
      return;
    }
    await _setPrimaryDnsServer(dnsServers.first, adapterName);
    await _addSecondaryDnsServers(dnsServers.skip(1).toList(), adapterName);
  }

  Future<void> _clearDnsServers(String adapterName) async {
    await _runNetsh([
      ..._ipv4Command('set', 'dnsservers'),
      'name=$adapterName',
      'source=static',
      'address=none',
    ]);
  }

  Future<void> _setPrimaryDnsServer(
    String dnsServer,
    String adapterName,
  ) async {
    await _runNetsh([
      ..._ipv4Command('set', 'dnsservers'),
      'name=$adapterName',
      'source=static',
      'address=$dnsServer',
      'register=primary',
      ..._skipDnsReachabilityCheck(),
    ]);
  }

  Future<void> _addSecondaryDnsServers(
    List<String> secondaryDnsServers,
    String adapterName,
  ) async {
    for (final (offset, dnsServer) in secondaryDnsServers.indexed) {
      // netsh indexes are 1-based and the primary server already holds 1.
      final netshIndex = offset + 2;
      await _runNetsh([
        ..._ipv4Command('add', 'dnsservers'),
        'name=$adapterName',
        'address=$dnsServer',
        'index=$netshIndex',
        ..._skipDnsReachabilityCheck(),
      ]);
    }
  }

  List<String> _ipv4Command(String verb, String setting) =>
      ['interface', 'ipv4', verb, setting];

  // Without this netsh tries to reach each DNS server first, which fails or
  // stalls on isolated machine networks.
  List<String> _skipDnsReachabilityCheck() => ['validate=no'];

  Future<void> _runNetshToleratingDhcpAlreadyEnabled(List<String> arguments) =>
      _runNetsh(
        arguments,
        acceptedExitCodes: const {
          _successExitCode,
          _dhcpAlreadyEnabledExitCode,
        },
      );

  Future<void> _runNetsh(
    List<String> arguments, {
    Set<int> acceptedExitCodes = const {_successExitCode},
  }) async {
    final result = await _commandRunner.run(_netshExecutable, arguments);
    if (!acceptedExitCodes.contains(result.exitCode)) {
      throw NetworkConfigurationException(
        failedCommand: '$_netshExecutable ${arguments.join(' ')}',
        exitCode: result.exitCode,
        output: '${result.standardOutput}${result.standardError}'.trim(),
      );
    }
  }
}
