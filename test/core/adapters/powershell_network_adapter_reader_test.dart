import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:network_profile_switcher/core/adapters/powershell_network_adapter_reader.dart';
import 'package:network_profile_switcher/core/contracts/network_adapter_reader.dart';
import 'package:network_profile_switcher/core/models/addressing_mode.dart';
import 'package:network_profile_switcher/core/models/network_adapter.dart';

import '../../fakes/recording_command_runner.dart';

// Shaped after real script output on Windows 11 (PowerShell 5.1), plus a
// disabled adapter, which has no IPv4 interface and therefore no DHCP state.
const _capturedAdaptersJson = '''
[
  {"name":"Wi-Fi","description":"Intel(R) Wi-Fi 6E AX211 160MHz","status":"Up",
   "dhcp":"Enabled","ipAddress":"192.168.2.6","prefixLength":24,
   "defaultGateway":"192.168.2.254","dnsServers":["192.168.2.254"]},
  {"name":"Ethernet","description":"Intel(R) Ethernet Connection (18) I219-V",
   "status":"Disconnected","dhcp":"Disabled","ipAddress":"10.100.10.3",
   "prefixLength":24,"defaultGateway":null,"dnsServers":[]},
  {"name":"vEthernet (WSL (Hyper-V firewall))",
   "description":"Hyper-V Virtual Ethernet Adapter #2","status":"Up",
   "dhcp":"Disabled","ipAddress":"172.29.208.1","prefixLength":20,
   "defaultGateway":null,"dnsServers":[]},
  {"name":"Netwerkverbinding über USB","description":"USB Ethernet",
   "status":"Disabled","dhcp":"","ipAddress":null,"prefixLength":null,
   "defaultGateway":null,"dnsServers":[]}
]
''';

void main() {
  PowerShellNetworkAdapterReader readerReturning(String standardOutput) {
    return PowerShellNetworkAdapterReader(
      RecordingCommandRunner(standardOutputForEveryCall: standardOutput),
    );
  }

  test('reads a DHCP adapter with gateway and DNS', () async {
    final adapters = await readerReturning(_capturedAdaptersJson)
        .readAllAdapters();

    final wifi = adapters.first;
    expect(wifi.name, 'Wi-Fi');
    expect(wifi.description, 'Intel(R) Wi-Fi 6E AX211 160MHz');
    expect(wifi.status, NetworkAdapterStatus.connected);
    expect(wifi.addressingMode, AddressingMode.dhcp);
    expect(wifi.ipAddress, '192.168.2.6');
    expect(wifi.subnetMask, '255.255.255.0');
    expect(wifi.defaultGateway, '192.168.2.254');
    expect(wifi.dnsServers, ['192.168.2.254']);
  });

  test('reads a disconnected static adapter without gateway or DNS', () async {
    final adapters = await readerReturning(_capturedAdaptersJson)
        .readAllAdapters();

    final ethernet = adapters[1];
    expect(ethernet.status, NetworkAdapterStatus.disconnected);
    expect(ethernet.addressingMode, AddressingMode.staticIp);
    expect(ethernet.defaultGateway, isNull);
    expect(ethernet.dnsServers, isEmpty);
  });

  test('converts a non-octet prefix length to a dotted subnet mask', () async {
    final adapters = await readerReturning(_capturedAdaptersJson)
        .readAllAdapters();

    expect(adapters[2].subnetMask, '255.255.240.0');
  });

  test('reads a disabled adapter without IPv4 settings', () async {
    final adapters = await readerReturning(_capturedAdaptersJson)
        .readAllAdapters();

    final disabled = adapters[3];
    expect(disabled.name, 'Netwerkverbinding über USB');
    expect(disabled.status, NetworkAdapterStatus.disabled);
    expect(disabled.addressingMode, isNull);
    expect(disabled.ipAddress, isNull);
    expect(disabled.subnetMask, isNull);
  });

  test('reads an empty adapter list', () async {
    final adapters = await readerReturning('[]').readAllAdapters();

    expect(adapters, isEmpty);
  });

  test('ignores a leading byte order mark', () async {
    final adapters = await readerReturning('﻿[]').readAllAdapters();

    expect(adapters, isEmpty);
  });

  test('finds an adapter by name, ignoring case', () async {
    final adapter = await readerReturning(_capturedAdaptersJson)
        .readAdapterByName('ETHERNET');

    expect(adapter?.name, 'Ethernet');
  });

  test('returns null for an unknown adapter name', () async {
    final adapter = await readerReturning(_capturedAdaptersJson)
        .readAdapterByName('Ethernet 9');

    expect(adapter, isNull);
  });

  test('runs PowerShell without profile and decodes output as UTF-8', () async {
    final commandRunner = RecordingCommandRunner(
      standardOutputForEveryCall: '[]',
    );

    await PowerShellNetworkAdapterReader(commandRunner).readAllAdapters();

    final command = commandRunner.recordedCommands.single;
    expect(command.executable, 'powershell.exe');
    expect(command.arguments.take(3), [
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
    ]);
    expect(command.outputEncoding, utf8);
  });

  test('encodes the script as Base64 UTF-16LE', () async {
    final commandRunner = RecordingCommandRunner(
      standardOutputForEveryCall: '[]',
    );

    await PowerShellNetworkAdapterReader(commandRunner).readAllAdapters();

    final encodedScript = commandRunner.recordedCommands.single.arguments.last;
    final scriptBytes = base64Decode(encodedScript);
    final script = String.fromCharCodes([
      for (var index = 0; index < scriptBytes.length; index += 2)
        scriptBytes[index] | (scriptBytes[index + 1] << 8),
    ]);
    expect(script, contains('Get-NetAdapter'));
    expect(script, contains('ConvertTo-Json'));
  });

  test('fails when PowerShell exits with an error', () async {
    final reader = PowerShellNetworkAdapterReader(
      RecordingCommandRunner(
        exitCodeForEveryCall: 1,
        standardErrorForEveryCall: 'Get-NetAdapter : Access denied',
      ),
    );

    await expectLater(
      reader.readAllAdapters(),
      throwsA(
        isA<NetworkAdapterReadException>().having(
          (error) => error.reason,
          'reason',
          contains('Access denied'),
        ),
      ),
    );
  });

  test('fails on output that is not JSON', () async {
    await expectLater(
      readerReturning('WARNING: something').readAllAdapters(),
      throwsA(isA<NetworkAdapterReadException>()),
    );
  });

  test('fails on JSON with an unexpected shape', () async {
    await expectLater(
      readerReturning('{"name":"Wi-Fi"}').readAllAdapters(),
      throwsA(isA<NetworkAdapterReadException>()),
    );
  });
}
