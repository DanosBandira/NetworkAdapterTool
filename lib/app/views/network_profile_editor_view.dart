import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/profiles/network_profile_validator.dart';
import '../view_models/network_profile_editor_view_model.dart';
import 'ipv4_settings_fields.dart';

/// Dialog to create or edit a profile, with inline validation.
///
/// Pops with the saved [NetworkProfile], or with `null` when cancelled.
class NetworkProfileEditorView extends StatefulWidget {
  const NetworkProfileEditorView({super.key});

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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: context.read<NetworkProfileEditorViewModel>().name,
    );
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
        width: 420,
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
              const SizedBox(height: 16),
              const Ipv4SettingsFields(),
              ..._buildPingTargetSection(viewModel),
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

  List<Widget> _buildPingTargetSection(
    NetworkProfileEditorViewModel viewModel,
  ) {
    final drafts = viewModel.pingTargetDrafts;
    _disposeControllersOfRemovedDrafts(drafts);
    final pingTargetError = viewModel.errorFor(NetworkProfileField.pingTargets);
    return [
      const SizedBox(height: 16),
      Text('Ping targets', style: Theme.of(context).textTheme.titleSmall),
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
    if (savedProfile != null) Navigator.pop(context, savedProfile);
  }
}
