import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/contracts/network_profile_repository.dart';
import 'package:network_adapter_tool/core/models/addressing_mode.dart';
import 'package:network_adapter_tool/core/models/network_preset.dart';
import 'package:network_adapter_tool/core/models/network_profile.dart';
import 'package:network_adapter_tool/core/models/network_profile_library.dart';
import 'package:network_adapter_tool/core/models/ping_target.dart';
import 'package:network_adapter_tool/core/profiles/json_network_profile_repository.dart';

void main() {
  late Directory temporaryDirectory;
  late File profilesFile;
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
    profilesFile = File(
      '${temporaryDirectory.path}\\NetworkAdapterTool\\profiles.json',
    );
    repository = JsonNetworkProfileRepository(profilesFile);
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  Future<void> writeProfilesFile(String fileContent) async {
    await profilesFile.parent.create(recursive: true);
    await profilesFile.writeAsString(fileContent);
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

    final remainingFiles = profilesFile.parent.listSync().map(
      (entity) => entity.path,
    );
    expect(remainingFiles, [profilesFile.path]);
  });

  test('writes a versioned, indented JSON document', () async {
    await repository.saveLibrary(
      const NetworkProfileLibrary(profiles: [officeProfile]),
    );

    final fileContent = await profilesFile.readAsString();
    expect(fileContent, contains('\n  "formatVersion": 3'));
    expect(jsonDecode(fileContent), {
      'formatVersion': 3,
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
    await writeProfilesFile(
      '{"formatVersion":1,"profiles":[{"name":"Office","addressingMode":"dhcp"}]}',
    );

    final loadedProfile = (await repository.loadLibrary()).profiles.single;

    expect(loadedProfile.name, 'Office');
    expect(loadedProfile.pingTargets, isEmpty);
  });

  test('loads a format version 2 file without presets', () async {
    await writeProfilesFile(
      '{"formatVersion":2,"profiles":[{"name":"Office","addressingMode":"dhcp"}]}',
    );

    final library = await repository.loadLibrary();

    expect(library.profiles.single.name, 'Office');
    expect(library.presets, isEmpty);
  });

  group('legacy location from before the rename', () {
    late File legacyProfilesFile;
    late JsonNetworkProfileRepository repositoryWithLegacyFile;

    setUp(() async {
      legacyProfilesFile = File(
        '${temporaryDirectory.path}\\NetworkProfileSwitcher\\profiles.json',
      );
      await legacyProfilesFile.parent.create(recursive: true);
      await legacyProfilesFile.writeAsString(
        '{"formatVersion":2,"profiles":[{"name":"Legacy","addressingMode":"dhcp"}]}',
      );
      repositoryWithLegacyFile = JsonNetworkProfileRepository(
        profilesFile,
        legacyProfilesFile: legacyProfilesFile,
      );
    });

    test('is read while the current file does not exist', () async {
      final library = await repositoryWithLegacyFile.loadLibrary();

      expect(library.profiles.single.name, 'Legacy');
    });

    test('is ignored once the current file exists', () async {
      await writeProfilesFile(
        '{"formatVersion":3,"profiles":[{"name":"Current","addressingMode":"dhcp"}]}',
      );

      final library = await repositoryWithLegacyFile.loadLibrary();

      expect(library.profiles.single.name, 'Current');
    });

    test('is kept unchanged when saving to the current location', () async {
      final legacyContent = await legacyProfilesFile.readAsString();
      final library = await repositoryWithLegacyFile.loadLibrary();

      await repositoryWithLegacyFile.saveLibrary(library);

      expect(await profilesFile.exists(), isTrue);
      expect(await legacyProfilesFile.readAsString(), legacyContent);
    });
  });

  group('refuses to load instead of returning an empty library', () {
    Future<void> expectLoadingFails(String fileContent) async {
      await writeProfilesFile(fileContent);

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
      await expectLoadingFails('{"formatVersion":4,"profiles":[]}');
    });
  });
}
