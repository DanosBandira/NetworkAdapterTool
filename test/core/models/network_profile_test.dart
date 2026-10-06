import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/models/addressing_mode.dart';
import 'package:network_adapter_tool/core/models/network_profile.dart';
import 'package:network_adapter_tool/core/models/ping_target.dart';

void main() {
  test('static profile survives a JSON round trip', () {
    const original = NetworkProfile(
      name: 'Machine direct',
      addressingMode: AddressingMode.staticIp,
      ipAddress: '192.168.0.10',
      subnetMask: '255.255.255.0',
      defaultGateway: '192.168.0.1',
      dnsServers: ['8.8.8.8', '1.1.1.1'],
    );

    final restored = NetworkProfile.fromJson(original.toJson());

    expect(restored.name, original.name);
    expect(restored.addressingMode, AddressingMode.staticIp);
    expect(restored.ipAddress, original.ipAddress);
    expect(restored.subnetMask, original.subnetMask);
    expect(restored.defaultGateway, original.defaultGateway);
    expect(restored.dnsServers, original.dnsServers);
  });

  test('ping targets survive a JSON round trip', () {
    const original = NetworkProfile(
      name: 'Line 1',
      addressingMode: AddressingMode.dhcp,
      pingTargets: [
        PingTarget(ipAddress: '10.100.10.1', name: 'PLC'),
        PingTarget(ipAddress: '10.100.10.2'),
      ],
    );

    final restored = NetworkProfile.fromJson(original.toJson());

    expect(restored.pingTargets, original.pingTargets);
    expect(restored.pingTargets[1].displayName, '10.100.10.2');
  });

  test('optional settings are omitted from JSON when not set', () {
    const dhcpProfile = NetworkProfile(
      name: 'Office',
      addressingMode: AddressingMode.dhcp,
    );

    expect(dhcpProfile.toJson(), {'name': 'Office', 'addressingMode': 'dhcp'});
  });

  test('missing optional settings are read as empty', () {
    final profile = NetworkProfile.fromJson({
      'name': 'Office',
      'addressingMode': 'dhcp',
    });

    expect(profile.ipAddress, isNull);
    expect(profile.dnsServers, isEmpty);
  });
}
