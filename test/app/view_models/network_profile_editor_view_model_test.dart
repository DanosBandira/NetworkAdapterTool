import 'package:flutter_test/flutter_test.dart';
import 'package:network_profile_switcher/app/view_models/network_profile_editor_view_model.dart';
import 'package:network_profile_switcher/core/models/addressing_mode.dart';
import 'package:network_profile_switcher/core/models/network_profile.dart';
import 'package:network_profile_switcher/core/profiles/network_profile_validator.dart';

void main() {
  NetworkProfileEditorViewModel newProfileEditor({
    List<String> otherProfileNames = const [],
  }) {
    return NetworkProfileEditorViewModel(
      originalProfile: null,
      otherProfileNames: otherProfileNames,
    );
  }

  test('starts a new profile as static with a /24 mask', () {
    final editor = newProfileEditor();

    expect(editor.isNewProfile, isTrue);
    expect(editor.addressingMode, AddressingMode.staticIp);
    expect(editor.subnetMask, '255.255.255.0');
  });

  test('shows no errors before the user edits or saves', () {
    final editor = newProfileEditor();

    for (final field in NetworkProfileField.values) {
      expect(editor.errorFor(field), isNull);
    }
  });

  test('shows the error of a field once it was edited', () {
    final editor = newProfileEditor()..updateIpAddress('192.168.0');

    expect(editor.errorFor(NetworkProfileField.ipAddress), isNotNull);
    expect(editor.errorFor(NetworkProfileField.name), isNull);
  });

  test('reveals all errors when saving invalid input', () {
    final editor = newProfileEditor();

    final savedProfile = editor.trySave();

    expect(savedProfile, isNull);
    expect(editor.errorFor(NetworkProfileField.name), isNotNull);
    expect(editor.errorFor(NetworkProfileField.ipAddress), isNotNull);
  });

  test('rejects a name used by another profile', () {
    final editor = newProfileEditor(otherProfileNames: ['Office'])
      ..updateName('office');

    expect(editor.errorFor(NetworkProfileField.name), isNotNull);
  });

  test('builds a trimmed static profile and skips empty DNS fields', () {
    final editor = newProfileEditor()
      ..updateName(' Machine ')
      ..updateIpAddress(' 192.168.0.10')
      ..updateDefaultGateway('')
      ..updatePreferredDnsServer('')
      ..updateAlternateDnsServer('8.8.8.8');

    final savedProfile = editor.trySave()!;

    expect(savedProfile.name, 'Machine');
    expect(savedProfile.ipAddress, '192.168.0.10');
    expect(savedProfile.defaultGateway, isNull);
    expect(savedProfile.dnsServers, ['8.8.8.8']);
  });

  test('drops address fields when switched to DHCP', () {
    final editor = newProfileEditor()
      ..updateName('Office')
      ..updateIpAddress('not even valid')
      ..updateAddressingMode(AddressingMode.dhcp);

    final savedProfile = editor.trySave()!;

    expect(savedProfile.addressingMode, AddressingMode.dhcp);
    expect(savedProfile.ipAddress, isNull);
    expect(savedProfile.dnsServers, isEmpty);
  });

  test('keeps DNS servers beyond the two form fields', () {
    final editor = NetworkProfileEditorViewModel(
      originalProfile: const NetworkProfile(
        name: 'Lab',
        addressingMode: AddressingMode.staticIp,
        ipAddress: '10.0.0.5',
        subnetMask: '255.255.255.0',
        dnsServers: ['10.0.0.1', '10.0.0.2', '10.0.0.3'],
      ),
      otherProfileNames: const [],
    );

    expect(editor.isNewProfile, isFalse);
    expect(editor.preferredDnsServer, '10.0.0.1');
    expect(editor.alternateDnsServer, '10.0.0.2');

    editor.updateAlternateDnsServer('10.0.0.9');

    expect(editor.trySave()!.dnsServers, ['10.0.0.1', '10.0.0.9', '10.0.0.3']);
  });
}
