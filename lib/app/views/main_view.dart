import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/addressing_mode.dart';
import '../../core/models/network_preset.dart';
import '../../core/models/network_profile.dart';
import '../../core/models/ping_target.dart';
import '../view_models/main_view_model.dart';
import '../view_models/network_adapter_view_model.dart';
import '../view_models/network_preset_editor_view_model.dart';
import '../view_models/network_profile_editor_view_model.dart';
import 'adapter_card.dart';
import 'adapter_settings_view.dart';
import 'apply_arrow_button.dart';
import 'card_colors.dart';
import 'collapsible_section.dart';
import 'help_view.dart';
import 'import_user_data_view.dart';
import 'label_and_result.dart';
import 'network_preset_editor_view.dart';
import 'network_profile_editor_view.dart';

/// Main window: adapters on the left; profiles (top) and presets (bottom) on
/// the right; the apply action and the status line at the bottom. Opens the
/// help by itself on the very first start.
class MainView extends StatefulWidget {
  const MainView({super.key});

  @override
  State<MainView> createState() => _MainViewState();
}

class _MainViewState extends State<MainView> {
  late final MainViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = context.read<MainViewModel>();
    _viewModel.addListener(_showHelpOnFirstStart);
    // The data may already have loaded before this view was built.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showHelpOnFirstStart(),
    );
  }

  @override
  void dispose() {
    _viewModel.removeListener(_showHelpOnFirstStart);
    super.dispose();
  }

  // Runs whenever the view model changes; does something only once, after
  // the stored data has loaded and says the help was never shown.
  void _showHelpOnFirstStart() {
    if (!mounted || !_viewModel.shouldShowHelpOnStart) return;
    unawaited(_viewModel.markHelpAsShown());
    // Not from inside the listener call: open after the current frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_showHelp(context));
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MainViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Adapter Tool'),
        actions: [
          TextButton.icon(
            onPressed: viewModel.canTransferUserData
                ? () => _importUserData(context)
                : null,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Import'),
          ),
          TextButton.icon(
            onPressed: viewModel.canTransferUserData
                ? () => _exportUserData(context)
                : null,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Export'),
          ),
          TextButton.icon(
            onPressed: () => _showHelp(context),
            icon: const Icon(Icons.help_outline),
            label: const Text('Help'),
          ),
          const SizedBox(width: 8),
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
        _PanelHeader(
          title: 'Adapters',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Double-clicking is not visible on the cards, so it is
              // explained here.
              const Tooltip(
                message:
                    'Double-click an adapter to change its settings directly',
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.info_outline, size: 20),
                ),
              ),
              IconButton(
                tooltip: 'Refresh adapters',
                icon: const Icon(Icons.refresh),
                onPressed: viewModel.isLoadingAdapters || viewModel.isApplying
                    ? null
                    : viewModel.refreshAdapters,
              ),
            ],
          ),
        ),
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
                  child: AdapterCard(
                    adapter: adapter,
                    isSelected: adapter.name == viewModel.selectedAdapterName,
                    onTap: () => viewModel.selectAdapter(adapter.name),
                    onDoubleTap: viewModel.canConfigureAdapters
                        ? () => _openAdapterSettings(context, adapter)
                        : null,
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
                        key: ValueKey(profile.name),
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

class _ProfileTile extends StatefulWidget {
  const _ProfileTile({
    super.key,
    required this.profile,
    required this.isSelected,
    required this.canEdit,
  });

  final NetworkProfile profile;
  final bool isSelected;
  final bool canEdit;

  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile> {
  // Folded by default to keep the list short; the folded header still shows
  // a summary of the results.
  bool _pingTargetsAreExpanded = false;
  bool _commandsAreExpanded = false;

  NetworkProfile get _profile => widget.profile;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MainViewModel>();
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: CardColors.profile(
        theme.brightness,
        isSelected: widget.isSelected,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: widget.isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, viewModel),
          if (_profile.pingTargets.isNotEmpty)
            _buildPingTargetSection(viewModel),
          if (_profile.commands.isNotEmpty) _buildCommandSection(viewModel),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, MainViewModel viewModel) {
    return ListTile(
      onTap: () => viewModel.selectProfile(_profile.name),
      title: Text(_profile.name),
      subtitle: Text(_describeProfile(_profile)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: widget.canEdit
                ? () => _openProfileEditor(context, profileToEdit: _profile)
                : null,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: widget.canEdit
                ? () => _confirmAndDeleteProfile(context, _profile)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildPingTargetSection(MainViewModel viewModel) {
    return _ProfileCardSection(
      title: 'Ping targets',
      summary: _summarizePingResults(viewModel),
      isExpanded: _pingTargetsAreExpanded,
      onToggle: () =>
          setState(() => _pingTargetsAreExpanded = !_pingTargetsAreExpanded),
      headerAction: _CompactButton(
        label: 'Ping all',
        isBusy: viewModel.isPinging(_profile.name),
        onPressed: viewModel.canPingProfile(_profile)
            ? () {
                setState(() => _pingTargetsAreExpanded = true);
                viewModel.pingTargetsOf(_profile);
              }
            : null,
      ),
      children: [
        for (final target in _profile.pingTargets)
          _PingTargetRow(profile: _profile, target: target),
      ],
    );
  }

  // While commands run the header button stops them, so a program that never
  // exits can always be ended from the app.
  Widget _buildCommandSection(MainViewModel viewModel) {
    final isRunning = viewModel.isRunningCommands(_profile.name);
    return _ProfileCardSection(
      title: 'Commands',
      summary: _summarizeCommandResults(viewModel),
      isExpanded: _commandsAreExpanded,
      onToggle: () =>
          setState(() => _commandsAreExpanded = !_commandsAreExpanded),
      headerAction: isRunning
          ? _CompactButton(
              label: 'Stop',
              icon: Icons.stop,
              onPressed: viewModel.canStopCommands(_profile.name)
                  ? () => viewModel.stopCommandsOf(_profile.name)
                  : null,
            )
          : _CompactButton(
              label: 'Run all',
              onPressed: viewModel.canRunCommands(_profile)
                  ? () {
                      setState(() => _commandsAreExpanded = true);
                      viewModel.runCommandsOf(_profile);
                    }
                  : null,
            ),
      children: [
        for (var index = 0; index < _profile.commands.length; index++)
          _CommandRow(profile: _profile, commandIndex: index),
      ],
    );
  }

  String _summarizePingResults(MainViewModel viewModel) {
    if (viewModel.isPinging(_profile.name)) return 'Pinging…';
    final statuses = viewModel.pingStatusesFor(_profile.name);
    if (statuses == null) {
      return _counted(_profile.pingTargets.length, 'target');
    }
    final replyCount = statuses
        .where((status) => status.state == PingState.reachable)
        .length;
    return '$replyCount of ${statuses.length} replied';
  }

  String _summarizeCommandResults(MainViewModel viewModel) {
    if (viewModel.isRunningCommands(_profile.name)) return 'Running…';
    final statuses = viewModel.commandStatusesFor(_profile.name);
    if (statuses == null) return _counted(_profile.commands.length, 'command');
    final ranStatuses = statuses.where(
      (status) => status.state != CommandState.skipped,
    );
    final succeededCount = ranStatuses
        .where((status) => status.state == CommandState.succeeded)
        .length;
    return '$succeededCount of ${ranStatuses.length} succeeded';
  }

  String _describeProfile(NetworkProfile profile) {
    final addressing = profile.addressingMode == AddressingMode.dhcp
        ? 'DHCP'
        : '${profile.ipAddress} / ${profile.subnetMask}';
    return [
      addressing,
      if (profile.pingTargets.isNotEmpty)
        _counted(profile.pingTargets.length, 'ping target'),
      if (profile.commands.isNotEmpty)
        _counted(profile.commands.length, 'command'),
    ].join(' · ');
  }

  static String _counted(int count, String noun) =>
      '$count $noun${count == 1 ? '' : 's'}';
}

/// A foldable part of a profile card (ping targets or commands), with the
/// "all" button in its header.
class _ProfileCardSection extends StatelessWidget {
  const _ProfileCardSection({
    required this.title,
    required this.summary,
    required this.isExpanded,
    required this.onToggle,
    required this.headerAction,
    required this.children,
  });

  final String title;
  final String summary;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget headerAction;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CollapsibleSection(
      title: title,
      summary: summary,
      isExpanded: isExpanded,
      onToggle: onToggle,
      headerAction: headerAction,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      children: children,
    );
  }
}

/// A small outlined button for card headers, with a spinner while [isBusy].
class _CompactButton extends StatelessWidget {
  const _CompactButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isBusy = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isBusy;

  /// Tells rows apart, e.g. "Ping 10.100.10.1" on each target's Ping button.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final leading = isBusy
        ? const SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : icon == null
        ? null
        : Icon(icon, size: 16);
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 8)],
          Text(label),
        ],
      ),
    );
    final buttonTooltip = tooltip;
    return buttonTooltip == null
        ? button
        : Tooltip(message: buttonTooltip, child: button);
  }
}

/// One ping target in a profile card: its state, name, last result and a
/// button to ping only this target (left out in the preset card, which
/// repeats the results).
class _PingTargetRow extends StatelessWidget {
  const _PingTargetRow({
    required this.profile,
    required this.target,
    this.showPingButton = true,
  });

  static const _reachableColor = Color(0xFF2E7D32);

  final NetworkProfile profile;
  final PingTarget target;
  final bool showPingButton;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MainViewModel>();
    final theme = Theme.of(context);
    final status = viewModel.pingStatusOf(profile.name, target);
    final resultStyle = theme.textTheme.bodySmall?.copyWith(
      color: _resultColor(status?.state, theme),
    );
    return _CardItemRow(
      indicator: _buildStateIndicator(status?.state, theme),
      label: _describeTarget(target),
      result: Text(
        status?.resultText ?? '',
        style: resultStyle,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        if (showPingButton)
          _CompactButton(
            label: 'Ping',
            tooltip: 'Ping ${target.ipAddress}',
            onPressed: viewModel.canPingTarget(profile, target)
                ? () => viewModel.pingTarget(profile, target)
                : null,
          ),
      ],
    );
  }

  Widget _buildStateIndicator(PingState? state, ThemeData theme) {
    return switch (state) {
      null => Icon(
        Icons.circle_outlined,
        size: 10,
        color: theme.colorScheme.outline,
      ),
      PingState.pinging => const SizedBox.square(
        dimension: 10,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      ),
      _ => Icon(Icons.circle, size: 10, color: _resultColor(state, theme)),
    };
  }

  Color _resultColor(PingState? state, ThemeData theme) => switch (state) {
    PingState.reachable => _reachableColor,
    PingState.unreachable => theme.colorScheme.error,
    _ => theme.colorScheme.outline,
  };

  String _describeTarget(PingTarget target) =>
      target.name == null || target.name!.trim().isEmpty
      ? target.ipAddress
      : '${target.name} · ${target.ipAddress}';
}

/// One command in a profile card: its state, name, running time or result,
/// a button for its output and a button to run only this command.
class _CommandRow extends StatelessWidget {
  const _CommandRow({required this.profile, required this.commandIndex});

  static const _succeededColor = Color(0xFF2E7D32);

  final NetworkProfile profile;
  final int commandIndex;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MainViewModel>();
    final theme = Theme.of(context);
    final command = profile.commands[commandIndex];
    final status = viewModel.commandStatusOf(profile.name, commandIndex);
    return _CardItemRow(
      indicator: _buildStateIndicator(status?.state, theme),
      label: command.displayName,
      result: _buildResultText(status, theme),
      actions: [
        if (status != null && status.output.trim().isNotEmpty)
          IconButton(
            tooltip: 'Show output',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.article_outlined),
            onPressed: () => _showOutput(context, status),
          ),
        _CompactButton(
          label: 'Run',
          tooltip: 'Run ${command.displayName}',
          onPressed: viewModel.canRunCommand(profile)
              ? () => viewModel.runCommand(profile, commandIndex)
              : null,
        ),
      ],
    );
  }

  Widget _buildResultText(CommandStatus? status, ThemeData theme) {
    final style = theme.textTheme.bodySmall?.copyWith(
      color: _resultColor(status?.state, theme),
    );
    final startedAt = status?.startedAt;
    if (status?.state == CommandState.running && startedAt != null) {
      return _ElapsedTimeText(startedAt: startedAt, style: style);
    }
    return Text(
      status?.resultText ?? '',
      style: style,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildStateIndicator(CommandState? state, ThemeData theme) {
    return switch (state) {
      CommandState.running => const SizedBox.square(
        dimension: 10,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      ),
      null || CommandState.waiting || CommandState.skipped => Icon(
        Icons.circle_outlined,
        size: 10,
        color: theme.colorScheme.outline,
      ),
      _ => Icon(Icons.circle, size: 10, color: _resultColor(state, theme)),
    };
  }

  Color _resultColor(CommandState? state, ThemeData theme) => switch (state) {
    CommandState.succeeded => _succeededColor,
    CommandState.failed || CommandState.stopped => theme.colorScheme.error,
    _ => theme.colorScheme.outline,
  };

  Future<void> _showOutput(BuildContext context, CommandStatus status) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Output of ${status.command.displayName}'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: SelectableText(
              status.output,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Shared layout of a ping target or command row in a profile card.
class _CardItemRow extends StatelessWidget {
  const _CardItemRow({
    required this.indicator,
    required this.label,
    required this.result,
    required this.actions,
  });

  final Widget indicator;
  final String label;
  final Widget result;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          indicator,
          const SizedBox(width: 8),
          Expanded(
            child: LabelAndResult(
              label: label,
              labelStyle: Theme.of(context).textTheme.bodySmall,
              result: result,
            ),
          ),
          const SizedBox(width: 4),
          ...actions,
          const SizedBox(
            width: CollapsibleSection.endInsetToAlignWithHeaderAction,
          ),
        ],
      ),
    );
  }
}

/// "Running · 12 s", updated every second while a command runs.
class _ElapsedTimeText extends StatefulWidget {
  const _ElapsedTimeText({required this.startedAt, this.style});

  final DateTime startedAt;
  final TextStyle? style;

  @override
  State<_ElapsedTimeText> createState() => _ElapsedTimeTextState();
}

class _ElapsedTimeTextState extends State<_ElapsedTimeText> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.startedAt);
    return Text('Running · ${describeDuration(elapsed)}', style: widget.style);
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
            child: ApplyArrowButton(
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
            // Room for the last lines a command wrote.
            maxLines: 5,
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

Future<void> _showHelp(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const HelpView());
}

const _userDataFileTypes = [
  XTypeGroup(label: 'Network Adapter Tool data', extensions: ['json']),
];

Future<void> _exportUserData(BuildContext context) async {
  final mainViewModel = context.read<MainViewModel>();
  final saveLocation = await getSaveLocation(
    acceptedTypeGroups: _userDataFileTypes,
    suggestedName: 'network_adapter_tool_data.json',
  );
  if (saveLocation == null) return;
  final filePath = saveLocation.path.toLowerCase().endsWith('.json')
      ? saveLocation.path
      : '${saveLocation.path}.json';
  await mainViewModel.exportUserData(filePath);
}

Future<void> _importUserData(BuildContext context) async {
  final mainViewModel = context.read<MainViewModel>();
  final file = await openFile(acceptedTypeGroups: _userDataFileTypes);
  if (file == null) return;
  final libraryImport = await mainViewModel.prepareImport(file.path);
  if (libraryImport == null || !context.mounted) return;
  final choice = await showDialog<ImportUserDataChoice>(
    context: context,
    builder: (_) => ImportUserDataView(
      libraryImport: libraryImport,
      localAdapterNames: [
        for (final adapter in mainViewModel.adapters) adapter.name,
      ],
    ),
  );
  if (choice == null) return;
  await mainViewModel.completeImport(
    libraryImport,
    mode: choice.mode,
    newAdapterNamesByImportedName: choice.newAdapterNamesByImportedName,
  );
}

Future<void> _openAdapterSettings(
  BuildContext context,
  NetworkAdapterViewModel adapter,
) async {
  final mainViewModel = context.read<MainViewModel>();
  final settings = await showDialog<NetworkProfile>(
    context: context,
    builder: (_) => ChangeNotifierProvider(
      create: (_) => NetworkProfileEditorViewModel(
        originalProfile: mainViewModel.currentSettingsOf(adapter.adapter),
        otherProfileNames: const [],
      ),
      child: AdapterSettingsView(adapter: adapter),
    ),
  );
  if (settings == null) return;
  await mainViewModel.applyManualSettings(settings, adapter.name);
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
      child: NetworkProfileEditorView(
        pluginFolderPath: mainViewModel.pluginFolderPath,
        onOpenPluginFolder: mainViewModel.openPluginFolder,
        onBrowseCommandFile: (currentCommandPath) =>
            _browseCommandFile(mainViewModel, currentCommandPath),
      ),
    ),
  );
  if (savedProfile == null) return;
  await mainViewModel.saveProfile(savedProfile, originalProfile: profileToEdit);
}

const _commandFileTypes = [
  XTypeGroup(
    label: 'Programs and scripts',
    extensions: ['exe', 'ps1', 'bat', 'cmd'],
  ),
];

Future<String?> _browseCommandFile(
  MainViewModel mainViewModel,
  String currentCommandPath,
) async {
  final file = await openFile(
    acceptedTypeGroups: _commandFileTypes,
    initialDirectory: mainViewModel.folderToBrowseFrom(currentCommandPath),
  );
  if (file == null) return null;
  return mainViewModel.commandPathFor(file.path);
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

  final NetworkPreset preset;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MainViewModel>();
    final theme = Theme.of(context);
    final lineStatuses = viewModel.lineStatusesFor(preset.name);
    return Card(
      elevation: 0,
      color: CardColors.preset(theme.brightness),
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
          ..._buildMissingAdapterWarnings(theme, viewModel),
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

  // A preset loaded from another PC may name adapters this PC lacks; warn
  // before applying instead of only failing per line afterwards.
  List<Widget> _buildMissingAdapterWarnings(
    ThemeData theme,
    MainViewModel viewModel,
  ) {
    return [
      for (final adapterName in viewModel.missingAdaptersOf(preset))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$adapterName not found on this PC',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: [
                for (final status in statuses)
                  _PingTargetRow(
                    profile: profile,
                    target: status.target,
                    showPingButton: false,
                  ),
              ],
            ),
          ),
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
