import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/profiles/network_preset_validator.dart';
import '../view_models/network_preset_editor_view_model.dart';

/// Dialog to create or edit a preset: a name and one line per adapter with
/// the profile it should get.
///
/// Pops with the saved [NetworkPreset], or with `null` when cancelled.
class NetworkPresetEditorView extends StatefulWidget {
  const NetworkPresetEditorView({super.key});

  @override
  State<NetworkPresetEditorView> createState() =>
      _NetworkPresetEditorViewState();
}

class _NetworkPresetEditorViewState extends State<NetworkPresetEditorView> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: context.read<NetworkPresetEditorViewModel>().name,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<NetworkPresetEditorViewModel>();
    final assignmentError = viewModel.errorFor(NetworkPresetField.assignments);
    return AlertDialog(
      title: Text(viewModel.isNewPreset ? 'New preset' : 'Edit preset'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                onChanged: viewModel.updateName,
                autofocus: viewModel.isNewPreset,
                decoration: InputDecoration(
                  labelText: 'Name',
                  errorText: viewModel.errorFor(NetworkPresetField.name),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Adapters and profiles',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final line in viewModel.lines) _buildLine(viewModel, line),
              if (assignmentError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    assignmentError,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: viewModel.addLine,
                  icon: const Icon(Icons.add),
                  label: const Text('Add adapter'),
                ),
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

  Widget _buildLine(
    NetworkPresetEditorViewModel viewModel,
    PresetLineDraft line,
  ) {
    return Padding(
      key: ValueKey(line.id),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: _buildDropdown(
              label: 'Adapter',
              value: line.adapterName,
              options: viewModel.adapterNames,
              onChanged: (adapterName) =>
                  viewModel.updateLineAdapter(line.id, adapterName),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_back),
          ),
          Expanded(
            child: _buildDropdown(
              label: 'Profile',
              value: line.profileName,
              options: viewModel.profileNames,
              onChanged: (profileName) =>
                  viewModel.updateLineProfile(line.id, profileName),
            ),
          ),
          IconButton(
            tooltip: 'Remove line',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => viewModel.removeLine(line.id),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: options.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option,
            child: Text(option, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
    );
  }

  void _saveIfValid(NetworkPresetEditorViewModel viewModel) {
    final savedPreset = viewModel.trySave();
    if (savedPreset != null) Navigator.pop(context, savedPreset);
  }
}
