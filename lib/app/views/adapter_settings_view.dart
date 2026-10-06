import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../view_models/network_adapter_view_model.dart';
import '../view_models/network_profile_editor_view_model.dart';
import 'ipv4_settings_fields.dart';

/// Dialog opened by double-clicking an adapter: change its IPv4 settings
/// directly, without creating a profile.
///
/// Expects a [NetworkProfileEditorViewModel] seeded with the adapter's
/// current settings; pops with the entered settings as an unsaved
/// [NetworkProfile], or with `null` when cancelled.
class AdapterSettingsView extends StatelessWidget {
  const AdapterSettingsView({super.key, required this.adapter});

  final NetworkAdapterViewModel adapter;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<NetworkProfileEditorViewModel>();
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Configure ${adapter.name}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Now: ${adapter.addressingModeText} · ${adapter.addressText} · '
                '${adapter.statusText}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Applied directly; not saved as a profile.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 16),
              const Ipv4SettingsFields(),
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
          onPressed: () {
            final settings = viewModel.trySave();
            if (settings != null) Navigator.pop(context, settings);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
