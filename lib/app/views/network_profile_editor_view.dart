import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/addressing_mode.dart';
import '../../core/profiles/network_profile_validator.dart';
import '../view_models/network_profile_editor_view_model.dart';

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
  // Controllers are seeded once from the view model; afterwards the text
  // flows one way, from the fields into the view model.
  late final TextEditingController _nameController;
  late final TextEditingController _ipAddressController;
  late final TextEditingController _subnetMaskController;
  late final TextEditingController _defaultGatewayController;
  late final TextEditingController _preferredDnsController;
  late final TextEditingController _alternateDnsController;

  // One (name, IP) controller pair per ping target row, keyed by draft id so
  // removing a row never shifts text into the wrong fields.
  final Map<int, (TextEditingController, TextEditingController)>
  _pingTargetControllers = {};

  @override
  void initState() {
    super.initState();
    final viewModel = context.read<NetworkProfileEditorViewModel>();
    _nameController = TextEditingController(text: viewModel.name);
    _ipAddressController = TextEditingController(text: viewModel.ipAddress);
    _subnetMaskController = TextEditingController(text: viewModel.subnetMask);
    _defaultGatewayController = TextEditingController(
      text: viewModel.defaultGateway,
    );
    _preferredDnsController = TextEditingController(
      text: viewModel.preferredDnsServer,
    );
    _alternateDnsController = TextEditingController(
      text: viewModel.alternateDnsServer,
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _ipAddressController,
      _subnetMaskController,
      _defaultGatewayController,
      _preferredDnsController,
      _alternateDnsController,
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
              SegmentedButton<AddressingMode>(
                segments: const [
                  ButtonSegment(
                    value: AddressingMode.dhcp,
                    label: Text('DHCP'),
                  ),
                  ButtonSegment(
                    value: AddressingMode.staticIp,
                    label: Text('Static IP'),
                  ),
                ],
                selected: {viewModel.addressingMode},
                onSelectionChanged: (selection) =>
                    viewModel.updateAddressingMode(selection.single),
              ),
              if (viewModel.usesStaticAddress) ..._buildStaticFields(viewModel),
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

  List<Widget> _buildStaticFields(NetworkProfileEditorViewModel viewModel) {
    final dnsError = viewModel.errorFor(NetworkProfileField.dnsServers);
    return [
      const SizedBox(height: 16),
      _buildTextField(
        label: 'IP address',
        hint: '192.168.0.10',
        controller: _ipAddressController,
        onChanged: viewModel.updateIpAddress,
        errorText: viewModel.errorFor(NetworkProfileField.ipAddress),
      ),
      _buildTextField(
        label: 'Subnet mask',
        hint: '255.255.255.0',
        controller: _subnetMaskController,
        onChanged: viewModel.updateSubnetMask,
        errorText: viewModel.errorFor(NetworkProfileField.subnetMask),
      ),
      _buildTextField(
        label: 'Default gateway (optional)',
        controller: _defaultGatewayController,
        onChanged: viewModel.updateDefaultGateway,
        errorText: viewModel.errorFor(NetworkProfileField.defaultGateway),
      ),
      _buildTextField(
        label: 'Preferred DNS server (optional)',
        controller: _preferredDnsController,
        onChanged: viewModel.updatePreferredDnsServer,
      ),
      _buildTextField(
        label: 'Alternate DNS server (optional)',
        controller: _alternateDnsController,
        onChanged: viewModel.updateAlternateDnsServer,
        // Shown once below both DNS fields, since the error can be about
        // either of them or about a duplicate.
        errorText: dnsError,
      ),
    ];
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String? hint,
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
          hintText: hint,
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
