import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/app/view_models/main_view_model.dart';
import 'package:network_adapter_tool/app/views/left_arrow_border.dart';
import 'package:network_adapter_tool/core/models/addressing_mode.dart';
import 'package:network_adapter_tool/core/models/network_adapter.dart';
import 'package:network_adapter_tool/core/models/network_profile.dart';
import 'package:network_adapter_tool/core/network_preset_applier.dart';
import 'package:network_adapter_tool/core/network_profile_applier.dart';
import 'package:network_adapter_tool/core/profiles/network_profile_validator.dart';
import 'package:network_adapter_tool/core/reachability/ping_targets_checker.dart';
import 'package:network_adapter_tool/main.dart';

import '../../fakes/fake_network_adapter_reader.dart';
import '../../fakes/in_memory_network_profile_repository.dart';
import '../../fakes/recording_network_adapter_configurator.dart';
import '../../fakes/scripted_host_pinger.dart';

void main() {
  late MainViewModel viewModel;
  late RecordingNetworkAdapterConfigurator configurator;

  setUp(() async {
    configurator = RecordingNetworkAdapterConfigurator();
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
    final applier = NetworkProfileApplier(
      validator: const NetworkProfileValidator(),
      configurator: configurator,
      reader: reader,
    );
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
      applier: applier,
      presetApplier: NetworkPresetApplier(applier),
      pingTargetsChecker: PingTargetsChecker(ScriptedHostPinger()),
    );
    await viewModel.initialize();
  });

  Future<void> showApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NetworkAdapterToolApp(mainViewModel: viewModel));
  }

  Future<void> doubleClick(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows info and refresh next to each other in the adapter header',
    (tester) async {
      await showApp(tester);

      final infoIcon = find.byIcon(Icons.info_outline);
      final refreshButton = find.byTooltip('Refresh adapters');
      expect(infoIcon, findsOneWidget);
      expect(refreshButton, findsOneWidget);
      expect(
        tester.getCenter(refreshButton).dy,
        closeTo(tester.getCenter(infoIcon).dy, 1),
      );
      expect(
        tester.getCenter(refreshButton).dx,
        greaterThan(tester.getCenter(infoIcon).dx),
      );
    },
  );

  testWidgets('uses a neutral white background without seed tint', (
    tester,
  ) async {
    await showApp(tester);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(
      scaffold.backgroundColor ?? theme.colorScheme.surface,
      const Color(0xFFFFFFFF),
    );
    expect(theme.colorScheme.surfaceTint, Colors.transparent);
  });

  testWidgets('double-clicking an adapter opens its settings', (tester) async {
    await showApp(tester);

    await doubleClick(tester, find.text('Ethernet'));

    expect(find.text('Configure Ethernet'), findsOneWidget);
    expect(
      find.text('Applied directly; not saved as a profile.'),
      findsOneWidget,
    );
    // The adapter uses DHCP, so the dialog starts on DHCP without fields.
    expect(find.text('IP address'), findsNothing);
  });

  testWidgets('applies settings entered in the adapter dialog directly', (
    tester,
  ) async {
    await showApp(tester);
    await doubleClick(tester, find.text('Ethernet'));

    await tester.tap(find.text('Static IP'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'IP address'),
      '10.100.10.4',
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Configure Ethernet'), findsNothing);
    final (appliedSettings, adapterName) = configurator.appliedProfiles.single;
    expect(adapterName, 'Ethernet');
    expect(appliedSettings.addressingMode, AddressingMode.staticIp);
    expect(appliedSettings.ipAddress, '10.100.10.4');
    expect(appliedSettings.subnetMask, '255.255.255.0');
    expect(viewModel.profiles.map((profile) => profile.name), ['Machine']);
  });

  testWidgets('colors a connected adapter green, darker when selected', (
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

    // Selected right away, without waiting for the double-tap timeout.
    expect(adapterCard().color, const Color(0xFFB4DDBF));
    await tester.pump(kDoubleTapTimeout);
    expect(adapterCardBorder().width, 2);
  });

  testWidgets('colors profile cards yellow, darker when selected', (
    tester,
  ) async {
    await showApp(tester);
    Card profileCard() => tester.widget<Card>(
      find.ancestor(of: find.text('Machine'), matching: find.byType(Card)),
    );

    expect(profileCard().color, const Color(0xFFFFF6D5));

    await tester.tap(find.text('Machine'));
    await tester.pump();

    expect(profileCard().color, const Color(0xFFFFE38C));
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

  testWidgets('shows the apply action as a left arrow without a DHCP button', (
    tester,
  ) async {
    await showApp(tester);

    final applyButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply profile to selected adapter'),
    );
    expect(applyButton.style!.shape!.resolve({}), isA<LeftArrowBorder>());
    expect(
      applyButton.style!.backgroundColor!.resolve({}),
      const Color(0xFFF57C00),
    );
    expect(find.text('Switch to DHCP'), findsNothing);
  });

  testWidgets('shows an empty presets panel below the profiles', (
    tester,
  ) async {
    await showApp(tester);

    expect(find.text('Presets'), findsOneWidget);
    expect(find.byTooltip('New preset'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Presets')).dy,
      greaterThan(tester.getTopLeft(find.text('Profiles')).dy),
    );
  });

  testWidgets('opens the preset editor with one empty line', (tester) async {
    await showApp(tester);

    await tester.tap(find.byTooltip('New preset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('New preset'), findsOneWidget);
    expect(find.text('Enter a preset name.'), findsOneWidget);
    expect(
      find.text('Choose an adapter and a profile on every line.'),
      findsOneWidget,
    );
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
    await tester.pump(kDoubleTapTimeout);

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
