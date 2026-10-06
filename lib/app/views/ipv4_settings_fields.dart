import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/addressing_mode.dart';
import '../../core/profiles/network_profile_validator.dart';
import '../view_models/network_profile_editor_view_model.dart';

/// The DHCP / static choice with IP, subnet mask, gateway and DNS fields,
/// including inline validation. Shared by the profile editor and the adapter
/// settings dialog; reads the [NetworkProfileEditorViewModel] provided above.
class Ipv4SettingsFields extends StatefulWidget {
  const Ipv4SettingsFields({super.key});

  @override
  State<Ipv4SettingsFields> createState() => _Ipv4SettingsFieldsState();
}

class _Ipv4SettingsFieldsState extends State<Ipv4SettingsFields> {
  // Controllers are seeded once from the view model; afterwards the text
  // flows one way, from the fields into the view model.
  late final TextEditingController _ipAddressController;
  late final TextEditingController _subnetMaskController;
  late final TextEditingController _defaultGatewayController;
  late final TextEditingController _preferredDnsController;
  late final TextEditingController _alternateDnsController;

  @override
  void initState() {
    super.initState();
    final viewModel = context.read<NetworkProfileEditorViewModel>();
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
      _ipAddressController,
      _subnetMaskController,
      _defaultGatewayController,
      _preferredDnsController,
      _alternateDnsController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<NetworkProfileEditorViewModel>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<AddressingMode>(
          segments: const [
            ButtonSegment(value: AddressingMode.dhcp, label: Text('DHCP')),
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
      ],
    );
  }

  List<Widget> _buildStaticFields(NetworkProfileEditorViewModel viewModel) {
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
        errorText: viewModel.errorFor(NetworkProfileField.dnsServers),
      ),
    ];
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String? hint,
    String? errorText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: errorText,
          errorMaxLines: 3,
        ),
      ),
    );
  }
}
