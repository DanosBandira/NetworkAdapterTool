import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_adapter_tool/app/views/help_view.dart';
import 'package:network_adapter_tool/core/platform/host_platform.dart';

void main() {
  Future<void> showLastStep(WidgetTester tester, HostPlatform platform) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HelpView(platform: platform)),
      ),
    );
    while (find.text('Next').evaluate().isNotEmpty) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('tells Windows users that their data is in AppData', (
    tester,
  ) async {
    await showLastStep(tester, HostPlatform.windows);

    expect(find.textContaining(r'%APPDATA%'), findsOneWidget);
    expect(find.textContaining('NetworkManager'), findsNothing);
  });

  testWidgets('tells Linux users about NetworkManager and ~/.config', (
    tester,
  ) async {
    await showLastStep(tester, HostPlatform.linux);

    expect(
      find.textContaining('~/.config/network-adapter-tool'),
      findsOneWidget,
    );
    expect(find.textContaining('NetworkManager'), findsWidgets);
    expect(find.textContaining('%APPDATA%'), findsNothing);
  });
}
