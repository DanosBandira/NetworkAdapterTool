import 'package:flutter_test/flutter_test.dart';
import 'package:network_profile_switcher/core/adapters/netsh_network_adapter_configurator.dart';
import 'package:network_profile_switcher/core/contracts/network_adapter_configurator.dart';
import 'package:network_profile_switcher/core/models/addressing_mode.dart';
import 'package:network_profile_switcher/core/models/network_profile.dart';

import '../../fakes/recording_command_runner.dart';

void main() {
  const adapterName = 'Ethernet 2';

  const dhcpProfile = NetworkProfile(
    name: 'Office',
    addressingMode: AddressingMode.dhcp,
  );

  NetworkProfile staticProfile({
    String? defaultGateway,
    List<String> dnsServers = const [],
  }) {
    return NetworkProfile(
      name: 'Machine',
      addressingMode: AddressingMode.staticIp,
      ipAddress: '192.168.0.10',
      subnetMask: '255.255.255.0',
      defaultGateway: defaultGateway,
      dnsServers: dnsServers,
    );
  }

  group('DHCP profile', () {
    test('switches address and DNS to DHCP', () async {
      final commandRunner = RecordingCommandRunner();

      await NetshNetworkAdapterConfigurator(commandRunner)
          .applyProfileToAdapter(dhcpProfile, adapterName);

      expect(commandRunner.recordedArgumentLists, [
        [
          'interface',
          'ipv4',
          'set',
          'address',
          'name=Ethernet 2',
          'source=dhcp',
        ],
        [
          'interface',
          'ipv4',
          'set',
          'dnsservers',
          'name=Ethernet 2',
          'source=dhcp',
        ],
      ]);
    });

    test('treats "DHCP already enabled" exit code 1 as success', () async {
      final commandRunner = RecordingCommandRunner(exitCodeForEveryCall: 1);

      await NetshNetworkAdapterConfigurator(commandRunner)
          .applyProfileToAdapter(dhcpProfile, adapterName);

      expect(commandRunner.recordedCommands, hasLength(2));
    });

    test('fails on any other non-zero exit code', () async {
      final commandRunner = RecordingCommandRunner(exitCodeForEveryCall: 2);

      final applying = NetshNetworkAdapterConfigurator(commandRunner)
          .applyProfileToAdapter(dhcpProfile, adapterName);

      await expectLater(
        applying,
        throwsA(isA<NetworkConfigurationException>()),
      );
    });
  });

  group('static profile', () {
    test('sets address with gateway and all DNS servers in order', () async {
      final commandRunner = RecordingCommandRunner();
      final profile = staticProfile(
        defaultGateway: '192.168.0.1',
        dnsServers: ['8.8.8.8', '8.8.4.4', '1.1.1.1'],
      );

      await NetshNetworkAdapterConfigurator(commandRunner)
          .applyProfileToAdapter(profile, adapterName);

      expect(commandRunner.recordedArgumentLists, [
        [
          'interface',
          'ipv4',
          'set',
          'address',
          'name=Ethernet 2',
          'source=static',
          'address=192.168.0.10',
          'mask=255.255.255.0',
          'gateway=192.168.0.1',
        ],
        [
          'interface',
          'ipv4',
          'set',
          'dnsservers',
          'name=Ethernet 2',
          'source=static',
          'address=8.8.8.8',
          'register=primary',
          'validate=no',
        ],
        [
          'interface',
          'ipv4',
          'add',
          'dnsservers',
          'name=Ethernet 2',
          'address=8.8.4.4',
          'index=2',
          'validate=no',
        ],
        [
          'interface',
          'ipv4',
          'add',
          'dnsservers',
          'name=Ethernet 2',
          'address=1.1.1.1',
          'index=3',
          'validate=no',
        ],
      ]);
    });

    test('clears gateway and DNS when the profile has none', () async {
      final commandRunner = RecordingCommandRunner();

      await NetshNetworkAdapterConfigurator(commandRunner)
          .applyProfileToAdapter(staticProfile(), adapterName);

      expect(commandRunner.recordedArgumentLists, [
        [
          'interface',
          'ipv4',
          'set',
          'address',
          'name=Ethernet 2',
          'source=static',
          'address=192.168.0.10',
          'mask=255.255.255.0',
          'gateway=none',
        ],
        [
          'interface',
          'ipv4',
          'set',
          'dnsservers',
          'name=Ethernet 2',
          'source=static',
          'address=none',
        ],
      ]);
    });

    test('keeps an adapter name with spaces as a single argument', () async {
      final commandRunner = RecordingCommandRunner();

      await NetshNetworkAdapterConfigurator(commandRunner)
          .applyProfileToAdapter(staticProfile(), 'LAN to machine 3');

      for (final arguments in commandRunner.recordedArgumentLists) {
        expect(arguments, contains('name=LAN to machine 3'));
      }
    });

    test('runs netsh.exe for every command', () async {
      final commandRunner = RecordingCommandRunner();

      await NetshNetworkAdapterConfigurator(commandRunner)
          .applyProfileToAdapter(
            staticProfile(dnsServers: ['8.8.8.8']),
            adapterName,
          );

      expect(
        commandRunner.recordedCommands.map((command) => command.executable),
        everyElement('netsh.exe'),
      );
    });

    test(
      'does not tolerate exit code 1 and stops at the first failure',
      () async {
        final commandRunner = RecordingCommandRunner(exitCodeForEveryCall: 1);

        final applying = NetshNetworkAdapterConfigurator(commandRunner)
            .applyProfileToAdapter(
              staticProfile(dnsServers: ['8.8.8.8']),
              adapterName,
            );

        await expectLater(
          applying,
          throwsA(
            isA<NetworkConfigurationException>()
                .having((error) => error.exitCode, 'exitCode', 1)
                .having(
                  (error) => error.failedCommand,
                  'failedCommand',
                  contains('set address'),
                ),
          ),
        );
        expect(commandRunner.recordedCommands, hasLength(1));
      },
    );
  });
}
