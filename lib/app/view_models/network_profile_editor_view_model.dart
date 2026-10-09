import 'package:flutter/foundation.dart';

import '../../core/commands/command_line_arguments.dart';
import '../../core/models/addressing_mode.dart';
import '../../core/models/network_profile.dart';
import '../../core/models/ping_target.dart';
import '../../core/models/profile_command.dart';
import '../../core/profiles/network_profile_validator.dart';

/// State of the profile editor dialog: the text of each field and the inline
/// validation messages.
///
/// A field shows its error only after the user edited it or tried to save,
/// so a fresh form does not open full of red text.
class NetworkProfileEditorViewModel extends ChangeNotifier {
  NetworkProfileEditorViewModel({
    required this.originalProfile,
    required this._otherProfileNames,
    this._validator = const NetworkProfileValidator(),
  }) : _name = originalProfile?.name ?? '',
       _addressingMode =
           originalProfile?.addressingMode ?? AddressingMode.staticIp,
       _ipAddress = originalProfile?.ipAddress ?? '',
       _subnetMask = originalProfile?.subnetMask ?? '255.255.255.0',
       _defaultGateway = originalProfile?.defaultGateway ?? '',
       _preferredDnsServer = _dnsServerAt(originalProfile, 0),
       _alternateDnsServer = _dnsServerAt(originalProfile, 1),
       _furtherDnsServers = originalProfile?.dnsServers.skip(2).toList() ?? [] {
    for (final pingTarget in originalProfile?.pingTargets ?? <PingTarget>[]) {
      _pingTargetDrafts.add(
        PingTargetDraft._(
          _nextPingTargetDraftId++,
          name: pingTarget.name ?? '',
          ipAddress: pingTarget.ipAddress,
        ),
      );
    }
    for (final command in originalProfile?.commands ?? <ProfileCommand>[]) {
      _commandDrafts.add(
        CommandDraft._(
          _nextCommandDraftId++,
          name: command.name ?? '',
          path: command.path,
          argumentsText: CommandLineArguments.join(command.arguments),
          runAfterApply: command.runAfterApply,
        ),
      );
    }
  }

  /// `null` when creating a new profile.
  final NetworkProfile? originalProfile;

  final List<String> _otherProfileNames;
  final NetworkProfileValidator _validator;

  String _name;
  AddressingMode _addressingMode;
  String _ipAddress;
  String _subnetMask;
  String _defaultGateway;
  String _preferredDnsServer;
  String _alternateDnsServer;

  // The form shows two DNS fields like Windows does; a profile with more
  // servers (e.g. edited by hand in user_data.json) keeps the rest unchanged.
  final List<String> _furtherDnsServers;

  final List<PingTargetDraft> _pingTargetDrafts = [];
  int _nextPingTargetDraftId = 0;

  final List<CommandDraft> _commandDrafts = [];
  int _nextCommandDraftId = 0;

  final Set<NetworkProfileField> _editedFields = {};
  bool _saveWasAttempted = false;

  List<PingTargetDraft> get pingTargetDrafts =>
      List.unmodifiable(_pingTargetDrafts);
  List<CommandDraft> get commandDrafts => List.unmodifiable(_commandDrafts);

  bool get isNewProfile => originalProfile == null;
  String get name => _name;
  AddressingMode get addressingMode => _addressingMode;
  String get ipAddress => _ipAddress;
  String get subnetMask => _subnetMask;
  String get defaultGateway => _defaultGateway;
  String get preferredDnsServer => _preferredDnsServer;
  String get alternateDnsServer => _alternateDnsServer;
  bool get usesStaticAddress => _addressingMode == AddressingMode.staticIp;

  void updateName(String name) {
    _name = name;
    _markEdited(NetworkProfileField.name);
  }

  void updateAddressingMode(AddressingMode addressingMode) {
    _addressingMode = addressingMode;
    notifyListeners();
  }

  void updateIpAddress(String ipAddress) {
    _ipAddress = ipAddress;
    _markEdited(NetworkProfileField.ipAddress);
  }

  void updateSubnetMask(String subnetMask) {
    _subnetMask = subnetMask;
    _markEdited(NetworkProfileField.subnetMask);
  }

  void updateDefaultGateway(String defaultGateway) {
    _defaultGateway = defaultGateway;
    _markEdited(NetworkProfileField.defaultGateway);
  }

  void updatePreferredDnsServer(String dnsServer) {
    _preferredDnsServer = dnsServer;
    _markEdited(NetworkProfileField.dnsServers);
  }

  void updateAlternateDnsServer(String dnsServer) {
    _alternateDnsServer = dnsServer;
    _markEdited(NetworkProfileField.dnsServers);
  }

  void addPingTarget() {
    _pingTargetDrafts.add(PingTargetDraft._(_nextPingTargetDraftId++));
    notifyListeners();
  }

  void updatePingTargetName(int draftId, String name) {
    _draftWithId(draftId).name = name;
    _markEdited(NetworkProfileField.pingTargets);
  }

  void updatePingTargetIpAddress(int draftId, String ipAddress) {
    _draftWithId(draftId).ipAddress = ipAddress;
    _markEdited(NetworkProfileField.pingTargets);
  }

  void removePingTarget(int draftId) {
    _pingTargetDrafts.removeWhere((draft) => draft.id == draftId);
    notifyListeners();
  }

  void addCommand() {
    _commandDrafts.add(CommandDraft._(_nextCommandDraftId++));
    notifyListeners();
  }

  void updateCommandName(int draftId, String name) {
    _commandDraftWithId(draftId).name = name;
    _markEdited(NetworkProfileField.commands);
  }

  void updateCommandPath(int draftId, String path) {
    _commandDraftWithId(draftId).path = path;
    _markEdited(NetworkProfileField.commands);
  }

  /// As on a command line: spaces separate, double quotes group.
  void updateCommandArguments(int draftId, String argumentsText) {
    _commandDraftWithId(draftId).argumentsText = argumentsText;
    _markEdited(NetworkProfileField.commands);
  }

  void updateCommandRunAfterApply(int draftId, bool runAfterApply) {
    _commandDraftWithId(draftId).runAfterApply = runAfterApply;
    notifyListeners();
  }

  void removeCommand(int draftId) {
    _commandDrafts.removeWhere((draft) => draft.id == draftId);
    notifyListeners();
  }

  /// All messages for [field] joined, or `null` when there is nothing to
  /// show (yet).
  String? errorFor(NetworkProfileField field) {
    final mayShowError = _saveWasAttempted || _editedFields.contains(field);
    if (!mayShowError) return null;
    final messages = [
      for (final error in _validate(_buildProfile()))
        if (error.field == field) error.message,
    ];
    return messages.isEmpty ? null : messages.join('\n');
  }

  /// Returns the profile to save, or `null` and reveals every error when the
  /// input is not valid.
  NetworkProfile? trySave() {
    _saveWasAttempted = true;
    final profile = _buildProfile();
    if (_validate(profile).isNotEmpty) {
      notifyListeners();
      return null;
    }
    return profile;
  }

  void _markEdited(NetworkProfileField field) {
    _editedFields.add(field);
    notifyListeners();
  }

  List<NetworkProfileValidationError> _validate(NetworkProfile profile) =>
      _validator.validate(profile, otherProfileNames: _otherProfileNames);

  PingTargetDraft _draftWithId(int draftId) =>
      _pingTargetDrafts.firstWhere((draft) => draft.id == draftId);

  CommandDraft _commandDraftWithId(int draftId) =>
      _commandDrafts.firstWhere((draft) => draft.id == draftId);

  // A DHCP profile drops the address fields, so switching a profile to DHCP
  // does not keep stale static settings in user_data.json. Ping targets and
  // commands are kept for both modes.
  NetworkProfile _buildProfile() {
    if (!usesStaticAddress) {
      return NetworkProfile(
        name: _name.trim(),
        addressingMode: AddressingMode.dhcp,
        pingTargets: _buildPingTargets(),
        commands: _buildCommands(),
      );
    }
    return NetworkProfile(
      name: _name.trim(),
      addressingMode: AddressingMode.staticIp,
      ipAddress: _trimmedOrNull(_ipAddress),
      subnetMask: _trimmedOrNull(_subnetMask),
      defaultGateway: _trimmedOrNull(_defaultGateway),
      dnsServers: [
        for (final dnsServer in [
          _preferredDnsServer,
          _alternateDnsServer,
          ..._furtherDnsServers,
        ])
          ?_trimmedOrNull(dnsServer),
      ],
      pingTargets: _buildPingTargets(),
      commands: _buildCommands(),
    );
  }

  // Completely empty rows are skipped, so an added but unused row does not
  // block saving. A row with only a name still fails validation.
  List<PingTarget> _buildPingTargets() => [
    for (final draft in _pingTargetDrafts)
      if (!draft.isEmpty)
        PingTarget(
          ipAddress: draft.ipAddress.trim(),
          name: _trimmedOrNull(draft.name),
        ),
  ];

  // Like ping targets, untouched empty rows are skipped.
  List<ProfileCommand> _buildCommands() => [
    for (final draft in _commandDrafts)
      if (!draft.isEmpty)
        ProfileCommand(
          path: draft.path.trim(),
          arguments: CommandLineArguments.split(draft.argumentsText),
          name: _trimmedOrNull(draft.name),
          runAfterApply: draft.runAfterApply,
        ),
  ];

  static String _dnsServerAt(NetworkProfile? profile, int index) {
    final dnsServers = profile?.dnsServers ?? const <String>[];
    return index < dnsServers.length ? dnsServers[index] : '';
  }

  String? _trimmedOrNull(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// One editable row in the editor's ping target list.
///
/// The [id] stays stable while rows are added and removed, so the view can
/// keep each row's text fields attached to the right draft.
class PingTargetDraft {
  PingTargetDraft._(this.id, {this.name = '', this.ipAddress = ''});

  final int id;
  String name;
  String ipAddress;

  bool get isEmpty => name.trim().isEmpty && ipAddress.trim().isEmpty;
}

/// One editable row in the editor's command list; see [PingTargetDraft] for
/// why it has an [id].
class CommandDraft {
  CommandDraft._(
    this.id, {
    this.name = '',
    this.path = '',
    this.argumentsText = '',
    this.runAfterApply = true,
  });

  final int id;
  String name;
  String path;

  /// As on a command line: spaces separate, double quotes group.
  String argumentsText;
  bool runAfterApply;

  bool get isEmpty =>
      name.trim().isEmpty &&
      path.trim().isEmpty &&
      argumentsText.trim().isEmpty;
}
