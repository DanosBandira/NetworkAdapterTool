import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:network_profile_switcher/core/contracts/network_profile_repository.dart';
import 'package:network_profile_switcher/core/models/addressing_mode.dart';
import 'package:network_profile_switcher/core/models/network_profile.dart';
import 'package:network_profile_switcher/core/profiles/json_network_profile_repository.dart';

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
      '${temporaryDirectory.path}\\NetworkProfileSwitcher\\profiles.json',
    );
    repository = JsonNetworkProfileRepository(profilesFile);
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('loads an empty list when nothing has been saved yet', () async {
    expect(await repository.loadAllProfiles(), isEmpty);
  });

  test('loads the profiles that were saved, in order', () async {
    await repository.saveAllProfiles([officeProfile, machineProfile]);

    final loadedProfiles = await repository.loadAllProfiles();

    expect(loadedProfiles.map((profile) => profile.name), [
      'Office',
      'Machine',
    ]);
    expect(loadedProfiles[1].ipAddress, '192.168.0.10');
    expect(loadedProfiles[1].dnsServers, ['8.8.8.8']);
  });

  test('replaces previously saved profiles', () async {
    await repository.saveAllProfiles([officeProfile, machineProfile]);
    await repository.saveAllProfiles([machineProfile]);

    final loadedProfiles = await repository.loadAllProfiles();

    expect(loadedProfiles.map((profile) => profile.name), ['Machine']);
  });

  test('leaves no temporary file behind', () async {
    await repository.saveAllProfiles([officeProfile]);

    final remainingFiles = profilesFile.parent.listSync().map(
      (entity) => entity.path,
    );
    expect(remainingFiles, [profilesFile.path]);
  });

  test('writes a versioned, indented JSON document', () async {
    await repository.saveAllProfiles([officeProfile]);

    final fileContent = await profilesFile.readAsString();
    expect(fileContent, contains('\n  "formatVersion": 1'));
    expect(jsonDecode(fileContent), {
      'formatVersion': 1,
      'profiles': [
        {'name': 'Office', 'addressingMode': 'dhcp'},
      ],
    });
  });

  group('refuses to load instead of returning an empty list', () {
    Future<void> expectLoadingFails(String fileContent) async {
      await profilesFile.parent.create(recursive: true);
      await profilesFile.writeAsString(fileContent);

      await expectLater(
        repository.loadAllProfiles(),
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

    test('when the file was written by a newer app version', () async {
      await expectLoadingFails('{"formatVersion":2,"profiles":[]}');
    });
  });
}
