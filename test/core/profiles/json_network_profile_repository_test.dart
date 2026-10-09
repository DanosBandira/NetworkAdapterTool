import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/contracts/network_profile_repository.dart';
import 'package:network_adapter_tool/core/models/addressing_mode.dart';
import 'package:network_adapter_tool/core/models/network_preset.dart';
import 'package:network_adapter_tool/core/models/network_profile.dart';
import 'package:network_adapter_tool/core/models/network_profile_library.dart';
import 'package:network_adapter_tool/core/models/ping_target.dart';
import 'package:network_adapter_tool/core/models/profile_command.dart';
import 'package:network_adapter_tool/core/profiles/json_network_profile_repository.dart';

void main() {
  late Directory temporaryDirectory;
  late File userDataFile;
  late JsonNetworkProfileRepository repository;

  const officeProfile = NetworkProfile(
    name: 'Office',
    addressingMode: AddressingMode.dhcp,
  );
  const machineProfile = NetworkProfile(
    name: 'Machine',
    addressingMode: AddressingMode.staticIp,
    ipAddress: '192.168.0.10',
    subnetMask: '255.255.255.0',
    dnsServers: ['8.8.8.8'],
  );

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('profiles_test');
    // A missing subfolder checks that saving creates it.
    userDataFile = File(
      '${temporaryDirectory.path}\\NetworkAdapterTool\\user_data.json',
    );
    repository = JsonNetworkProfileRepository(userDataFile);
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  Future<void> writeUserDataFile(String fileContent) async {
    await userDataFile.parent.create(recursive: true);
    await userDataFile.writeAsString(fileContent);
  }

  test('loads an empty library when nothing has been saved yet', () async {
    final library = await repository.loadLibrary();

    expect(library.profiles, isEmpty);
    expect(library.presets, isEmpty);
  });

  test('loads the profiles that were saved, in order', () async {
    await repository.saveLibrary(
      const NetworkProfileLibrary(profiles: [officeProfile, machineProfile]),
    );

    final loadedProfiles = (await repository.loadLibrary()).profiles;

    expect(loadedProfiles.map((profile) => profile.name), [
      'Office',
      'Machine',
    ]);
    expect(loadedProfiles[1].ipAddress, '192.168.0.10');
    expect(loadedProfiles[1].dnsServers, ['8.8.8.8']);
  });

  test('replaces previously saved data', () async {
    await repository.saveLibrary(
      const NetworkProfileLibrary(profiles: [officeProfile, machineProfile]),
    );
    await repository.saveLibrary(
      const NetworkProfileLibrary(profiles: [machineProfile]),
    );

    final loadedProfiles = (await repository.loadLibrary()).profiles;

    expect(loadedProfiles.map((profile) => profile.name), ['Machine']);
  });

  test('leaves no temporary file behind', () async {
    await repository.saveLibrary(
      const NetworkProfileLibrary(profiles: [officeProfile]),
    );

    final remainingFiles = userDataFile.parent.listSync().map(
      (entity) => entity.path,
    );
    expect(remainingFiles, [userDataFile.path]);
  });

  test('writes a versioned, indented JSON document', () async {
    await repository.saveLibrary(
      const NetworkProfileLibrary(profiles: [officeProfile]),
    );

    final fileContent = await userDataFile.readAsString();
    expect(fileContent, contains('\n  "formatVersion": 4'));
    expect(jsonDecode(fileContent), {
      'formatVersion': 4,
      'profiles': [
        {'name': 'Office', 'addressingMode': 'dhcp'},
      ],
      'presets': <Object?>[],
    });
  });

  test('stores ping targets with their optional names', () async {
    const profileWithPingTargets = NetworkProfile(
      name: 'Machine',
      addressingMode: AddressingMode.staticIp,
      ipAddress: '10.100.10.4',
      subnetMask: '255.255.255.0',
      pingTargets: [
        PingTarget(ipAddress: '10.100.10.1', name: 'PLC'),
        PingTarget(ipAddress: '10.100.10.2'),
      ],
    );

    await repository.saveLibrary(
      const NetworkProfileLibrary(profiles: [profileWithPingTargets]),
    );
    final loadedProfile = (await repository.loadLibrary()).profiles.single;

    expect(loadedProfile.pingTargets, profileWithPingTargets.pingTargets);
  });

  test('stores commands with their arguments in order', () async {
    const profileWithCommands = NetworkProfile(
      name: 'Machine',
      addressingMode: AddressingMode.dhcp,
      commands: [
        ProfileCommand(
          path: 'map_drive.ps1',
          arguments: ['-Drive', 'Z:', r'\\server\share name'],
          name: 'Map drive',
        ),
        ProfileCommand(path: r'C:\Tools\viewer.exe', runAfterApply: false),
      ],
    );

    await repository.saveLibrary(
      const NetworkProfileLibrary(profiles: [profileWithCommands]),
    );
    final loadedProfile = (await repository.loadLibrary()).profiles.single;

    expect(loadedProfile.commands, profileWithCommands.commands);
  });

  test('loads a format 3 file without commands', () async {
    await writeUserDataFile(
      '{"formatVersion":3,"profiles":[{"name":"Office",'
      '"addressingMode":"dhcp"}],"presets":[]}',
    );

    final loadedProfile = (await repository.loadLibrary()).profiles.single;

    expect(loadedProfile.commands, isEmpty);
  });

  test('stores presets with their assignments in order', () async {
    const linePreset = NetworkPreset(
      name: 'Line 1',
      assignments: [
        PresetAssignment(adapterName: 'Ethernet', profileName: 'Machine'),
        PresetAssignment(adapterName: 'Wi-Fi', profileName: 'Office'),
      ],
    );

    await repository.saveLibrary(
      const NetworkProfileLibrary(
        profiles: [officeProfile, machineProfile],
        presets: [linePreset],
      ),
    );
    final loadedPreset = (await repository.loadLibrary()).presets.single;

    expect(loadedPreset.name, 'Line 1');
    expect(loadedPreset.assignments, linePreset.assignments);
  });

  test('loads a format version 1 file without ping targets', () async {
    await writeUserDataFile(
      '{"formatVersion":1,"profiles":[{"name":"Office","addressingMode":"dhcp"}]}',
    );

    final loadedProfile = (await repository.loadLibrary()).profiles.single;

    expect(loadedProfile.name, 'Office');
    expect(loadedProfile.pingTargets, isEmpty);
  });

  test('loads a format version 2 file without presets', () async {
    await writeUserDataFile(
      '{"formatVersion":2,"profiles":[{"name":"Office","addressingMode":"dhcp"}]}',
    );

    final library = await repository.loadLibrary();

    expect(library.profiles.single.name, 'Office');
    expect(library.presets, isEmpty);
  });

  test('stores helpWasShown only once it is true', () async {
    await repository.saveLibrary(const NetworkProfileLibrary());
    expect(await userDataFile.readAsString(), isNot(contains('helpWasShown')));
    expect((await repository.loadLibrary()).helpWasShown, isFalse);

    await repository.saveLibrary(
      const NetworkProfileLibrary(helpWasShown: true),
    );

    expect(await userDataFile.readAsString(), contains('"helpWasShown": true'));
    expect((await repository.loadLibrary()).helpWasShown, isTrue);
  });

  group('backup', () {
    test('copies the stored file next to it with a timestamp', () async {
      await repository.saveLibrary(
        const NetworkProfileLibrary(profiles: [officeProfile]),
      );

      final backupPath = await repository.backupLibrary();

      expect(backupPath, isNotNull);
      expect(backupPath, matches(r'user_data\.backup-\d{8}-\d{6}\.json$'));
      expect(
        await File(backupPath!).readAsString(),
        await userDataFile.readAsString(),
      );
    });

    test('returns null when nothing was stored yet', () async {
      expect(await repository.backupLibrary(), isNull);
    });
  });

  group('refuses to load instead of returning an empty library', () {
    Future<void> expectLoadingFails(String fileContent) async {
      await writeUserDataFile(fileContent);

      await expectLater(
        repository.loadLibrary(),
        throwsA(isA<NetworkProfileStorageException>()),
      );
    }

    test('when the file is not JSON', () async {
      await expectLoadingFails('{ not json');
    });

    test('when the file has an unexpected structure', () async {
      await expectLoadingFails('[]');
    });

    test('when a profile has an unknown addressing mode', () async {
      await expectLoadingFails(
        '{"formatVersion":1,"profiles":[{"name":"x","addressingMode":"ipv6"}]}',
      );
    });

    test('when a preset is incomplete', () async {
      await expectLoadingFails(
        '{"formatVersion":3,"profiles":[],"presets":[{"name":"x"}]}',
      );
    });

    test('when the file was written by a newer app version', () async {
      await expectLoadingFails('{"formatVersion":5,"profiles":[]}');
    });
  });
}
