import 'package:flutter_test/flutter_test.dart';
import 'package:network_profile_switcher/core/models/addressing_mode.dart';
import 'package:network_profile_switcher/core/models/network_profile.dart';
import 'package:network_profile_switcher/core/models/ping_target.dart';
import 'package:network_profile_switcher/core/profiles/network_profile_validator.dart';

void main() {
  const validator = NetworkProfileValidator();

  NetworkProfile staticProfile({
    String name = 'Machine',
    String? ipAddress = '192.168.0.10',
    String? subnetMask = '255.255.255.0',
    String? defaultGateway,
    List<String> dnsServers = const [],
  }) {
    return NetworkProfile(
      name: name,
      addressingMode: AddressingMode.staticIp,
      ipAddress: ipAddress,
      subnetMask: subnetMask,
      defaultGateway: defaultGateway,
      dnsServers: dnsServers,
    );
  }

  List<NetworkProfileField> fieldsWithErrors(
    NetworkProfile profile, {
    Iterable<String> otherProfileNames = const [],
  }) {
    return [
      for (final error in validator.validate(
        profile,
        otherProfileNames: otherProfileNames,
      ))
        error.field,
    ];
  }

  group('valid profiles', () {
    test('accepts a DHCP profile with only a name', () {
      const profile = NetworkProfile(
        name: 'Office',
        addressingMode: AddressingMode.dhcp,
      );

      expect(validator.validate(profile), isEmpty);
    });

    test('ignores address fields of a DHCP profile', () {
      const profile = NetworkProfile(
        name: 'Office',
        addressingMode: AddressingMode.dhcp,
        ipAddress: 'left over from editing',
      );

      expect(validator.validate(profile), isEmpty);
    });

    test('accepts a static profile without gateway or DNS', () {
      expect(validator.validate(staticProfile()), isEmpty);
    });

    test('accepts a complete static profile', () {
      final profile = staticProfile(
        defaultGateway: '192.168.0.1',
        dnsServers: ['8.8.8.8', '1.1.1.1'],
      );

      expect(validator.validate(profile), isEmpty);
    });

    test('accepts both addresses of a /31 point-to-point link', () {
      final profile = staticProfile(
        ipAddress: '10.0.0.0',
        subnetMask: '255.255.255.254',
        defaultGateway: '10.0.0.1',
      );

      expect(validator.validate(profile), isEmpty);
    });
  });

  group('name', () {
    test('is required', () {
      expect(fieldsWithErrors(staticProfile(name: '  ')), [
        NetworkProfileField.name,
      ]);
    });

    test('must differ from other profiles, ignoring case', () {
      expect(
        fieldsWithErrors(
          staticProfile(name: 'machine'),
          otherProfileNames: ['Office', 'Machine'],
        ),
        [NetworkProfileField.name],
      );
    });
  });

  group('IP address', () {
    test('is required for a static profile', () {
      expect(fieldsWithErrors(staticProfile(ipAddress: null)), [
        NetworkProfileField.ipAddress,
      ]);
      expect(fieldsWithErrors(staticProfile(ipAddress: '')), [
        NetworkProfileField.ipAddress,
      ]);
    });

    for (final invalidAddress in [
      '192.168.0',
      '192.168.0.300',
      '192.168.0.010',
    ]) {
      test('rejects malformed "$invalidAddress"', () {
        expect(fieldsWithErrors(staticProfile(ipAddress: invalidAddress)), [
          NetworkProfileField.ipAddress,
        ]);
      });
    }

    for (final unassignableAddress in ['127.0.0.1', '224.0.0.5', '0.0.0.0']) {
      test('rejects unassignable "$unassignableAddress"', () {
        expect(
          fieldsWithErrors(staticProfile(ipAddress: unassignableAddress)),
          [NetworkProfileField.ipAddress],
        );
      });
    }

    test('rejects the network address of the subnet', () {
      expect(fieldsWithErrors(staticProfile(ipAddress: '192.168.0.0')), [
        NetworkProfileField.ipAddress,
      ]);
    });

    test('rejects the broadcast address of the subnet', () {
      expect(fieldsWithErrors(staticProfile(ipAddress: '192.168.0.255')), [
        NetworkProfileField.ipAddress,
      ]);
    });
  });

  group('subnet mask', () {
    test('is required for a static profile', () {
      expect(fieldsWithErrors(staticProfile(subnetMask: null)), [
        NetworkProfileField.subnetMask,
      ]);
    });

    for (final invalidMask in [
      '255.0.255.0',
      '255.255.255.1',
      '0.0.0.0',
      'abc',
    ]) {
      test('rejects "$invalidMask"', () {
        expect(fieldsWithErrors(staticProfile(subnetMask: invalidMask)), [
          NetworkProfileField.subnetMask,
        ]);
      });
    }
  });

  group('default gateway', () {
    test('treats an empty gateway as not set', () {
      expect(validator.validate(staticProfile(defaultGateway: '')), isEmpty);
    });

    test('rejects a malformed gateway', () {
      expect(fieldsWithErrors(staticProfile(defaultGateway: '192.168.0')), [
        NetworkProfileField.defaultGateway,
      ]);
    });

    test('must be in the same subnet as the IP address', () {
      expect(fieldsWithErrors(staticProfile(defaultGateway: '192.168.1.1')), [
        NetworkProfileField.defaultGateway,
      ]);
    });

    test('may not equal the IP address', () {
      expect(fieldsWithErrors(staticProfile(defaultGateway: '192.168.0.10')), [
        NetworkProfileField.defaultGateway,
      ]);
    });

    test('may not be the broadcast address', () {
      expect(fieldsWithErrors(staticProfile(defaultGateway: '192.168.0.255')), [
        NetworkProfileField.defaultGateway,
      ]);
    });

    test('is not compared to the subnet when the IP address is invalid', () {
      expect(
        fieldsWithErrors(
          staticProfile(ipAddress: 'x', defaultGateway: '10.0.0.1'),
        ),
        [NetworkProfileField.ipAddress],
      );
    });
  });

  group('DNS servers', () {
    test('rejects an invalid entry and names it in the message', () {
      final errors = validator.validate(
        staticProfile(dnsServers: ['8.8.8.8', '8.8.8']),
      );

      expect(errors.single.field, NetworkProfileField.dnsServers);
      expect(errors.single.message, contains('"8.8.8"'));
    });

    test('rejects a duplicate entry', () {
      expect(
        fieldsWithErrors(staticProfile(dnsServers: ['8.8.8.8', '8.8.8.8'])),
        [NetworkProfileField.dnsServers],
      );
    });
  });

  group('ping targets', () {
    NetworkProfile dhcpProfileWithTargets(List<PingTarget> pingTargets) {
      return NetworkProfile(
        name: 'Line 1',
        addressingMode: AddressingMode.dhcp,
        pingTargets: pingTargets,
      );
    }

    test('accepts valid targets, also on a DHCP profile', () {
      final profile = dhcpProfileWithTargets(const [
        PingTarget(ipAddress: '10.100.10.1', name: 'PLC'),
        PingTarget(ipAddress: '10.100.10.2'),
      ]);

      expect(validator.validate(profile), isEmpty);
    });

    test('rejects an invalid address and names it in the message', () {
      final errors = validator.validate(
        dhcpProfileWithTargets(const [PingTarget(ipAddress: '10.100.10')]),
      );

      expect(errors.single.field, NetworkProfileField.pingTargets);
      expect(errors.single.message, contains('"10.100.10"'));
    });

    test('rejects a target with only a name', () {
      final errors = validator.validate(
        dhcpProfileWithTargets(const [PingTarget(ipAddress: '', name: 'PLC')]),
      );

      expect(errors.single.message, contains('"PLC" needs an IP address'));
    });

    test('rejects the same address twice', () {
      expect(
        fieldsWithErrors(
          dhcpProfileWithTargets(const [
            PingTarget(ipAddress: '10.100.10.1', name: 'PLC'),
            PingTarget(ipAddress: '10.100.10.1', name: 'HMI'),
          ]),
        ),
        [NetworkProfileField.pingTargets],
      );
    });
  });

  test('reports problems in several fields at once', () {
    final profile = staticProfile(
      name: '',
      ipAddress: '',
      subnetMask: '',
      defaultGateway: 'x',
      dnsServers: ['y'],
    );

    expect(fieldsWithErrors(profile), [
      NetworkProfileField.name,
      NetworkProfileField.ipAddress,
      NetworkProfileField.subnetMask,
      NetworkProfileField.defaultGateway,
      NetworkProfileField.dnsServers,
    ]);
  });
}
