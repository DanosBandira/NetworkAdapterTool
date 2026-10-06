import '../models/addressing_mode.dart';
import '../models/ipv4_address.dart';
import '../models/network_profile.dart';

/// The profile input a validation error belongs to, so the editor can show
/// the message next to the right field.
enum NetworkProfileField {
  name,
  ipAddress,
  subnetMask,
  defaultGateway,
  dnsServers,
}

class NetworkProfileValidationError {
  const NetworkProfileValidationError(this.field, this.message);

  final NetworkProfileField field;
  final String message;

  @override
  String toString() => '${field.name}: $message';
}

/// Checks that a profile is complete and consistent before it is saved or
/// applied: valid IPv4 addresses, a contiguous subnet mask, a gateway inside
/// the subnet and valid DNS servers.
///
/// DHCP profiles only need a name; their address fields are ignored because
/// the configurator never uses them.
class NetworkProfileValidator {
  const NetworkProfileValidator();

  // Below /31 a subnet reserves its first and last address (RFC 3021 makes
  // /31 point-to-point links the exception).
  static const _longestPrefixWithNetworkAndBroadcast = 30;

  /// Returns all problems at once, so the editor can mark every field.
  ///
  /// [otherProfileNames] are the names of the other saved profiles; the name
  /// must not collide with one of them.
  List<NetworkProfileValidationError> validate(
    NetworkProfile profile, {
    Iterable<String> otherProfileNames = const [],
  }) {
    return [
      ..._validateName(profile.name, otherProfileNames),
      if (profile.addressingMode == AddressingMode.staticIp)
        ..._validateStaticSettings(profile),
    ];
  }

  Iterable<NetworkProfileValidationError> _validateName(
    String name,
    Iterable<String> otherProfileNames,
  ) sync* {
    if (_isBlank(name)) {
      yield const NetworkProfileValidationError(
        NetworkProfileField.name,
        'Enter a profile name.',
      );
    } else if (otherProfileNames.any((other) => _isSameName(other, name))) {
      yield const NetworkProfileValidationError(
        NetworkProfileField.name,
        'A profile with this name already exists.',
      );
    }
  }

  Iterable<NetworkProfileValidationError> _validateStaticSettings(
    NetworkProfile profile,
  ) sync* {
    final ipAddress = _tryParse(profile.ipAddress);
    final subnetMask = _tryParse(profile.subnetMask);
    final defaultGateway = _tryParse(profile.defaultGateway);

    yield* _validateIpAddressFormat(profile.ipAddress, ipAddress);
    yield* _validateSubnetMaskFormat(profile.subnetMask, subnetMask);
    yield* _validateDefaultGatewayFormat(
      profile.defaultGateway,
      defaultGateway,
    );

    if (_isHostAddress(ipAddress) && _isSubnetMask(subnetMask)) {
      yield* _validateIpAddressWithinSubnet(ipAddress!, subnetMask!);
      if (_isHostAddress(defaultGateway)) {
        yield* _validateDefaultGatewayWithinSubnet(
          defaultGateway!,
          ipAddress,
          subnetMask,
        );
      }
    }

    yield* _validateDnsServers(profile.dnsServers);
  }

  Iterable<NetworkProfileValidationError> _validateIpAddressFormat(
    String? text,
    Ipv4Address? ipAddress,
  ) sync* {
    if (_isBlank(text)) {
      yield const NetworkProfileValidationError(
        NetworkProfileField.ipAddress,
        'Enter an IP address.',
      );
    } else if (ipAddress == null) {
      yield const NetworkProfileValidationError(
        NetworkProfileField.ipAddress,
        'Enter a valid IPv4 address, e.g. 192.168.0.10.',
      );
    } else if (!ipAddress.isAssignableToHost) {
      yield const NetworkProfileValidationError(
        NetworkProfileField.ipAddress,
        'This address cannot be assigned to an adapter.',
      );
    }
  }

  Iterable<NetworkProfileValidationError> _validateSubnetMaskFormat(
    String? text,
    Ipv4Address? subnetMask,
  ) sync* {
    if (_isBlank(text)) {
      yield const NetworkProfileValidationError(
        NetworkProfileField.subnetMask,
        'Enter a subnet mask.',
      );
    } else if (!_isSubnetMask(subnetMask)) {
      yield const NetworkProfileValidationError(
        NetworkProfileField.subnetMask,
        'Enter a valid subnet mask, e.g. 255.255.255.0.',
      );
    }
  }

  Iterable<NetworkProfileValidationError> _validateDefaultGatewayFormat(
    String? text,
    Ipv4Address? defaultGateway,
  ) sync* {
    if (_isBlank(text)) return;
    if (!_isHostAddress(defaultGateway)) {
      yield const NetworkProfileValidationError(
        NetworkProfileField.defaultGateway,
        'Enter a valid IPv4 address, or leave the gateway empty.',
      );
    }
  }

  Iterable<NetworkProfileValidationError> _validateIpAddressWithinSubnet(
    Ipv4Address ipAddress,
    Ipv4Address subnetMask,
  ) sync* {
    if (_isNetworkOrBroadcastAddress(ipAddress, subnetMask)) {
      yield const NetworkProfileValidationError(
        NetworkProfileField.ipAddress,
        'This is the network or broadcast address of the subnet; '
        'choose a host address.',
      );
    }
  }

  Iterable<NetworkProfileValidationError> _validateDefaultGatewayWithinSubnet(
    Ipv4Address defaultGateway,
    Ipv4Address ipAddress,
    Ipv4Address subnetMask,
  ) sync* {
    if (!defaultGateway.isInSameSubnetAs(ipAddress, subnetMask)) {
      yield const NetworkProfileValidationError(
        NetworkProfileField.defaultGateway,
        'The gateway must be in the same subnet as the IP address.',
      );
    } else if (defaultGateway == ipAddress) {
      yield const NetworkProfileValidationError(
        NetworkProfileField.defaultGateway,
        "The gateway cannot be the adapter's own IP address.",
      );
    } else if (_isNetworkOrBroadcastAddress(defaultGateway, subnetMask)) {
      yield const NetworkProfileValidationError(
        NetworkProfileField.defaultGateway,
        'The gateway cannot be the network or broadcast address.',
      );
    }
  }

  Iterable<NetworkProfileValidationError> _validateDnsServers(
    List<String> dnsServers,
  ) sync* {
    final seenDnsServers = <Ipv4Address>{};
    for (final text in dnsServers) {
      final dnsServer = _tryParse(text);
      if (!_isHostAddress(dnsServer)) {
        yield NetworkProfileValidationError(
          NetworkProfileField.dnsServers,
          'DNS server "$text" is not a valid IPv4 address.',
        );
      } else if (!seenDnsServers.add(dnsServer!)) {
        yield NetworkProfileValidationError(
          NetworkProfileField.dnsServers,
          'DNS server "$text" is listed more than once.',
        );
      }
    }
  }

  bool _isNetworkOrBroadcastAddress(
    Ipv4Address address,
    Ipv4Address subnetMask,
  ) {
    if (subnetMask.prefixLengthAsSubnetMask! >
        _longestPrefixWithNetworkAndBroadcast) {
      return false;
    }
    return address == address.networkAddress(subnetMask) ||
        address == address.broadcastAddress(subnetMask);
  }

  Ipv4Address? _tryParse(String? text) =>
      text == null ? null : Ipv4Address.tryParse(text);

  bool _isHostAddress(Ipv4Address? address) =>
      address != null && address.isAssignableToHost;

  // A /0 mask is technically contiguous but would put every address on the
  // local link, which is never a meaningful adapter setting.
  bool _isSubnetMask(Ipv4Address? subnetMask) {
    final prefixLength = subnetMask?.prefixLengthAsSubnetMask;
    return prefixLength != null && prefixLength > 0;
  }

  bool _isBlank(String? text) => text == null || text.trim().isEmpty;

  bool _isSameName(String first, String second) =>
      first.trim().toLowerCase() == second.trim().toLowerCase();
}
