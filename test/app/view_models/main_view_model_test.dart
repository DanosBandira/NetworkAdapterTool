import 'package:flutter_test/flutter_test.dart';
import 'package:network_profile_switcher/app/view_models/main_view_model.dart';
import 'package:network_profile_switcher/core/contracts/network_adapter_configurator.dart';
import 'package:network_profile_switcher/core/contracts/network_adapter_reader.dart';
import 'package:network_profile_switcher/core/contracts/network_profile_repository.dart';
import 'package:network_profile_switcher/core/models/addressing_mode.dart';
import 'package:network_profile_switcher/core/models/network_adapter.dart';
import 'package:network_profile_switcher/core/models/network_profile.dart';
import 'package:network_profile_switcher/core/network_profile_applier.dart';
import 'package:network_profile_switcher/core/profiles/network_profile_validator.dart';

import '../../fakes/fake_network_adapter_reader.dart';
import '../../fakes/in_memory_network_profile_repository.dart';
import '../../fakes/recording_network_adapter_configurator.dart';

void main() {
  const machineProfile = NetworkProfile(
    name: 'Machine',
    addressingMode: AddressingMode.staticIp,
    ipAddress: '192.168.0.10',
    subnetMask: '255.255.255.0',
  );
  const officeProfile = NetworkProfile(
    name: 'Office',
    addressingMode: AddressingMode.dhcp,
  );

  NetworkAdapter ethernet({
    AddressingMode addressingMode = AddressingMode.dhcp,
    String? ipAddress = '169.254.1.1',
    String? subnetMask = '255.255.0.0',
  }) {
    return NetworkAdapter(
      name: 'Ethernet',
      description: 'Intel(R) Ethernet',
      status: NetworkAdapterStatus.connected,
      addressingMode: addressingMode,
      ipAddress: ipAddress,
      subnetMask: subnetMask,
    );
  }

  late RecordingNetworkAdapterConfigurator configurator;
  late InMemoryNetworkProfileRepository repository;

  setUp(() {
    configurator = RecordingNetworkAdapterConfigurator();
    repository = InMemoryNetworkProfileRepository(
      storedProfiles: [machineProfile, officeProfile],
    );
  });

  MainViewModel createViewModel(NetworkAdapterReader reader) {
    return MainViewModel(
      reader: reader,
      repository: repository,
      applier: NetworkProfileApplier(
        validator: const NetworkProfileValidator(),
        configurator: configurator,
        reader: reader,
        verificationAttempts: 1,
      ),
    );
  }

  Future<MainViewModel> initializedViewModel(
    NetworkAdapterReader reader,
  ) async {
    final viewModel = createViewModel(reader);
    await viewModel.initialize();
    return viewModel;
  }

  group('initialize', () {
    test('loads adapters and profiles', () async {
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );

      expect(viewModel.adapters.single.name, 'Ethernet');
      expect(viewModel.profiles.map((profile) => profile.name), [
        'Machine',
        'Office',
      ]);
      expect(viewModel.isLoadingAdapters, isFalse);
      expect(viewModel.canEditProfiles, isTrue);
    });

    test('shows an error when adapters cannot be read', () async {
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader(
          [],
          readError: const NetworkAdapterReadException('access denied'),
        ),
      );

      expect(viewModel.statusMessage?.kind, StatusKind.error);
      expect(viewModel.statusMessage?.text, contains('access denied'));
    });

    test('blocks profile editing when profiles cannot be loaded', () async {
      repository = InMemoryNetworkProfileRepository(
        loadError: const NetworkProfileStorageException('corrupt file'),
      );

      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );

      expect(viewModel.canEditProfiles, isFalse);
      expect(viewModel.statusMessage?.text, contains('corrupt file'));
    });
  });

  group('applying', () {
    test('needs a selected adapter and profile', () async {
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );

      expect(viewModel.canApplySelectedProfile, isFalse);
      viewModel.selectAdapter('Ethernet');
      expect(viewModel.canApplySelectedProfile, isFalse);
      expect(viewModel.canSwitchSelectedAdapterToDhcp, isTrue);
      viewModel.selectProfile('Machine');
      expect(viewModel.canApplySelectedProfile, isTrue);
    });

    test(
      'applies the selected profile and shows the adapter read back',
      () async {
        final viewModel = await initializedViewModel(
          FakeNetworkAdapterReader([
            ethernet(),
            ethernet(
              addressingMode: AddressingMode.staticIp,
              ipAddress: '192.168.0.10',
              subnetMask: '255.255.255.0',
            ),
          ]),
        );
        viewModel
          ..selectAdapter('Ethernet')
          ..selectProfile('Machine');

        await viewModel.applySelectedProfileToSelectedAdapter();

        expect(configurator.appliedProfiles.single, (
          machineProfile,
          'Ethernet',
        ));
        expect(viewModel.statusMessage?.kind, StatusKind.success);
        expect(viewModel.adapters.single.addressText, contains('192.168.0.10'));
        expect(viewModel.isApplying, isFalse);
      },
    );

    test('switches the selected adapter to DHCP', () async {
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );
      viewModel.selectAdapter('Ethernet');

      await viewModel.switchSelectedAdapterToDhcp();

      final (appliedProfile, adapterName) = configurator.appliedProfiles.single;
      expect(appliedProfile.addressingMode, AddressingMode.dhcp);
      expect(adapterName, 'Ethernet');
      expect(viewModel.statusMessage?.kind, StatusKind.success);
    });

    test('explains a netsh failure', () async {
      configurator = RecordingNetworkAdapterConfigurator(
        errorToThrow: const NetworkConfigurationException(
          failedCommand: 'netsh.exe interface ipv4 set address',
          exitCode: 1,
          output: 'The requested operation requires elevation.',
        ),
      );
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );
      viewModel
        ..selectAdapter('Ethernet')
        ..selectProfile('Machine');

      await viewModel.applySelectedProfileToSelectedAdapter();

      expect(viewModel.statusMessage?.kind, StatusKind.error);
      expect(viewModel.statusMessage?.text, contains('requires elevation'));
    });

    test('asks to connect a disconnected DHCP adapter first', () async {
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([
          const NetworkAdapter(
            name: 'Ethernet',
            description: 'Intel(R) Ethernet',
            status: NetworkAdapterStatus.disconnected,
            addressingMode: AddressingMode.dhcp,
          ),
        ]),
      );
      viewModel
        ..selectAdapter('Ethernet')
        ..selectProfile('Machine');

      await viewModel.applySelectedProfileToSelectedAdapter();

      expect(configurator.appliedProfiles, isEmpty);
      expect(viewModel.statusMessage?.kind, StatusKind.error);
      expect(viewModel.statusMessage?.text, contains('not connected'));
    });

    test('lists the settings that did not become active', () async {
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );
      viewModel
        ..selectAdapter('Ethernet')
        ..selectProfile('Machine');

      await viewModel.applySelectedProfileToSelectedAdapter();

      expect(viewModel.statusMessage?.kind, StatusKind.error);
      expect(viewModel.statusMessage?.text, contains('addressingMode'));
    });
  });

  group('profiles', () {
    test('adds a new profile and selects it', () async {
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );
      const labProfile = NetworkProfile(
        name: 'Lab',
        addressingMode: AddressingMode.dhcp,
      );

      await viewModel.saveProfile(labProfile);

      expect(repository.storedProfiles.map((profile) => profile.name), [
        'Machine',
        'Office',
        'Lab',
      ]);
      expect(viewModel.selectedProfileName, 'Lab');
    });

    test('replaces an edited profile in place, also when renamed', () async {
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );
      const renamedProfile = NetworkProfile(
        name: 'Machine 2',
        addressingMode: AddressingMode.staticIp,
        ipAddress: '192.168.0.20',
        subnetMask: '255.255.255.0',
      );

      await viewModel.saveProfile(
        renamedProfile,
        originalProfile: machineProfile,
      );

      expect(repository.storedProfiles.map((profile) => profile.name), [
        'Machine 2',
        'Office',
      ]);
    });

    test('deletes a profile and clears its selection', () async {
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );
      viewModel.selectProfile('Office');

      await viewModel.deleteProfile(officeProfile);

      expect(repository.storedProfiles.map((profile) => profile.name), [
        'Machine',
      ]);
      expect(viewModel.selectedProfileName, isNull);
    });

    test('keeps the profile list when saving fails', () async {
      repository = InMemoryNetworkProfileRepository(
        storedProfiles: [machineProfile],
        saveError: const NetworkProfileStorageException('file is locked'),
      );
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );

      await viewModel.saveProfile(officeProfile);

      expect(viewModel.profiles.map((profile) => profile.name), ['Machine']);
      expect(viewModel.statusMessage?.text, contains('file is locked'));
    });

    test(
      'excludes the edited profile from the names it may not reuse',
      () async {
        final viewModel = await initializedViewModel(
          FakeNetworkAdapterReader([ethernet()]),
        );

        expect(viewModel.profileNamesOtherThan(machineProfile), ['Office']);
        expect(viewModel.profileNamesOtherThan(null), ['Machine', 'Office']);
      },
    );
  });
}
