import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/addressing_mode.dart';
import '../../core/models/network_preset.dart';
import '../../core/models/network_profile.dart';
import '../view_models/main_view_model.dart';
import '../view_models/network_adapter_view_model.dart';
import '../view_models/network_preset_editor_view_model.dart';
import '../view_models/network_profile_editor_view_model.dart';
import 'left_arrow_border.dart';
import 'network_preset_editor_view.dart';
import 'network_profile_editor_view.dart';

/// Main window: adapters on the left; profiles (top) and presets (bottom) on
/// the right; the apply action and the status line at the bottom.
class MainView extends StatelessWidget {
  const MainView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MainViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Adapter Tool'),
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
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _ProfilePanel()),
                      Divider(height: 1),
                      Expanded(child: _PresetPanel()),
                    ],
                  ),
                ),
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
        _SearchField(
          hint: 'Search adapters by name, description or IP',
          onChanged: viewModel.searchAdapters,
        ),
        if (viewModel.isLoadingAdapters) const LinearProgressIndicator(),
        Expanded(
          child:
              viewModel.visibleAdapters.isEmpty && !viewModel.isLoadingAdapters
              ? _EmptyPanelText(
                  viewModel.adapters.isEmpty
                      ? 'No network adapters found.'
                      : 'No adapters match "${viewModel.adapterSearchText}".',
                )
              : _AdapterGrid(viewModel: viewModel),
        ),
      ],
    );
  }
}

/// Lays adapter cards out in 1 to 3 columns depending on the panel width,
/// so more adapters fit on screen. Rows grow to their tallest card, because
/// cards differ in height (gateway and DNS lines are optional).
class _AdapterGrid extends StatelessWidget {
  const _AdapterGrid({required this.viewModel});

  static const _minimumCardWidth = 240.0;
  static const _maximumColumns = 3;
  static const _spacing = 8.0;

  final MainViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 2 * _spacing;
        final cardWidth = _cardWidthFor(availableWidth);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(_spacing),
          child: Wrap(
            spacing: _spacing,
            runSpacing: _spacing,
            children: [
              for (final adapter in viewModel.visibleAdapters)
                SizedBox(
                  width: cardWidth,
                  child: _AdapterTile(
                    adapter: adapter,
                    isSelected: adapter.name == viewModel.selectedAdapterName,
                    onTap: () => viewModel.selectAdapter(adapter.name),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  double _cardWidthFor(double availableWidth) {
    final columns = (availableWidth / _minimumCardWidth).floor().clamp(
      1,
      _maximumColumns,
    );
    final totalSpacing = (columns - 1) * _spacing;
    // Floor avoids a rounding overflow that would wrap the last card early.
    return ((availableWidth - totalSpacing) / columns).floorToDouble();
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
  static const _selectedConnectedBackgroundLight = Color(0xFFB4DDBF);
  static const _selectedConnectedBackgroundDark = Color(0xFF2E5C40);
  static const _selectedNotConnectedBackgroundLight = Color(0xFFF4B6AE);
  static const _selectedNotConnectedBackgroundDark = Color(0xFF633030);

  final NetworkAdapterViewModel adapter;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = adapter.isConnected ? colors.primary : colors.outline;
    final detailStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: _connectionBackground(theme.brightness),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: colors.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lan_outlined, color: statusColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      adapter.name,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    adapter.addressingModeText,
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                adapter.statusText,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: statusColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                adapter.description,
                style: detailStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              for (final detailLine in [
                adapter.addressText,
                ?adapter.gatewayText,
                ?adapter.dnsServersText,
              ])
                Text(detailLine, style: detailStyle),
            ],
          ),
        ),
      ),
    );
  }

  // The selected card keeps its connection color, only a darker shade.
  Color _connectionBackground(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch ((adapter.isConnected, isSelected, isDark)) {
      (true, false, false) => _connectedBackgroundLight,
      (true, false, true) => _connectedBackgroundDark,
      (true, true, false) => _selectedConnectedBackgroundLight,
      (true, true, true) => _selectedConnectedBackgroundDark,
      (false, false, false) => _notConnectedBackgroundLight,
      (false, false, true) => _notConnectedBackgroundDark,
      (false, true, false) => _selectedNotConnectedBackgroundLight,
      (false, true, true) => _selectedNotConnectedBackgroundDark,
    };
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
        _SearchField(
          hint: 'Search profiles by name or IP',
          onChanged: viewModel.searchProfiles,
        ),
        Expanded(
          child: viewModel.visibleProfiles.isEmpty
              ? _EmptyPanelText(
                  viewModel.profiles.isEmpty
                      ? 'No profiles yet. Add one with +.'
                      : 'No profiles match "${viewModel.profileSearchText}".',
                )
              : ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (final profile in viewModel.visibleProfiles)
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

  static const _profileBackgroundLight = Color(0xFFFFF6D5);
  static const _profileBackgroundDark = Color(0xFF3A3320);
  static const _selectedProfileBackgroundLight = Color(0xFFFFE38C);
  static const _selectedProfileBackgroundDark = Color(0xFF5E5024);

  final NetworkProfile profile;
  final bool isSelected;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MainViewModel>();
    final theme = Theme.of(context);
    final pingStatuses = viewModel.pingStatusesFor(profile.name);
    return Card(
      elevation: 0,
      color: _profileBackground(theme.brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, viewModel),
          if (pingStatuses != null) _PingResults(statuses: pingStatuses),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, MainViewModel viewModel) {
    return ListTile(
      onTap: () => viewModel.selectProfile(profile.name),
      title: Text(profile.name),
      subtitle: Text(_describeProfile(profile)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (profile.pingTargets.isNotEmpty)
            OutlinedButton(
              onPressed: viewModel.canPingProfile(profile)
                  ? () => viewModel.pingTargetsOf(profile)
                  : null,
              child: viewModel.isPinging(profile.name)
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Ping'),
                      ],
                    )
                  : const Text('Ping'),
            ),
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
    );
  }

  Color _profileBackground(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    if (isSelected) {
      return isDark
          ? _selectedProfileBackgroundDark
          : _selectedProfileBackgroundLight;
    }
    return isDark ? _profileBackgroundDark : _profileBackgroundLight;
  }

  String _describeProfile(NetworkProfile profile) {
    final addressing = profile.addressingMode == AddressingMode.dhcp
        ? 'DHCP'
        : '${profile.ipAddress} / ${profile.subnetMask}';
    final targetCount = profile.pingTargets.length;
    return switch (targetCount) {
      0 => addressing,
      1 => '$addressing · 1 ping target',
      _ => '$addressing · $targetCount ping targets',
    };
  }
}

/// Ping state per target under a profile card: a colored dot (or spinner),
/// the target and its round-trip time or "No reply".
class _PingResults extends StatelessWidget {
  const _PingResults({required this.statuses});

  static const _reachableColor = Color(0xFF2E7D32);

  final List<PingTargetStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          for (final status in statuses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  _buildStateIndicator(status.state, theme),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _describeTarget(status),
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    status.resultText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _resultColor(status.state, theme),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStateIndicator(PingState state, ThemeData theme) {
    if (state == PingState.pinging) {
      return const SizedBox.square(
        dimension: 10,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      );
    }
    return Icon(Icons.circle, size: 10, color: _resultColor(state, theme));
  }

  Color _resultColor(PingState state, ThemeData theme) => switch (state) {
    PingState.pinging => theme.colorScheme.outline,
    PingState.reachable => _reachableColor,
    PingState.unreachable => theme.colorScheme.error,
  };

  String _describeTarget(PingTargetStatus status) {
    final target = status.target;
    return target.name == null || target.name!.trim().isEmpty
        ? target.ipAddress
        : '${target.name} · ${target.ipAddress}';
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar();

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MainViewModel>();
    // "Switch to DHCP" is hidden for now; MainViewModel still offers
    // switchSelectedAdapterToDhcp so the button can return.
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: _ApplyArrowButton(
              onPressed: viewModel.canApplySelectedProfile
                  ? viewModel.applySelectedProfileToSelectedAdapter
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          _StatusLine(message: viewModel.statusMessage),
        ],
      ),
    );
  }
}

/// The main action, shaped as an arrow pointing from the profiles (right)
/// to the adapters (left).
class _ApplyArrowButton extends StatelessWidget {
  const _ApplyArrowButton({required this.onPressed});

  static const _height = 52.0;

  // Orange stands out from the green, red and yellow cards; the disabled
  // state keeps the theme's grey so it is clear when nothing can be applied.
  static const _background = Color(0xFFF57C00);
  static const _foreground = Colors.white;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    const headWidth = _height * LeftArrowBorder.headWidthFactor;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        shape: const LeftArrowBorder(),
        backgroundColor: _background,
        foregroundColor: _foreground,
        minimumSize: const Size(0, _height),
        // Extra room on the left keeps the text out of the arrow head.
        padding: const EdgeInsets.fromLTRB(headWidth + 12, 0, 28, 0),
        textStyle: Theme.of(context).textTheme.titleMedium,
      ),
      child: const Text('Apply profile to selected adapter'),
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

/// Search box below a panel header, with a clear button once text is typed.
class _SearchField extends StatefulWidget {
  const _SearchField({required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: TextField(
        controller: _controller,
        onChanged: (text) {
          widget.onChanged(text);
          setState(() {});
        },
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close),
                  onPressed: _clearSearch,
                ),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  void _clearSearch() {
    _controller.clear();
    widget.onChanged('');
    setState(() {});
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
  final usingPresets = mainViewModel.presetsUsingProfile(profile.name);
  if (usingPresets.isNotEmpty) {
    await _explainProfileIsUsedByPresets(context, profile, usingPresets);
    return;
  }
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

Future<void> _explainProfileIsUsedByPresets(
  BuildContext context,
  NetworkProfile profile,
  List<NetworkPreset> usingPresets,
) {
  final presetNames = [for (final preset in usingPresets) '"${preset.name}"']
      .join(', ');
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Profile is in use'),
      content: Text(
        '"${profile.name}" is used by $presetNames. '
        'Remove it from those presets before deleting it.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class _PresetPanel extends StatelessWidget {
  const _PresetPanel();

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MainViewModel>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          title: 'Presets',
          action: IconButton(
            tooltip: 'New preset',
            icon: const Icon(Icons.add),
            onPressed: viewModel.canEditPresets
                ? () => _openPresetEditor(context, presetToEdit: null)
                : null,
          ),
        ),
        Expanded(
          child: viewModel.presets.isEmpty
              ? const _EmptyPanelText(
                  'No presets yet. Add one with + to switch several '
                  'adapters at once.',
                )
              : ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (final preset in viewModel.presets)
                      _PresetTile(preset: preset),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.preset});

  static const _presetBackgroundLight = Color(0xFFEDE7F6);
  static const _presetBackgroundDark = Color(0xFF2E2640);

  final NetworkPreset preset;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MainViewModel>();
    final theme = Theme.of(context);
    final lineStatuses = viewModel.lineStatusesFor(preset.name);
    return Card(
      elevation: 0,
      color: theme.brightness == Brightness.dark
          ? _presetBackgroundDark
          : _presetBackgroundLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(preset.name),
            subtitle: Text(_describeAssignments()),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (viewModel.pingableProfilesOf(preset).isNotEmpty) ...[
                  _buildPingButton(viewModel),
                  const SizedBox(width: 8),
                ],
                _buildApplyButton(viewModel),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: viewModel.canEditPresets
                      ? () => _openPresetEditor(context, presetToEdit: preset)
                      : null,
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: viewModel.canEditPresets
                      ? () => _confirmAndDeletePreset(context, preset)
                      : null,
                ),
              ],
            ),
          ),
          if (lineStatuses != null) _PresetLineResults(statuses: lineStatuses),
          ..._buildPingResultsPerProfile(context, viewModel),
        ],
      ),
    );
  }

  // Arrow points left like the apply button: the profile goes onto the
  // adapter.
  String _describeAssignments() => [
    for (final assignment in preset.assignments)
      '${assignment.adapterName} ← ${assignment.profileName}',
  ].join('\n');

  // Same results as under the profile cards, repeated here so the whole
  // preset's reachability is visible in one place.
  List<Widget> _buildPingResultsPerProfile(
    BuildContext context,
    MainViewModel viewModel,
  ) {
    return [
      for (final profile in viewModel.pingableProfilesOf(preset))
        if (viewModel.pingStatusesFor(profile.name) case final statuses?) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            child: Text(
              'Ping ${profile.name}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          _PingResults(statuses: statuses),
        ],
    ];
  }

  Widget _buildPingButton(MainViewModel viewModel) {
    return OutlinedButton(
      onPressed: viewModel.canPingPreset(preset)
          ? () => viewModel.pingPreset(preset)
          : null,
      child: viewModel.isPingingPreset(preset)
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Ping'),
              ],
            )
          : const Text('Ping'),
    );
  }

  Widget _buildApplyButton(MainViewModel viewModel) {
    return FilledButton.tonal(
      onPressed: viewModel.canApplyPresets
          ? () => viewModel.applyPreset(preset)
          : null,
      child: viewModel.isApplyingPreset(preset.name)
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Apply'),
              ],
            )
          : const Text('Apply'),
    );
  }
}

/// Result per preset line: a spinner while waiting, then a check or cross
/// with the outcome message.
class _PresetLineResults extends StatelessWidget {
  const _PresetLineResults({required this.statuses});

  static const _appliedColor = Color(0xFF2E7D32);

  final List<PresetLineStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final status in statuses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox.square(
                    dimension: 16,
                    child: _buildStateIndicator(status.state, theme),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${status.assignment.adapterName}: '
                      '${status.message ?? 'Waiting…'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: status.state == PresetLineState.failed
                            ? theme.colorScheme.error
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStateIndicator(PresetLineState state, ThemeData theme) {
    return switch (state) {
      PresetLineState.pending => const Padding(
        padding: EdgeInsets.all(2),
        child: CircularProgressIndicator(strokeWidth: 1.5),
      ),
      PresetLineState.applied => const Icon(
        Icons.check_circle,
        size: 16,
        color: _appliedColor,
      ),
      PresetLineState.failed => Icon(
        Icons.cancel,
        size: 16,
        color: theme.colorScheme.error,
      ),
    };
  }
}

Future<void> _openPresetEditor(
  BuildContext context, {
  required NetworkPreset? presetToEdit,
}) async {
  final mainViewModel = context.read<MainViewModel>();
  final savedPreset = await showDialog<NetworkPreset>(
    context: context,
    builder: (_) => ChangeNotifierProvider(
      create: (_) => NetworkPresetEditorViewModel(
        originalPreset: presetToEdit,
        availableAdapterNames: [
          for (final adapter in mainViewModel.adapters) adapter.name,
        ],
        profileNames: [
          for (final profile in mainViewModel.profiles) profile.name,
        ],
        otherPresetNames: mainViewModel.presetNamesOtherThan(presetToEdit),
      ),
      child: const NetworkPresetEditorView(),
    ),
  );
  if (savedPreset == null) return;
  await mainViewModel.savePreset(savedPreset, originalPreset: presetToEdit);
}

Future<void> _confirmAndDeletePreset(
  BuildContext context,
  NetworkPreset preset,
) async {
  final mainViewModel = context.read<MainViewModel>();
  final isConfirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete preset?'),
      content: Text('"${preset.name}" will be removed. Its profiles are kept.'),
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
  if (isConfirmed ?? false) await mainViewModel.deletePreset(preset);
}
