import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/models/ipv4_address.dart';

void main() {
  Ipv4Address address(String text) => Ipv4Address.tryParse(text)!;

  group('tryParse', () {
    test('parses dotted-quad notation', () {
      expect(address('192.168.0.10').toString(), '192.168.0.10');
      expect(address('0.0.0.0').value, 0);
      expect(address('255.255.255.255').value, 0xFFFFFFFF);
    });

    test('ignores surrounding whitespace', () {
      expect(address(' 10.0.0.1 ').toString(), '10.0.0.1');
    });

    for (final invalidText in [
      '',
      '192.168.0',
      '192.168.0.10.1',
      '192.168.0.256',
      '192.168.010.1',
      '192.168.0.-1',
      '192.168.0.a',
      '192.168..1',
      '1921.168.0.1',
    ]) {
      test('rejects "$invalidText"', () {
        expect(Ipv4Address.tryParse(invalidText), isNull);
      });
    }
  });

  group('subnet masks', () {
    test('builds a mask from a prefix length', () {
      expect(
        Ipv4Address.subnetMaskFromPrefixLength(24).toString(),
        '255.255.255.0',
      );
      expect(
        Ipv4Address.subnetMaskFromPrefixLength(20).toString(),
        '255.255.240.0',
      );
      expect(
        Ipv4Address.subnetMaskFromPrefixLength(32).toString(),
        '255.255.255.255',
      );
      expect(Ipv4Address.subnetMaskFromPrefixLength(0).toString(), '0.0.0.0');
    });

    test('rejects a prefix length outside 0..32', () {
      expect(
        () => Ipv4Address.subnetMaskFromPrefixLength(33),
        throwsRangeError,
      );
    });

    test('reports the prefix length of a contiguous mask', () {
      expect(address('255.255.255.0').prefixLengthAsSubnetMask, 24);
      expect(address('255.255.255.252').prefixLengthAsSubnetMask, 30);
      expect(address('255.255.255.255').prefixLengthAsSubnetMask, 32);
      expect(address('0.0.0.0').prefixLengthAsSubnetMask, 0);
    });

    test('reports null for a non-contiguous mask', () {
      expect(address('255.0.255.0').prefixLengthAsSubnetMask, isNull);
      expect(address('255.255.255.1').prefixLengthAsSubnetMask, isNull);
    });
  });

  group('subnet arithmetic', () {
    final subnetMask = address('255.255.255.0');

    test('computes network and broadcast address', () {
      expect(
        address('192.168.0.10').networkAddress(subnetMask),
        address('192.168.0.0'),
      );
      expect(
        address('192.168.0.10').broadcastAddress(subnetMask),
        address('192.168.0.255'),
      );
    });

    test('compares subnets', () {
      expect(
        address('192.168.0.10')
            .isInSameSubnetAs(address('192.168.0.1'), subnetMask),
        isTrue,
      );
      expect(
        address('192.168.0.10')
            .isInSameSubnetAs(address('192.168.1.1'), subnetMask),
        isFalse,
      );
    });
  });

  test('only unicast addresses are assignable to a host', () {
    expect(address('10.0.0.1').isAssignableToHost, isTrue);
    expect(address('223.255.255.254').isAssignableToHost, isTrue);
    expect(address('0.1.2.3').isAssignableToHost, isFalse);
    expect(address('127.0.0.1').isAssignableToHost, isFalse);
    expect(address('224.0.0.1').isAssignableToHost, isFalse);
    expect(address('255.255.255.255').isAssignableToHost, isFalse);
  });
}
