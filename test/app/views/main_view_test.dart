import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_profile_switcher/app/view_models/main_view_model.dart';
import 'package:network_profile_switcher/core/models/addressing_mode.dart';
import 'package:network_profile_switcher/core/models/network_adapter.dart';
import 'package:network_profile_switcher/core/models/network_profile.dart';
import 'package:network_profile_switcher/core/network_profile_applier.dart';
import 'package:network_profile_switcher/core/profiles/network_profile_validator.dart';
import 'package:network_profile_switcher/core/reachability/ping_targets_checker.dart';
import 'package:network_profile_switcher/main.dart';

import '../../fakes/fake_network_adapter_reader.dart';
import '../../fakes/in_memory_network_profile_repository.dart';
import '../../fakes/recording_network_adapter_configurator.dart';
import '../../fakes/scripted_host_pinger.dart';

void main() {
  late MainViewModel viewModel;

  setUp(() async {
    final reader = FakeNetworkAdapterReader([
      const NetworkAdapter(
        name: 'Ethernet',
        description: 'Intel(R) Ethernet',
        status: NetworkAdapterStatus.connected,
        addressingMode: AddressingMode.dhcp,
        ipAddress: '192.168.2.6',
        subnetMask: '255.255.255.0',
      ),
    ]);
    viewModel = MainViewModel(
      reader: reader,
      repository: InMemoryNetworkProfileRepository(
        storedProfiles: [
          const NetworkProfile(
            name: 'Machine',
            addressingMode: AddressingMode.staticIp,
            ipAddress: '192.168.0.10',
            subnetMask: '255.255.255.0',
          ),
        ],
      ),
      applier: NetworkProfileApplier(
        validator: const NetworkProfileValidator(),
        configurator: RecordingNetworkAdapterConfigurator(),
        reader: reader,
      ),
      pingTargetsChecker: PingTargetsChecker(ScriptedHostPinger()),
    );
    await viewModel.initialize();
  });

  Future<void> showApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      NetworkProfileSwitcherApp(mainViewModel: viewModel),
    );
  }

  testWidgets('colors a connected adapter green and borders the selection', (
    tester,
  ) async {
    await showApp(tester);
    Card adapterCard() => tester.widget<Card>(
      find.ancestor(of: find.text('Ethernet'), matching: find.byType(Card)),
    );
    BorderSide adapterCardBorder() =>
        (adapterCard().shape! as RoundedRectangleBorder).side;

    expect(adapterCard().color, const Color(0xFFE6F4EA));
    expect(adapterCardBorder(), BorderSide.none);

    await tester.tap(find.text('Ethernet'));
    await tester.pump();

    expect(adapterCardBorder().width, 2);
  });

  testWidgets('colors profile cards yellow', (tester) async {
    await showApp(tester);

    final profileCard = tester.widget<Card>(
      find.ancestor(of: find.text('Machine'), matching: find.byType(Card)),
    );
    expect(profileCard.color, const Color(0xFFFFF6D5));
  });

  testWidgets('filters profiles and explains an empty result', (tester) async {
    await showApp(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search profiles by name or IP'),
      'xyz',
    );
    await tester.pump();

    expect(find.text('Machine'), findsNothing);
    expect(find.text('No profiles match "xyz".'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();

    expect(find.text('Machine'), findsOneWidget);
  });

  testWidgets('shows adapters and profiles', (tester) async {
    await showApp(tester);

    expect(find.text('Ethernet'), findsOneWidget);
    expect(find.text('Machine'), findsOneWidget);
    expect(find.text('192.168.0.10 / 255.255.255.0'), findsOneWidget);
  });

  testWidgets('enables applying once adapter and profile are selected', (
    tester,
  ) async {
    await showApp(tester);
    FilledButton applyButton() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply profile to selected adapter'),
    );

    expect(applyButton().onPressed, isNull);

    await tester.tap(find.text('Ethernet'));
    await tester.tap(find.text('Machine'));
    await tester.pump();

    expect(applyButton().onPressed, isNotNull);
  });

  testWidgets('opens the editor and shows inline errors on save', (
    tester,
  ) async {
    await showApp(tester);

    await tester.tap(find.byTooltip('New profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('New profile'), findsOneWidget);
    expect(find.text('Enter a profile name.'), findsOneWidget);
    expect(find.text('Enter an IP address.'), findsOneWidget);
  });
}
