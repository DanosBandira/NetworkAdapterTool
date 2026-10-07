import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/core/contracts/network_profile_repository.dart';
import 'package:network_adapter_tool/core/models/addressing_mode.dart';
import 'package:network_adapter_tool/core/models/network_preset.dart';
import 'package:network_adapter_tool/core/models/network_profile.dart';
import 'package:network_adapter_tool/core/models/network_profile_library.dart';
import 'package:network_adapter_tool/core/profiles/json_network_profile_library_transfer.dart';

void main() {
  late Directory temporaryDirectory;
  const transfer = JsonNetworkProfileLibraryTransfer();

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('transfer_test');
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('a saved file loads back with the same profiles and presets', () async {
    const library = NetworkProfileLibrary(
      profiles: [
        NetworkProfile(name: 'Office', addressingMode: AddressingMode.dhcp),
      ],
      presets: [
        NetworkPreset(
          name: 'Morning',
          assignments: [
            PresetAssignment(adapterName: 'Ethernet', profileName: 'Office'),
          ],
        ),
      ],
    );
    final filePath = '${temporaryDirectory.path}\\shared\\line1.json';

    await transfer.exportLibrary(library, filePath);
    final loaded = await transfer.importLibrary(filePath);

    expect(loaded.profiles.single.name, 'Office');
    expect(
      loaded.presets.single.assignments,
      library.presets.single.assignments,
    );
  });

  test(
    'refuses a file that does not exist instead of loading nothing',
    () async {
      await expectLater(
        transfer.importLibrary('${temporaryDirectory.path}\\missing.json'),
        throwsA(isA<NetworkProfileStorageException>()),
      );
    },
  );

  test('refuses a file that is not user data', () async {
    final filePath = '${temporaryDirectory.path}\\other.json';
    await File(filePath).writeAsString('{"something": "else"}');

    await expectLater(
      transfer.importLibrary(filePath),
      throwsA(isA<NetworkProfileStorageException>()),
    );
  });
}
