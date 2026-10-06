import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/addressing_mode.dart';
import '../../core/models/network_profile.dart';
import '../view_models/main_view_model.dart';
import '../view_models/network_adapter_view_model.dart';
import '../view_models/network_profile_editor_view_model.dart';
import 'network_profile_editor_view.dart';

/// Main window: adapters on the left, profiles on the right, apply actions
/// and the status line at the bottom.
class MainView extends StatelessWidget {
  const MainView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MainViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Profile Switcher'),
        actions: [
          IconButton(
            tooltip: 'Refresh adapters',
            icon: const Icon(Icons.refresh),
            onPressed: viewModel.isLoadingAdapters || viewModel.isApplying
                ? null
                : viewModel.refreshAdapters,
          ),
        ],
      ),
      body: Column(
        children: [
          const Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _AdapterPanel()),
                VerticalDivider(width: 1),
                Expanded(flex: 2, child: _ProfilePanel()),
              ],
            ),
          ),
          const Divider(height: 1),
          const _ActionBar(),
        ],
      ),
    );
  }
}

class _AdapterPanel extends StatelessWidget {
  const _AdapterPanel();

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MainViewModel>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PanelHeader(title: 'Adapters'),
        if (viewModel.isLoadingAdapters) const LinearProgressIndicator(),
        Expanded(
          child: viewModel.adapters.isEmpty && !viewModel.isLoadingAdapters
              ? const _EmptyPanelText('No network adapters found.')
              : ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (final adapter in viewModel.adapters)
                      _AdapterTile(
                        adapter: adapter,
                        isSelected:
                            adapter.name == viewModel.selectedAdapterName,
                        onTap: () => viewModel.selectAdapter(adapter.name),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _AdapterTile extends StatelessWidget {
  const _AdapterTile({
    required this.adapter,
    required this.isSelected,
    required this.onTap,
  });

  static const _connectedBackgroundLight = Color(0xFFE6F4EA);
  static const _connectedBackgroundDark = Color(0xFF1E3A2A);
  static const _notConnectedBackgroundLight = Color(0xFFFCE8E6);
  static const _notConnectedBackgroundDark = Color(0xFF3D2222);

  final NetworkAdapterViewModel adapter;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final detailLines = [
      adapter.description,
      adapter.addressText,
      ?adapter.gatewayText,
      ?adapter.dnsServersText,
    ];
    return Card(
      elevation: 0,
      color: _connectionBackground(Theme.of(context).brightness),
      // The background shows the connection state, so selection is shown
      // with a border instead.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: colors.primary, width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          Icons.lan_outlined,
          color: adapter.isConnected ? colors.primary : colors.outline,
        ),
        title: Text(adapter.name),
        subtitle: Text(detailLines.join('\n')),
        isThreeLine: detailLines.length > 1,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              adapter.addressingModeText,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text(
              adapter.statusText,
              style: TextStyle(
                color: adapter.isConnected ? colors.primary : colors.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _connectionBackground(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    if (adapter.isConnected) {
      return isDark ? _connectedBackgroundDark : _connectedBackgroundLight;
    }
    return isDark ? _notConnectedBackgroundDark : _notConnectedBackgroundLight;
  }
}

class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel();

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MainViewModel>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          title: 'Profiles',
          action: IconButton(
            tooltip: 'New profile',
            icon: const Icon(Icons.add),
            onPressed: viewModel.canEditProfiles
                ? () => _openProfileEditor(context, profileToEdit: null)
                : null,
          ),
        ),
        Expanded(
          child: viewModel.profiles.isEmpty
              ? const _EmptyPanelText('No profiles yet. Add one with +.')
              : ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (final profile in viewModel.profiles)
                      _ProfileTile(
                        profile: profile,
                        isSelected:
                            profile.name == viewModel.selectedProfileName,
                        canEdit: viewModel.canEditProfiles,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.isSelected,
    required this.canEdit,
  });

  final NetworkProfile profile;
  final bool isSelected;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<MainViewModel>();
    return Card(
      elevation: 0,
      color: isSelected
          ? Theme.of(context).colorScheme.secondaryContainer
          : null,
      child: ListTile(
        onTap: () => viewModel.selectProfile(profile.name),
        title: Text(profile.name),
        subtitle: Text(_describeProfile(profile)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: canEdit
                  ? () => _openProfileEditor(context, profileToEdit: profile)
                  : null,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: canEdit
                  ? () => _confirmAndDeleteProfile(context, profile)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  String _describeProfile(NetworkProfile profile) {
    if (profile.addressingMode == AddressingMode.dhcp) return 'DHCP';
    return '${profile.ipAddress} / ${profile.subnetMask}';
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar();

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MainViewModel>();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(child: _StatusLine(message: viewModel.statusMessage)),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: viewModel.canSwitchSelectedAdapterToDhcp
                ? viewModel.switchSelectedAdapterToDhcp
                : null,
            child: const Text('Switch to DHCP'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: viewModel.canApplySelectedProfile
                ? viewModel.applySelectedProfileToSelectedAdapter
                : null,
            child: const Text('Apply profile to selected adapter'),
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.message});

  final StatusMessage? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null) {
      return Text(
        'Select an adapter and a profile.',
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final (icon, color) = switch (message.kind) {
      StatusKind.progress => (null, colors.onSurface),
      StatusKind.success => (Icons.check_circle_outline, colors.primary),
      StatusKind.error => (Icons.error_outline, colors.error),
    };
    return Row(
      children: [
        if (icon == null)
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            message.text,
            style: TextStyle(color: color),
            maxLines: 3,
          ),
        ),
        if (message.kind != StatusKind.progress)
          IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 18),
            onPressed: context.read<MainViewModel>().dismissStatusMessage,
          ),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _EmptyPanelText extends StatelessWidget {
  const _EmptyPanelText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}

Future<void> _openProfileEditor(
  BuildContext context, {
  required NetworkProfile? profileToEdit,
}) async {
  final mainViewModel = context.read<MainViewModel>();
  final savedProfile = await showDialog<NetworkProfile>(
    context: context,
    builder: (_) => ChangeNotifierProvider(
      create: (_) => NetworkProfileEditorViewModel(
        originalProfile: profileToEdit,
        otherProfileNames: mainViewModel.profileNamesOtherThan(profileToEdit),
      ),
      child: const NetworkProfileEditorView(),
    ),
  );
  if (savedProfile == null) return;
  await mainViewModel.saveProfile(savedProfile, originalProfile: profileToEdit);
}

Future<void> _confirmAndDeleteProfile(
  BuildContext context,
  NetworkProfile profile,
) async {
  final mainViewModel = context.read<MainViewModel>();
  final isConfirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete profile?'),
      content: Text('"${profile.name}" will be removed.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (isConfirmed ?? false) await mainViewModel.deleteProfile(profile);
}
