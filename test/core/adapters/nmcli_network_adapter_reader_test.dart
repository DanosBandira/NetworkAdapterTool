import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/adapters/nmcli_client.dart';
import 'package:network_adapter_tool/core/adapters/nmcli_network_adapter_reader.dart';
import 'package:network_adapter_tool/core/contracts/network_adapter_reader.dart';
import 'package:network_adapter_tool/core/models/addressing_mode.dart';
import 'package:network_adapter_tool/core/models/network_adapter.dart';

import '../../fakes/scripted_nmcli_command_runner.dart';
import 'nmcli_samples.dart';

void main() {
  ScriptedNmcliCommandRunner sampleRunner({int exitCodeForReads = 0}) {
    return ScriptedNmcliCommandRunner(
      deviceOutput: nmcliDeviceOutput,
      connectionListOutput: nmcliConnectionListOutput,
      connectionDetailsByUuid: nmcliConnectionDetails,
      exitCodeForReads: exitCodeForReads,
    );
  }

  NmcliNetworkAdapterReader readerOver(ScriptedNmcliCommandRunner runner) =>
      NmcliNetworkAdapterReader(NmcliClient(runner));

  Future<NetworkAdapter> adapterNamed(String name) async {
    final adapter = await readerOver(sampleRunner()).readAdapterByName(name);
    return adapter!;
  }

  test('lists wired and wireless devices, not loopback', () async {
    final adapters = await readerOver(sampleRunner()).readAllAdapters();

    expect(
      [for (final adapter in adapters) adapter.name],
      ['enp3s0', 'enx001122334455', 'wlp2s0'],
    );
  });

  test('shows the live settings of a connected DHCP device', () async {
    final adapter = await adapterNamed('enp3s0');

    expect(adapter.status, NetworkAdapterStatus.connected);
    expect(adapter.addressingMode, AddressingMode.dhcp);
    expect(adapter.ipAddress, '192.168.1.20');
    expect(adapter.subnetMask, '255.255.255.0');
    expect(adapter.defaultGateway, '192.168.1.1');
    expect(adapter.dnsServers, ['192.168.1.1', '8.8.8.8']);
    expect(adapter.description, 'Ethernet · Wired connection 1');
  });

  test('shows the stored settings of a static device without cable', () async {
    final adapter = await adapterNamed('enx001122334455');

    expect(adapter.status, NetworkAdapterStatus.disconnected);
    expect(adapter.addressingMode, AddressingMode.staticIp);
    expect(adapter.ipAddress, '10.100.10.4');
    expect(adapter.subnetMask, '255.255.255.0');
    expect(adapter.defaultGateway, '10.100.10.1');
    expect(adapter.dnsServers, ['10.100.10.1', '8.8.8.8']);
    expect(adapter.description, 'Ethernet · Machine: line 1');
  });

  test('a device without a saved connection has no addressing mode', () async {
    final adapter = await adapterNamed('wlp2s0');

    expect(adapter.status, NetworkAdapterStatus.disconnected);
    expect(adapter.addressingMode, isNull);
    expect(adapter.ipAddress, isNull);
    expect(adapter.description, 'Wi-Fi');
  });

  test('reports that NetworkManager is not running', () async {
    final reader = readerOver(
      sampleRunner(
        exitCodeForReads: NmcliClient.networkManagerNotRunningExitCode,
      ),
    );

    expect(
      reader.readAllAdapters,
      throwsA(
        isA<NetworkAdapterReadException>().having(
          (error) => error.reason,
          'reason',
          contains('NetworkManager is not running'),
        ),
      ),
    );
  });

  group('terse output', () {
    test('splits table fields at unescaped colons', () {
      expect(NmcliClient.splitTerseFields(r'Machine\: line 1:uuid:type:'), [
        'Machine: line 1',
        'uuid',
        'type',
        '',
      ]);
    });

    test('collects numbered keys under one key', () {
      final records = NmcliClient.parseTerseRecords(
        'IP4.DNS[1]:10.0.0.1\nIP4.DNS[2]:10.0.0.2\n',
      );

      expect(records.single['IP4.DNS'], ['10.0.0.1', '10.0.0.2']);
    });
  });
}
