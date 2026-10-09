import 'package:flutter/material.dart';

import '../view_models/main_view_model.dart';

/// What the user chose in [ImportUserDataView].
class ImportUserDataChoice {
  const ImportUserDataChoice({
    required this.mode,
    required this.newAdapterNamesByImportedName,
  });

  final LibraryImportMode mode;

  /// Only adapters the user mapped; unmapped ones keep their name.
  final Map<String, String> newAdapterNamesByImportedName;
}

/// Confirms importing a shared file: merge or replace, and for every preset
/// adapter this PC does not have, which local adapter to use instead.
///
/// Pops with a [ImportUserDataChoice], or with `null` when cancelled.
class ImportUserDataView extends StatefulWidget {
  const ImportUserDataView({
    super.key,
    required this.libraryImport,
    required this.localAdapterNames,
  });

  final LibraryImport libraryImport;
  final List<String> localAdapterNames;

  @override
  State<ImportUserDataView> createState() => _ImportUserDataViewState();
}

class _ImportUserDataViewState extends State<ImportUserDataView> {
  // Merge is the default: it can never lose data, replace can.
  LibraryImportMode _mode = LibraryImportMode.merge;
  final Map<String, String> _newAdapterNamesByImportedName = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final importedLibrary = widget.libraryImport.library;
    return AlertDialog(
      title: const Text('Import user data'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.libraryImport.filePath}\n'
                '${importedLibrary.profiles.length} profiles, '
                '${importedLibrary.presets.length} presets',
                style: theme.textTheme.bodySmall,
              ),
              if (widget.libraryImport.commands.isNotEmpty)
                ..._buildCommandWarning(theme),
              const SizedBox(height: 16),
              RadioGroup<LibraryImportMode>(
                groupValue: _mode,
                onChanged: (mode) => setState(() => _mode = mode!),
                child: const Column(
                  children: [
                    RadioListTile(
                      value: LibraryImportMode.merge,
                      title: Text('Add to my data'),
                      subtitle: Text(
                        'Existing names are kept; imported items with the same '
                        'name get "(imported)" added.',
                      ),
                    ),
                    RadioListTile(
                      value: LibraryImportMode.replace,
                      title: Text('Replace my data'),
                      subtitle: Text(
                        'A backup of your current data is saved first.',
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.libraryImport.unknownAdapterNames.isNotEmpty)
                ..._buildAdapterMapping(theme),
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
          onPressed: () => Navigator.pop(
            context,
            ImportUserDataChoice(
              mode: _mode,
              newAdapterNamesByImportedName: Map.of(
                _newAdapterNamesByImportedName,
              ),
            ),
          ),
          child: const Text('Import'),
        ),
      ],
    );
  }

  // Commands run with the app's administrator rights, so a file from someone
  // else could run anything on this PC. Only a warning: the user decided
  // against blocking imported commands.
  List<Widget> _buildCommandWarning(ThemeData theme) {
    final errorColor = theme.colorScheme.error;
    return [
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: errorColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: errorColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This file contains commands',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: errorColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'They run programs on this PC with administrator rights. Only '
              'import files from people you trust.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final (profileName, command) in widget.libraryImport.commands)
              Text(
                '$profileName: ${[command.path, ...command.arguments].join(' ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'Consolas',
                ),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildAdapterMapping(ThemeData theme) {
    return [
      const SizedBox(height: 16),
      Text(
        'Adapters in this file that do not exist on this PC',
        style: theme.textTheme.titleSmall,
      ),
      Text(
        'Choose which adapter to use instead, or keep the name (e.g. for a '
        'USB adapter that is not plugged in).',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      for (final importedName in widget.libraryImport.unknownAdapterNames)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(child: Text(importedName)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward),
              ),
              Expanded(child: _buildAdapterChoice(importedName)),
            ],
          ),
        ),
    ];
  }

  Widget _buildAdapterChoice(String importedName) {
    return DropdownButtonFormField<String?>(
      initialValue: _newAdapterNamesByImportedName[importedName],
      isExpanded: true,
      decoration: const InputDecoration(isDense: true),
      items: [
        const DropdownMenuItem(value: null, child: Text('Keep as is')),
        for (final localAdapterName in widget.localAdapterNames)
          DropdownMenuItem(
            value: localAdapterName,
            child: Text(localAdapterName, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (localAdapterName) => setState(() {
        if (localAdapterName == null) {
          _newAdapterNamesByImportedName.remove(importedName);
        } else {
          _newAdapterNamesByImportedName[importedName] = localAdapterName;
        }
      }),
    );
  }
}
