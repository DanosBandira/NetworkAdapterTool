import 'dart:convert';

import '../contracts/command_runner.dart';
import '../contracts/network_adapter_reader.dart';
import '../models/addressing_mode.dart';
import '../models/ipv4_address.dart';
import '../models/network_adapter.dart';

/// Reads adapters and their IPv4 settings by running a PowerShell script
/// that returns JSON.
///
/// `dart:io` only exposes adapter names and addresses; subnet mask, gateway,
/// DNS servers and DHCP state come from the NetTCPIP/DnsClient cmdlets.
/// One run takes about two seconds, mostly PowerShell and CIM startup.
class PowerShellNetworkAdapterReader implements NetworkAdapterReader {
  const PowerShellNetworkAdapterReader(this._commandRunner);

  static const _powerShellExecutable = 'powershell.exe';
  static const _byteOrderMark = '﻿';

  final CommandRunner _commandRunner;

  @override
  Future<List<NetworkAdapter>> readAllAdapters() async {
    final adaptersJson = await _runAdapterQueryScript();
    return _parseAdapters(adaptersJson);
  }

  @override
  Future<NetworkAdapter?> readAdapterByName(String adapterName) async {
    final adapters = await readAllAdapters();
    return adapters
        .where((adapter) => _isSameAdapterName(adapter.name, adapterName))
        .firstOrNull;
  }

  Future<String> _runAdapterQueryScript() async {
    final result = await _commandRunner.run(_powerShellExecutable, [
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      _encodeForPowerShellCommandLine(_adapterQueryScript),
    ], outputEncoding: utf8);
    if (result.exitCode != 0) {
      throw NetworkAdapterReadException(
        'PowerShell exited with code ${result.exitCode}: '
        '${result.standardError.trim()}',
      );
    }
    return result.standardOutput;
  }

  // -EncodedCommand takes Base64 of UTF-16LE text. It avoids having to escape
  // quotes and newlines of a multi-line script on the command line.
  String _encodeForPowerShellCommandLine(String script) {
    final utf16LittleEndianBytes = [
      for (final codeUnit in script.codeUnits) ...[
        codeUnit & 0xFF,
        codeUnit >> 8,
      ],
    ];
    return base64Encode(utf16LittleEndianBytes);
  }

  List<NetworkAdapter> _parseAdapters(String adaptersJson) {
    try {
      final adapterEntries =
          jsonDecode(_withoutByteOrderMark(adaptersJson)) as List<Object?>;
      return [
        for (final adapterEntry in adapterEntries)
          _parseAdapter(adapterEntry as Map<String, Object?>),
      ];
    } on FormatException catch (error) {
      throw NetworkAdapterReadException('Invalid JSON from PowerShell: $error');
    } on TypeError catch (error) {
      throw NetworkAdapterReadException('Unexpected JSON shape: $error');
    }
  }

  String _withoutByteOrderMark(String text) =>
      text.startsWith(_byteOrderMark) ? text.substring(1) : text;

  NetworkAdapter _parseAdapter(Map<String, Object?> adapterEntry) {
    final prefixLength = adapterEntry['prefixLength'] as int?;
    return NetworkAdapter(
      name: adapterEntry['name'] as String,
      description: adapterEntry['description'] as String? ?? '',
      status: _statusFromPowerShell(adapterEntry['status'] as String?),
      addressingMode: _addressingModeFromPowerShell(
        adapterEntry['dhcp'] as String?,
      ),
      ipAddress: adapterEntry['ipAddress'] as String?,
      subnetMask: prefixLength == null
          ? null
          : Ipv4Address.subnetMaskFromPrefixLength(prefixLength).toString(),
      defaultGateway: adapterEntry['defaultGateway'] as String?,
      dnsServers: List<String>.from(
        adapterEntry['dnsServers'] as List<Object?>? ?? const <Object?>[],
      ),
    );
  }

  NetworkAdapterStatus _statusFromPowerShell(String? status) {
    return switch (status) {
      'Up' => NetworkAdapterStatus.connected,
      'Disconnected' => NetworkAdapterStatus.disconnected,
      'Disabled' => NetworkAdapterStatus.disabled,
      _ => NetworkAdapterStatus.unknown,
    };
  }

  AddressingMode? _addressingModeFromPowerShell(String? dhcpState) {
    return switch (dhcpState) {
      'Enabled' => AddressingMode.dhcp,
      'Disabled' => AddressingMode.staticIp,
      _ => null,
    };
  }

  // Windows treats interface aliases case-insensitively.
  bool _isSameAdapterName(String first, String second) =>
      first.toLowerCase() == second.toLowerCase();
}

// Notes on the script:
// - Each cmdlet runs once for all adapters; per-adapter calls are much slower.
// - APIPA addresses (169.254.x.x, PrefixOrigin WellKnown) are sorted last, so
//   a disconnected static adapter shows its configured address.
// - Disconnected adapters have no active routes; their static gateway only
//   exists in the PersistentStore.
// - UTF-8 without BOM keeps non-ASCII adapter names intact.
const _adapterQueryScript = r'''
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

$ipInterfaces = @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue)
$ipAddresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue)
$activeDefaultRoutes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)
$persistentDefaultRoutes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -PolicyStore PersistentStore -ErrorAction SilentlyContinue)
$dnsAddresses = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue)

$adapters = foreach ($adapter in Get-NetAdapter) {
    $index = $adapter.ifIndex
    $ipInterface = $ipInterfaces | Where-Object InterfaceIndex -eq $index | Select-Object -First 1
    $ipAddress = $ipAddresses | Where-Object InterfaceIndex -eq $index |
        Sort-Object { $_.PrefixOrigin -eq 'WellKnown' } | Select-Object -First 1
    $defaultRoute = @($activeDefaultRoutes + $persistentDefaultRoutes) |
        Where-Object InterfaceIndex -eq $index | Select-Object -First 1
    $dns = $dnsAddresses | Where-Object InterfaceIndex -eq $index | Select-Object -First 1

    [PSCustomObject]@{
        name           = $adapter.Name
        description    = $adapter.InterfaceDescription
        status         = [string]$adapter.Status
        dhcp           = [string]$ipInterface.Dhcp
        ipAddress      = $ipAddress.IPAddress
        prefixLength   = $ipAddress.PrefixLength
        defaultGateway = $defaultRoute.NextHop
        dnsServers     = @($dns.ServerAddresses)
    }
}

ConvertTo-Json -InputObject @($adapters) -Depth 3 -Compress
''';
