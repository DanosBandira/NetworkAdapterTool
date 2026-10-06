import 'package:flutter_test/flutter_test.dart';
import 'package:network_profile_switcher/app/view_models/main_view_model.dart';
import 'package:network_profile_switcher/core/contracts/network_adapter_configurator.dart';
import 'package:network_profile_switcher/core/contracts/network_adapter_reader.dart';
import 'package:network_profile_switcher/core/contracts/network_profile_repository.dart';
import 'package:network_profile_switcher/core/models/addressing_mode.dart';
import 'package:network_profile_switcher/core/models/network_adapter.dart';
import 'package:network_profile_switcher/core/models/network_profile.dart';
import 'package:network_profile_switcher/core/network_profile_applier.dart';
import 'package:network_profile_switcher/core/models/ping_target.dart';
import 'package:network_profile_switcher/core/profiles/network_profile_validator.dart';
import 'package:network_profile_switcher/core/reachability/ping_targets_checker.dart';

import '../../fakes/fake_network_adapter_reader.dart';
import '../../fakes/in_memory_network_profile_repository.dart';
import '../../fakes/recording_network_adapter_configurator.dart';
import '../../fakes/scripted_host_pinger.dart';

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
  late ScriptedHostPinger pinger;

  setUp(() {
    configurator = RecordingNetworkAdapterConfigurator();
    repository = InMemoryNetworkProfileRepository(
      storedProfiles: [machineProfile, officeProfile],
    );
    pinger = ScriptedHostPinger();
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
      pingTargetsChecker: PingTargetsChecker(
        pinger,
        tryFor: const Duration(milliseconds: 50),
        pauseAfterFailedAttempt: const Duration(milliseconds: 5),
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

  group('ping targets', () {
    const plc = PingTarget(ipAddress: '10.100.10.1', name: 'PLC');
    const hmi = PingTarget(ipAddress: '10.100.10.2', name: 'HMI');
    const lineProfile = NetworkProfile(
      name: 'Line 1',
      addressingMode: AddressingMode.dhcp,
      pingTargets: [plc, hmi],
    );

    setUp(() {
      repository = InMemoryNetworkProfileRepository(
        storedProfiles: [lineProfile, officeProfile],
      );
      pinger = ScriptedHostPinger({
        plc.ipAddress: [const Duration(milliseconds: 3)],
      });
    });

    PingState stateOf(MainViewModel viewModel, PingTarget target) => viewModel
        .pingStatusesFor(lineProfile.name)!
        .singleWhere((status) => status.target == target)
        .state;

    test('pings automatically after applying the profile', () async {
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );
      viewModel
        ..selectAdapter('Ethernet')
        ..selectProfile(lineProfile.name);

      await viewModel.applySelectedProfileToSelectedAdapter();

      expect(stateOf(viewModel, plc), PingState.reachable);
      expect(stateOf(viewModel, hmi), PingState.unreachable);
      expect(viewModel.isPinging(lineProfile.name), isFalse);
    });

    test('does not ping when applying failed', () async {
      configurator = RecordingNetworkAdapterConfigurator(
        errorToThrow: const NetworkConfigurationException(
          failedCommand: 'netsh.exe',
          exitCode: 1,
          output: 'failed',
        ),
      );
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );
      viewModel
        ..selectAdapter('Ethernet')
        ..selectProfile(lineProfile.name);

      await viewModel.applySelectedProfileToSelectedAdapter();

      expect(viewModel.pingStatusesFor(lineProfile.name), isNull);
      expect(pinger.attemptsPerAddress, isEmpty);
    });

    test('pings on demand and shows progress while pinging', () async {
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );

      final pinging = viewModel.pingTargetsOf(lineProfile);

      expect(viewModel.isPinging(lineProfile.name), isTrue);
      expect(viewModel.canPingProfile(lineProfile), isFalse);
      expect(stateOf(viewModel, hmi), PingState.pinging);

      await pinging;

      expect(stateOf(viewModel, plc), PingState.reachable);
      expect(
        viewModel
            .pingStatusesFor(lineProfile.name)!
            .firstWhere((status) => status.target == plc)
            .resultText,
        '3 ms',
      );
      expect(viewModel.canPingProfile(lineProfile), isTrue);
    });

    test('cannot ping a profile without targets', () async {
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );

      expect(viewModel.canPingProfile(officeProfile), isFalse);
    });

    test('forgets results when the profile is deleted', () async {
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );
      await viewModel.pingTargetsOf(lineProfile);

      await viewModel.deleteProfile(lineProfile);

      expect(viewModel.pingStatusesFor(lineProfile.name), isNull);
    });
  });

  group('search', () {
    final wifi = NetworkAdapter(
      name: 'Wi-Fi',
      description: 'Intel(R) Wi-Fi 6E',
      status: NetworkAdapterStatus.connected,
      addressingMode: AddressingMode.dhcp,
      ipAddress: '192.168.2.6',
    );

    test('filters adapters on name, description and IP', () async {
      final viewModel = await initializedViewModel(
        _TwoAdapterReader(ethernet(), wifi),
      );

      viewModel.searchAdapters('wi-fi');
      expect(viewModel.visibleAdapters.map((adapter) => adapter.name), [
        'Wi-Fi',
      ]);

      viewModel.searchAdapters('ETHERNET');
      expect(viewModel.visibleAdapters.map((adapter) => adapter.name), [
        'Ethernet',
      ]);

      viewModel.searchAdapters('192.168.2');
      expect(viewModel.visibleAdapters.map((adapter) => adapter.name), [
        'Wi-Fi',
      ]);

      viewModel.searchAdapters('  ');
      expect(viewModel.visibleAdapters, hasLength(2));
    });

    test('filters profiles on name and IP', () async {
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );

      viewModel.searchProfiles('off');
      expect(viewModel.visibleProfiles.map((profile) => profile.name), [
        'Office',
      ]);

      viewModel.searchProfiles('192.168.0');
      expect(viewModel.visibleProfiles.map((profile) => profile.name), [
        'Machine',
      ]);
    });

    test('keeps the selection when it is filtered out', () async {
      final viewModel = await initializedViewModel(
        FakeNetworkAdapterReader([ethernet()]),
      );
      viewModel
        ..selectAdapter('Ethernet')
        ..selectProfile('Machine')
        ..searchAdapters('nothing matches')
        ..searchProfiles('nothing matches');

      expect(viewModel.visibleAdapters, isEmpty);
      expect(viewModel.selectedAdapterName, 'Ethernet');
      expect(viewModel.canApplySelectedProfile, isTrue);
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

/// Returns two adapters on every read, for search tests.
class _TwoAdapterReader implements NetworkAdapterReader {
  _TwoAdapterReader(this.first, this.second);

  final NetworkAdapter first;
  final NetworkAdapter second;

  @override
  Future<List<NetworkAdapter>> readAllAdapters() async => [first, second];

  @override
  Future<NetworkAdapter?> readAdapterByName(String adapterName) async => [
    first,
    second,
  ].where((adapter) => adapter.name == adapterName).firstOrNull;
}
