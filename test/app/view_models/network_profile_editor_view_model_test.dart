import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/app/view_models/network_profile_editor_view_model.dart';
import 'package:network_adapter_tool/core/models/addressing_mode.dart';
import 'package:network_adapter_tool/core/models/network_profile.dart';
import 'package:network_adapter_tool/core/models/ping_target.dart';
import 'package:network_adapter_tool/core/models/profile_command.dart';
import 'package:network_adapter_tool/core/profiles/network_profile_validator.dart';

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

  group('ping targets', () {
    NetworkProfileEditorViewModel validDhcpEditor() {
      return newProfileEditor()
        ..updateName('Line 1')
        ..updateAddressingMode(AddressingMode.dhcp);
    }

    test('adds, edits and removes ping target rows', () {
      final editor = validDhcpEditor()
        ..addPingTarget()
        ..addPingTarget();
      final [plcRow, hmiRow] = editor.pingTargetDrafts;
      editor
        ..updatePingTargetName(plcRow.id, 'PLC')
        ..updatePingTargetIpAddress(plcRow.id, ' 10.100.10.1 ')
        ..updatePingTargetIpAddress(hmiRow.id, '10.100.10.2')
        ..removePingTarget(hmiRow.id);

      final savedProfile = editor.trySave()!;

      expect(savedProfile.pingTargets, [
        const PingTarget(ipAddress: '10.100.10.1', name: 'PLC'),
      ]);
    });

    test('skips rows that were added but left empty', () {
      final editor = validDhcpEditor()..addPingTarget();

      expect(editor.trySave()!.pingTargets, isEmpty);
    });

    test('shows an error for an invalid ping target address', () {
      final editor = validDhcpEditor()..addPingTarget();
      editor.updatePingTargetIpAddress(
        editor.pingTargetDrafts.single.id,
        '10.100',
      );

      expect(editor.errorFor(NetworkProfileField.pingTargets), isNotNull);
      expect(editor.trySave(), isNull);
    });

    test('loads the ping targets of an existing profile', () {
      final editor = NetworkProfileEditorViewModel(
        originalProfile: const NetworkProfile(
          name: 'Line 1',
          addressingMode: AddressingMode.dhcp,
          pingTargets: [PingTarget(ipAddress: '10.100.10.1', name: 'PLC')],
        ),
        otherProfileNames: const [],
      );

      final draft = editor.pingTargetDrafts.single;
      expect(draft.name, 'PLC');
      expect(draft.ipAddress, '10.100.10.1');
    });
  });

  group('commands', () {
    NetworkProfileEditorViewModel validDhcpEditor() {
      return newProfileEditor()
        ..updateName('Line 1')
        ..updateAddressingMode(AddressingMode.dhcp);
    }

    test('builds commands from arguments typed as a command line', () {
      final editor = validDhcpEditor()
        ..addCommand()
        ..addCommand();
      final [mapRow, viewerRow] = editor.commandDrafts;
      editor
        ..updateCommandName(mapRow.id, 'Map drive')
        ..updateCommandPath(mapRow.id, ' map_drive.ps1 ')
        ..updateCommandArguments(mapRow.id, ' -Drive Z:  "two words" ')
        ..updateCommandPath(viewerRow.id, 'viewer.exe')
        ..updateCommandRunAfterApply(viewerRow.id, false);

      final savedProfile = editor.trySave()!;

      expect(savedProfile.commands, [
        const ProfileCommand(
          path: 'map_drive.ps1',
          arguments: ['-Drive', 'Z:', 'two words'],
          name: 'Map drive',
        ),
        const ProfileCommand(path: 'viewer.exe', runAfterApply: false),
      ]);
    });

    test('runs a new command after applying by default', () {
      final editor = validDhcpEditor()..addCommand();

      expect(editor.commandDrafts.single.runAfterApply, isTrue);
    });

    test('skips rows that were added but left empty', () {
      final editor = validDhcpEditor()
        ..addCommand()
        ..addCommand();
      editor.removeCommand(editor.commandDrafts.first.id);

      expect(editor.trySave()!.commands, isEmpty);
    });

    test('shows an error for a file type that cannot run', () {
      final editor = validDhcpEditor()..addCommand();
      editor.updateCommandPath(editor.commandDrafts.single.id, 'notes.txt');

      expect(editor.errorFor(NetworkProfileField.commands), isNotNull);
      expect(editor.trySave(), isNull);
    });

    test('loads the commands of an existing profile', () {
      final editor = NetworkProfileEditorViewModel(
        originalProfile: const NetworkProfile(
          name: 'Line 1',
          addressingMode: AddressingMode.dhcp,
          commands: [
            ProfileCommand(
              path: 'map_drive.ps1',
              arguments: ['-Drive', 'Z:'],
              runAfterApply: false,
            ),
          ],
        ),
        otherProfileNames: const [],
      );

      final draft = editor.commandDrafts.single;
      expect(draft.path, 'map_drive.ps1');
      expect(draft.argumentsText, '-Drive Z:');
      expect(draft.runAfterApply, isFalse);
    });
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
