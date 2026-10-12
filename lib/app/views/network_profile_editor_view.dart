import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/profiles/network_profile_validator.dart';
import '../view_models/network_profile_editor_view_model.dart';
import 'collapsible_section.dart';
import 'ipv4_settings_fields.dart';

/// Dialog to create or edit a profile, with inline validation.
///
/// Pops with the saved [NetworkProfile], or with `null` when cancelled.
class NetworkProfileEditorView extends StatefulWidget {
  const NetworkProfileEditorView({
    super.key,
    required this.pluginFolderPath,
    required this.onOpenPluginFolder,
    required this.onBrowseCommandFile,
  });

  /// Shown in the command section, where bare file names are looked up.
  final String pluginFolderPath;
  final VoidCallback onOpenPluginFolder;

  /// Lets the user pick a file for a command; gets the current path and
  /// returns the path to fill in, or `null` when cancelled.
  final Future<String?> Function(String currentCommandPath) onBrowseCommandFile;

  @override
  State<NetworkProfileEditorView> createState() =>
      _NetworkProfileEditorViewState();
}

class _NetworkProfileEditorViewState extends State<NetworkProfileEditorView> {
  // Seeded once from the view model; afterwards the text flows one way, from
  // the field into the view model.
  late final TextEditingController _nameController;

  // One (name, IP) controller pair per ping target row, keyed by draft id so
  // removing a row never shifts text into the wrong fields.
  final Map<int, (TextEditingController, TextEditingController)>
  _pingTargetControllers = {};

  final Map<int, _CommandControllers> _commandControllers = {};

  final Set<_EditorSection> _expandedSections = {};

  @override
  void initState() {
    super.initState();
    final viewModel = context.read<NetworkProfileEditorViewModel>();
    _nameController = TextEditingController(text: viewModel.name);
    _expandedSections.addAll([
      _EditorSection.networkSettings,
      if (viewModel.pingTargetDrafts.isNotEmpty) _EditorSection.pingTargets,
      if (viewModel.commandDrafts.isNotEmpty) _EditorSection.commands,
    ]);
  }

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      for (final (nameController, ipAddressController)
          in _pingTargetControllers.values) ...[
        nameController,
        ipAddressController,
      ],
      for (final controllers in _commandControllers.values) ...controllers.all,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<NetworkProfileEditorViewModel>();
    return AlertDialog(
      title: Text(viewModel.isNewProfile ? 'New profile' : 'Edit profile'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTextField(
                label: 'Name',
                controller: _nameController,
                onChanged: viewModel.updateName,
                errorText: viewModel.errorFor(NetworkProfileField.name),
                autofocus: viewModel.isNewProfile,
              ),
              _buildSection(
                viewModel,
                _EditorSection.networkSettings,
                summary: _summarizeNetworkSettings(viewModel),
                children: const [SizedBox(height: 8), Ipv4SettingsFields()],
              ),
              _buildSection(
                viewModel,
                _EditorSection.pingTargets,
                summary: _countText(
                  viewModel.pingTargetDrafts.length,
                  'ping target',
                ),
                children: _buildPingTargetSection(viewModel),
              ),
              _buildSection(
                viewModel,
                _EditorSection.commands,
                summary: _countText(viewModel.commandDrafts.length, 'command'),
                children: _buildCommandSection(viewModel),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _saveIfValid(viewModel),
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildSection(
    NetworkProfileEditorViewModel viewModel,
    _EditorSection section, {
    required String summary,
    required List<Widget> children,
  }) {
    return CollapsibleSection(
      title: section.title,
      summary: summary,
      isExpanded: _expandedSections.contains(section),
      hasError: _hasError(viewModel, section),
      onToggle: () => setState(() {
        if (!_expandedSections.remove(section)) _expandedSections.add(section);
      }),
      children: children,
    );
  }

  String _summarizeNetworkSettings(NetworkProfileEditorViewModel viewModel) {
    if (!viewModel.usesStaticAddress) return 'DHCP';
    final ipAddress = viewModel.ipAddress.trim();
    if (ipAddress.isEmpty) return 'Static';
    return 'Static · $ipAddress / ${viewModel.subnetMask.trim()}';
  }

  static String _countText(int count, String noun) =>
      count == 1 ? '1 $noun' : '${count == 0 ? 'No' : count} ${noun}s';

  bool _hasError(
    NetworkProfileEditorViewModel viewModel,
    _EditorSection section,
  ) => section.fields.any((field) => viewModel.errorFor(field) != null);

  List<Widget> _buildPingTargetSection(
    NetworkProfileEditorViewModel viewModel,
  ) {
    final drafts = viewModel.pingTargetDrafts;
    _disposeControllersOfRemovedDrafts(drafts);
    final pingTargetError = viewModel.errorFor(NetworkProfileField.pingTargets);
    return [
      Text(
        'Pinged automatically after applying this profile.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      for (final draft in drafts) _buildPingTargetRow(viewModel, draft),
      if (pingTargetError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            pingTargetError,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: viewModel.addPingTarget,
          icon: const Icon(Icons.add),
          label: const Text('Add ping target'),
        ),
      ),
    ];
  }

  Widget _buildPingTargetRow(
    NetworkProfileEditorViewModel viewModel,
    PingTargetDraft draft,
  ) {
    final (nameController, ipAddressController) = _pingTargetControllers
        .putIfAbsent(
          draft.id,
          () => (
            TextEditingController(text: draft.name),
            TextEditingController(text: draft.ipAddress),
          ),
        );
    return Padding(
      key: ValueKey(draft.id),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: nameController,
              onChanged: (name) =>
                  viewModel.updatePingTargetName(draft.id, name),
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'PLC',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: ipAddressController,
              onChanged: (ipAddress) =>
                  viewModel.updatePingTargetIpAddress(draft.id, ipAddress),
              decoration: const InputDecoration(
                labelText: 'IP address',
                hintText: '10.100.10.1',
                isDense: true,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove ping target',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => viewModel.removePingTarget(draft.id),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCommandSection(NetworkProfileEditorViewModel viewModel) {
    final theme = Theme.of(context);
    final drafts = viewModel.commandDrafts;
    _disposeControllersOfRemovedCommands(drafts);
    final commandError = viewModel.errorFor(NetworkProfileField.commands);
    return [
      Text(
        'Programs or scripts (.exe, .ps1, .bat, .cmd) run one after another '
        'once the ping targets were checked. A file name without a folder is '
        'looked up in the plugin folder:',
        style: theme.textTheme.bodySmall,
      ),
      Row(
        children: [
          Expanded(
            child: SelectableText(
              widget.pluginFolderPath,
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton.icon(
            onPressed: widget.onOpenPluginFolder,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Open'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      for (final draft in drafts) _buildCommandRow(viewModel, draft),
      if (commandError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            commandError,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: viewModel.addCommand,
          icon: const Icon(Icons.add),
          label: const Text('Add command'),
        ),
      ),
    ];
  }

  Widget _buildCommandRow(
    NetworkProfileEditorViewModel viewModel,
    CommandDraft draft,
  ) {
    final controllers = _commandControllers.putIfAbsent(
      draft.id,
      () => _CommandControllers(draft),
    );
    return Container(
      key: ValueKey('command-${draft.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: controllers.name,
                  onChanged: (name) =>
                      viewModel.updateCommandName(draft.id, name),
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: 'Map drive',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: controllers.path,
                  onChanged: (path) =>
                      viewModel.updateCommandPath(draft.id, path),
                  decoration: const InputDecoration(
                    labelText: 'File',
                    hintText: r'map_drive.ps1 or C:\Tools\tool.exe',
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Browse for a file',
                icon: const Icon(Icons.folder_open_outlined),
                onPressed: () => _browseCommandFile(viewModel, draft.id),
              ),
              IconButton(
                tooltip: 'Remove command',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => viewModel.removeCommand(draft.id),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextField(
              controller: controllers.arguments,
              onChanged: (argumentsText) =>
                  viewModel.updateCommandArguments(draft.id, argumentsText),
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Arguments (optional)',
                hintText: r'-Address 10.0.0.1 -Path "C:\My Files"',
                isDense: true,
              ),
            ),
          ),
          CheckboxListTile(
            value: draft.runAfterApply,
            onChanged: (runAfterApply) => viewModel.updateCommandRunAfterApply(
              draft.id,
              runAfterApply ?? false,
            ),
            title: const Text('Run after applying this profile'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
    );
  }

  Future<void> _browseCommandFile(
    NetworkProfileEditorViewModel viewModel,
    int draftId,
  ) async {
    final pathController = _commandControllers[draftId]!.path;
    final selectedPath = await widget.onBrowseCommandFile(pathController.text);
    if (selectedPath == null || !mounted) return;
    pathController.text = selectedPath;
    viewModel.updateCommandPath(draftId, selectedPath);
  }

  void _disposeControllersOfRemovedCommands(List<CommandDraft> drafts) {
    final remainingIds = {for (final draft in drafts) draft.id};
    final removedIds = _commandControllers.keys
        .where((id) => !remainingIds.contains(id))
        .toList();
    for (final removedId in removedIds) {
      final controllers = _commandControllers.remove(removedId)!;
      // The removed row's TextFields are still mounted during this build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final controller in controllers.all) {
          controller.dispose();
        }
      });
    }
  }

  void _disposeControllersOfRemovedDrafts(List<PingTargetDraft> drafts) {
    final remainingIds = {for (final draft in drafts) draft.id};
    final removedIds = _pingTargetControllers.keys
        .where((id) => !remainingIds.contains(id))
        .toList();
    for (final removedId in removedIds) {
      final (nameController, ipAddressController) = _pingTargetControllers
          .remove(removedId)!;
      // The removed row's TextFields are still mounted during this build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameController.dispose();
        ipAddressController.dispose();
      });
    }
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String? errorText,
    bool autofocus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autofocus: autofocus,
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          errorMaxLines: 3,
        ),
      ),
    );
  }

  void _saveIfValid(NetworkProfileEditorViewModel viewModel) {
    final savedProfile = viewModel.trySave();
    if (savedProfile != null) {
      Navigator.pop(context, savedProfile);
      return;
    }
    // Errors in a folded section would otherwise go unnoticed.
    setState(() {
      _expandedSections.addAll(
        _EditorSection.values.where((section) => _hasError(viewModel, section)),
      );
    });
  }
}

enum _EditorSection {
  networkSettings('Network settings', [
    NetworkProfileField.ipAddress,
    NetworkProfileField.subnetMask,
    NetworkProfileField.defaultGateway,
    NetworkProfileField.dnsServers,
  ]),
  pingTargets('Ping targets', [NetworkProfileField.pingTargets]),
  commands('Commands', [NetworkProfileField.commands]);

  const _EditorSection(this.title, this.fields);

  final String title;
  final List<NetworkProfileField> fields;
}

/// The text fields of one command row, created once from its draft.
class _CommandControllers {
  _CommandControllers(CommandDraft draft)
    : name = TextEditingController(text: draft.name),
      path = TextEditingController(text: draft.path),
      arguments = TextEditingController(text: draft.argumentsText);

  final TextEditingController name;
  final TextEditingController path;
  final TextEditingController arguments;

  List<TextEditingController> get all => [name, path, arguments];
}
