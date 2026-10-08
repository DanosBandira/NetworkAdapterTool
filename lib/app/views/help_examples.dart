import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/addressing_mode.dart';
import '../../core/models/network_adapter.dart';
import '../../core/models/network_profile.dart';
import '../view_models/network_adapter_view_model.dart';
import '../view_models/network_profile_editor_view_model.dart';
import 'adapter_card.dart';
import 'adapter_settings_view.dart';
import 'apply_arrow_button.dart';
import 'card_colors.dart';

/// Example pictures for the help steps. They use the real cards, dialog and
/// arrow button with sample data, so they look like the app; they are
/// wrapped in [IgnorePointer] because they only illustrate.

const _calloutColor = Color(0xFFE65100);

final _connectedStaticEthernet = NetworkAdapterViewModel(
  const NetworkAdapter(
    name: 'Ethernet',
    description: 'Intel(R) Ethernet Connection I219-V',
    status: NetworkAdapterStatus.connected,
    addressingMode: AddressingMode.staticIp,
    ipAddress: '10.100.10.4',
    subnetMask: '255.255.255.0',
  ),
);

final _connectedDhcpWifi = NetworkAdapterViewModel(
  const NetworkAdapter(
    name: 'Wi-Fi',
    description: 'Intel(R) Wi-Fi 6E AX211',
    status: NetworkAdapterStatus.connected,
    addressingMode: AddressingMode.dhcp,
    ipAddress: '192.168.2.6',
    subnetMask: '255.255.255.0',
    defaultGateway: '192.168.2.254',
  ),
);

final _disconnectedUsbAdapter = NetworkAdapterViewModel(
  const NetworkAdapter(
    name: 'USB LAN',
    description: 'USB 3.0 Gigabit Ethernet',
    status: NetworkAdapterStatus.disconnected,
    addressingMode: AddressingMode.dhcp,
    ipAddress: '169.254.12.7',
    subnetMask: '255.255.0.0',
  ),
);

/// Step 1: an adapter card with "Double-click to change" and the dialog
/// that opens.
class ChangeAdapterExample extends StatelessWidget {
  const ChangeAdapterExample({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 250,
            child: HelpCallout(
              label: 'Double-click to change',
              child: _exampleAdapterCard(_connectedStaticEthernet),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.arrow_forward, size: 32, color: _calloutColor),
          ),
          SizedBox(
            width: 360,
            height: 360,
            child: FittedBox(child: _exampleAdapterSettingsDialog()),
          ),
        ],
      ),
    );
  }

  Widget _exampleAdapterSettingsDialog() {
    return SizedBox(
      width: 520,
      child: ChangeNotifierProvider(
        create: (_) => NetworkProfileEditorViewModel(
          originalProfile: const NetworkProfile(
            name: 'Manual settings',
            addressingMode: AddressingMode.staticIp,
            ipAddress: '10.100.10.4',
            subnetMask: '255.255.255.0',
          ),
          otherProfileNames: const [],
        ),
        child: AdapterSettingsView(adapter: _connectedStaticEthernet),
      ),
    );
  }
}

/// Step 2: a connected (green) and a disconnected (red) adapter.
class AdapterColorsExample extends StatelessWidget {
  const AdapterColorsExample({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 240,
            child: HelpCallout(
              label: 'Connected',
              child: _exampleAdapterCard(_connectedDhcpWifi),
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 240,
            child: HelpCallout(
              label: 'Not connected',
              child: _exampleAdapterCard(_disconnectedUsbAdapter),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 3: a selected adapter, a selected profile card with ping results and
/// the arrow button, numbered in the order the user acts.
class ApplyProfileExample extends StatelessWidget {
  const ApplyProfileExample({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 240,
                child: HelpCallout(
                  label: '1. Select an adapter',
                  child: AdapterCard(
                    adapter: _connectedStaticEthernet,
                    isSelected: true,
                    onTap: () {},
                    onDoubleTap: null,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 400,
                child: HelpCallout(
                  label: '2. Select a profile',
                  child: _selectedProfileCard(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          HelpCallout(
            label: '3. Click to apply',
            child: ApplyArrowButton(onPressed: () {}),
          ),
        ],
      ),
    );
  }

  Widget _selectedProfileCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: CardColors.profile(theme.brightness, isSelected: true),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: const Text('Machine'),
            subtitle: const Text(
              '10.100.10.4 / 255.255.255.0 · 2 ping targets',
            ),
            trailing: OutlinedButton(
              onPressed: () {},
              child: const Text('Ping'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                _ExamplePingResult('PLC · 10.100.10.1', '3 ms'),
                _ExamplePingResult('HMI · 10.100.10.2', '<1 ms'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 4: a preset card with its lines and the Ping and Apply buttons.
class PresetExample extends StatelessWidget {
  const PresetExample({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: SizedBox(
        width: 460,
        child: HelpCallout(
          label: 'One click, configure adapter(s)',
          child: Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: CardColors.preset(theme.brightness),
            child: ListTile(
              title: const Text('Machine setup'),
              subtitle: const Text('Ethernet ← Machine\nWi-Fi ← Office'),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(onPressed: () {}, child: const Text('Ping')),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () {},
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Step 5: the Import and Export buttons of the app bar.
class ImportExportExample extends StatelessWidget {
  const ImportExportExample({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: HelpCallout(
          label: 'Top right',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Import'),
              ),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Export'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An orange frame around [child] with a label above it, pointing out the
/// part of the app a help step is about.
class HelpCallout extends StatelessWidget {
  const HelpCallout({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Centered rather than stretched, so the frame hugs its child (e.g. the
    // arrow button keeps its own width instead of filling the dialog).
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _calloutColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: Colors.white),
            ),
          ),
        ),
        const Icon(Icons.arrow_drop_down, color: _calloutColor, size: 28),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            border: Border.all(color: _calloutColor, width: 3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _ExamplePingResult extends StatelessWidget {
  const _ExamplePingResult(this.target, this.result);

  static const _reachableColor = Color(0xFF2E7D32);

  final String target;
  final String result;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 10, color: _reachableColor),
          const SizedBox(width: 8),
          Expanded(child: Text(target, style: style)),
          Text(result, style: style?.copyWith(color: _reachableColor)),
        ],
      ),
    );
  }
}

Widget _exampleAdapterCard(NetworkAdapterViewModel adapter) {
  return AdapterCard(
    adapter: adapter,
    isSelected: false,
    onTap: () {},
    onDoubleTap: null,
  );
}
