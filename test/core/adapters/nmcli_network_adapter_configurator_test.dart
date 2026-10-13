import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/adapters/nmcli_client.dart';
import 'package:network_adapter_tool/core/adapters/nmcli_network_adapter_configurator.dart';
import 'package:network_adapter_tool/core/contracts/network_adapter_configurator.dart';
import 'package:network_adapter_tool/core/models/addressing_mode.dart';
import 'package:network_adapter_tool/core/models/network_profile.dart';

import '../../fakes/scripted_nmcli_command_runner.dart';
import 'nmcli_samples.dart';

void main() {
  const staticProfile = NetworkProfile(
    name: 'Machine',
    addressingMode: AddressingMode.staticIp,
    ipAddress: '10.100.10.5',
    subnetMask: '255.255.255.0',
    defaultGateway: '10.100.10.1',
    dnsServers: ['10.100.10.1', '8.8.8.8'],
  );
  const staticProfileWithoutExtras = NetworkProfile(
    name: 'Direct',
    addressingMode: AddressingMode.staticIp,
    ipAddress: '192.168.0.10',
    subnetMask: '255.255.0.0',
  );
  const dhcpProfile = NetworkProfile(
    name: 'Office',
    addressingMode: AddressingMode.dhcp,
  );

  ScriptedNmcliCommandRunner sampleRunner({
    int exitCodeForChanges = 0,
    void Function(List<String> arguments)? onChange,
  }) {
    return ScriptedNmcliCommandRunner(
      deviceOutput: nmcliDeviceOutput,
      connectionListOutput: nmcliConnectionListOutput,
      connectionDetailsByUuid: Map.of(nmcliConnectionDetails),
      exitCodeForChanges: exitCodeForChanges,
      onChange: onChange,
    );
  }

  NmcliNetworkAdapterConfigurator configuratorOver(
    ScriptedNmcliCommandRunner runner,
  ) => NmcliNetworkAdapterConfigurator(NmcliClient(runner));

  test('sets a static profile in the connection of the device', () async {
    final runner = sampleRunner();

    await configuratorOver(runner)
        .applyProfileToAdapter(staticProfile, 'enx001122334455');

    expect(runner.changes.first, [
      'connection',
      'modify',
      'uuid',
      machineUuid,
      'ipv4.method',
      'manual',
      'ipv4.addresses',
      '10.100.10.5/24',
      'ipv4.gateway',
      '10.100.10.1',
      'ipv4.dns',
      '10.100.10.1,8.8.8.8',
      'ipv4.ignore-auto-dns',
      'yes',
    ]);
  });

  test('clears gateway and DNS a static profile leaves out', () async {
    final runner = sampleRunner();

    await configuratorOver(runner)
        .applyProfileToAdapter(staticProfileWithoutExtras, 'enx001122334455');

    final modify = runner.changes.first;
    expect(modify[modify.indexOf('ipv4.addresses') + 1], '192.168.0.10/16');
    expect(modify[modify.indexOf('ipv4.gateway') + 1], '');
    expect(modify[modify.indexOf('ipv4.dns') + 1], '');
  });

  test(
    'stores the settings without activating a device without cable',
    () async {
      final runner = sampleRunner();

      await configuratorOver(runner)
          .applyProfileToAdapter(staticProfile, 'enx001122334455');

      expect(runner.changes, hasLength(1));
    },
  );

  test('switches a connected device to DHCP and activates it', () async {
    final runner = sampleRunner();

    await configuratorOver(runner).applyProfileToAdapter(dhcpProfile, 'enp3s0');

    expect(runner.changes, [
      [
        'connection',
        'modify',
        'uuid',
        wiredUuid,
        'ipv4.method',
        'auto',
        'ipv4.addresses',
        '',
        'ipv4.gateway',
        '',
        'ipv4.dns',
        '',
        'ipv4.ignore-auto-dns',
        'no',
      ],
      [
        '--wait',
        '30',
        'connection',
        'up',
        'uuid',
        wiredUuid,
        'ifname',
        'enp3s0',
      ],
    ]);
  });

  test('creates a connection for a wired device that has none', () async {
    const newUuid = '5f1c7a3e-0000-4000-8000-000000000009';
    late ScriptedNmcliCommandRunner runner;
    runner = sampleRunner(
      onChange: (arguments) {
        if (!arguments.contains('add')) return;
        runner.connectionListOutput += 'enp4s0:$newUuid:802-3-ethernet:\n';
        runner.connectionDetailsByUuid[newUuid] =
            'connection.interface-name:enp4s0\nipv4.method:auto\n';
      },
    );
    runner.deviceOutput +=
        '\nGENERAL.DEVICE:enp4s0\nGENERAL.TYPE:ethernet\n'
        'GENERAL.STATE:30 (disconnected)\n';

    await configuratorOver(runner).applyProfileToAdapter(dhcpProfile, 'enp4s0');

    expect(runner.changes.first, [
      'connection',
      'add',
      'type',
      'ethernet',
      'ifname',
      'enp4s0',
      'con-name',
      'enp4s0',
    ]);
    expect(runner.changes[1].sublist(0, 4), [
      'connection',
      'modify',
      'uuid',
      newUuid,
    ]);
  });

  test('refuses a Wi-Fi device without a saved connection', () async {
    final runner = sampleRunner();

    await expectLater(
      configuratorOver(runner).applyProfileToAdapter(dhcpProfile, 'wlp2s0'),
      throwsA(
        isA<NetworkConfigurationException>().having(
          (error) => error.output,
          'output',
          contains('Wi-Fi'),
        ),
      ),
    );
    expect(runner.changes, isEmpty);
  });

  test('reports a refused change with nmcli exit code', () async {
    final runner = sampleRunner(exitCodeForChanges: 4);

    await expectLater(
      configuratorOver(runner).applyProfileToAdapter(dhcpProfile, 'enp3s0'),
      throwsA(
        isA<NetworkConfigurationException>().having(
          (error) => error.exitCode,
          'exitCode',
          4,
        ),
      ),
    );
  });

  test('reports an unknown device', () async {
    await expectLater(
      configuratorOver(sampleRunner())
          .applyProfileToAdapter(dhcpProfile, 'eth9'),
      throwsA(isA<NetworkConfigurationException>()),
    );
  });
}
