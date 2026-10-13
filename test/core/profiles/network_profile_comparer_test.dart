import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/models/addressing_mode.dart';
import 'package:network_adapter_tool/core/models/network_adapter.dart';
import 'package:network_adapter_tool/core/models/network_profile.dart';
import 'package:network_adapter_tool/core/profiles/network_profile_comparer.dart';

void main() {
  const comparer = NetworkProfileComparer();
  const staticProfile = NetworkProfile(
    name: 'Machine',
    addressingMode: AddressingMode.staticIp,
    ipAddress: '10.100.10.4',
    subnetMask: '255.255.255.0',
    defaultGateway: '',
    dnsServers: ['10.100.10.1', '8.8.8.8'],
  );

  NetworkAdapter adapter({
    AddressingMode addressingMode = AddressingMode.staticIp,
    String ipAddress = '10.100.10.4',
    List<String> dnsServers = const ['10.100.10.1', '8.8.8.8'],
  }) {
    return NetworkAdapter(
      name: 'Ethernet',
      description: 'Intel(R) Ethernet',
      status: NetworkAdapterStatus.connected,
      addressingMode: addressingMode,
      ipAddress: ipAddress,
      subnetMask: '255.255.255.0',
      dnsServers: dnsServers,
    );
  }

  test('a static profile is active when every setting matches', () {
    expect(comparer.isActiveOn(staticProfile, adapter()), isTrue);
  });

  test('a blank gateway matches an adapter without gateway', () {
    expect(comparer.findMismatches(staticProfile, adapter()), isEmpty);
  });

  test('another IP address or DNS order is a mismatch', () {
    expect(
      comparer.isActiveOn(staticProfile, adapter(ipAddress: '10.100.10.5')),
      isFalse,
    );
    expect(
      comparer
          .findMismatches(
            staticProfile,
            adapter(dnsServers: ['8.8.8.8', '10.100.10.1']),
          )
          .single
          .setting,
      AdapterSetting.dnsServers,
    );
  });

  test('a DHCP profile matches on the addressing mode only', () {
    const dhcpProfile = NetworkProfile(
      name: 'Office',
      addressingMode: AddressingMode.dhcp,
    );

    expect(
      comparer.isActiveOn(
        dhcpProfile,
        adapter(addressingMode: AddressingMode.dhcp),
      ),
      isTrue,
    );
    expect(comparer.isActiveOn(dhcpProfile, adapter()), isFalse);
  });
}
