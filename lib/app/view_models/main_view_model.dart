import 'package:flutter/foundation.dart';

import '../../core/contracts/network_adapter_reader.dart';
import '../../core/contracts/network_profile_repository.dart';
import '../../core/models/addressing_mode.dart';
import '../../core/models/network_profile.dart';
import '../../core/network_profile_applier.dart';
import 'network_adapter_view_model.dart';

/// State and commands of the main window: the adapter list, the profile list
/// and applying a profile to an adapter.
///
/// Holds no network logic itself; everything goes through the injected core
/// components, so it can be tested with fakes.
class MainViewModel extends ChangeNotifier {
  MainViewModel({
    required this._reader,
    required this._repository,
    required this._applier,
  });

  // Applied by the "Switch to DHCP" shortcut; never stored.
  static const _dhcpShortcutProfile = NetworkProfile(
    name: 'DHCP',
    addressingMode: AddressingMode.dhcp,
  );

  final NetworkAdapterReader _reader;
  final NetworkProfileRepository _repository;
  final NetworkProfileApplier _applier;

  List<NetworkAdapterViewModel> _adapters = [];
  List<NetworkProfile> _profiles = [];
  String? _selectedAdapterName;
  String? _selectedProfileName;
  bool _isLoadingAdapters = false;
  bool _isApplying = false;
  bool _profilesAreLoaded = false;
  StatusMessage? _statusMessage;

  List<NetworkAdapterViewModel> get adapters => List.unmodifiable(_adapters);
  List<NetworkProfile> get profiles => List.unmodifiable(_profiles);
  String? get selectedAdapterName => _selectedAdapterName;
  String? get selectedProfileName => _selectedProfileName;
  bool get isLoadingAdapters => _isLoadingAdapters;
  bool get isApplying => _isApplying;
  StatusMessage? get statusMessage => _statusMessage;

  bool get canApplySelectedProfile =>
      _canChangeAdapter && _selectedProfile != null;
  bool get canSwitchSelectedAdapterToDhcp => _canChangeAdapter;

  // Profile editing is blocked until loading succeeded: saving over a file
  // that failed to load would replace the user's profiles.
  bool get canEditProfiles => _profilesAreLoaded;

  bool get _canChangeAdapter =>
      !_isApplying && !_isLoadingAdapters && _selectedAdapterName != null;

  NetworkProfile? get _selectedProfile => _profiles
      .where((profile) => profile.name == _selectedProfileName)
      .firstOrNull;

  Future<void> initialize() async {
    await Future.wait([_loadProfiles(), refreshAdapters()]);
  }

  Future<void> refreshAdapters() async {
    _isLoadingAdapters = true;
    notifyListeners();
    try {
      final adapters = await _reader.readAllAdapters();
      _adapters = [
        for (final adapter in adapters) NetworkAdapterViewModel(adapter),
      ];
      _keepAdapterSelectionOnlyIfStillPresent();
    } on NetworkAdapterReadException catch (error) {
      _statusMessage = StatusMessage.error(
        'Could not read network adapters: ${error.reason}',
      );
    } finally {
      _isLoadingAdapters = false;
      notifyListeners();
    }
  }

  void selectAdapter(String adapterName) {
    _selectedAdapterName = adapterName;
    notifyListeners();
  }

  void selectProfile(String profileName) {
    _selectedProfileName = profileName;
    notifyListeners();
  }

  Future<void> applySelectedProfileToSelectedAdapter() async {
    final profile = _selectedProfile;
    if (!canApplySelectedProfile || profile == null) return;
    await _applyProfileToSelectedAdapter(profile);
  }

  Future<void> switchSelectedAdapterToDhcp() async {
    if (!canSwitchSelectedAdapterToDhcp) return;
    await _applyProfileToSelectedAdapter(_dhcpShortcutProfile);
  }

  /// Names the editor must not reuse; excludes the profile being edited so
  /// saving it under its own name stays allowed.
  List<String> profileNamesOtherThan(NetworkProfile? profileBeingEdited) => [
    for (final profile in _profiles)
      if (profile.name != profileBeingEdited?.name) profile.name,
  ];

  /// Adds [savedProfile], or replaces [originalProfile] with it when editing.
  Future<void> saveProfile(
    NetworkProfile savedProfile, {
    NetworkProfile? originalProfile,
  }) async {
    final updatedProfiles = [
      for (final profile in _profiles)
        if (profile.name == originalProfile?.name) savedProfile else profile,
      if (originalProfile == null) savedProfile,
    ];
    final isStored = await _storeProfiles(updatedProfiles);
    if (isStored) _selectedProfileName = savedProfile.name;
    notifyListeners();
  }

  Future<void> deleteProfile(NetworkProfile profileToDelete) async {
    final updatedProfiles = [
      for (final profile in _profiles)
        if (profile.name != profileToDelete.name) profile,
    ];
    final isStored = await _storeProfiles(updatedProfiles);
    if (isStored && _selectedProfileName == profileToDelete.name) {
      _selectedProfileName = null;
    }
    notifyListeners();
  }

  void dismissStatusMessage() {
    _statusMessage = null;
    notifyListeners();
  }

  Future<void> _loadProfiles() async {
    try {
      _profiles = await _repository.loadAllProfiles();
      _profilesAreLoaded = true;
    } on NetworkProfileStorageException catch (error) {
      _statusMessage = StatusMessage.error(
        'Could not load profiles: ${error.reason}',
      );
    }
    notifyListeners();
  }

  Future<bool> _storeProfiles(List<NetworkProfile> updatedProfiles) async {
    try {
      await _repository.saveAllProfiles(updatedProfiles);
      _profiles = updatedProfiles;
      return true;
    } on NetworkProfileStorageException catch (error) {
      _statusMessage = StatusMessage.error(
        'Could not save profiles: ${error.reason}',
      );
      return false;
    }
  }

  Future<void> _applyProfileToSelectedAdapter(NetworkProfile profile) async {
    final adapterName = _selectedAdapterName!;
    _isApplying = true;
    _statusMessage = StatusMessage.progress(
      'Applying "${profile.name}" to $adapterName…',
    );
    notifyListeners();

    final outcome = await _applier.applyProfileToAdapter(profile, adapterName);
    _showUpdatedAdapterAfter(outcome);
    _statusMessage = _describeOutcome(outcome, profile, adapterName);
    _isApplying = false;
    notifyListeners();
  }

  // The applier already read the adapter back; reuse that instead of
  // spending another few seconds on a full refresh.
  void _showUpdatedAdapterAfter(ApplyProfileOutcome outcome) {
    if (outcome is! ProfileApplied) return;
    _adapters = [
      for (final adapterViewModel in _adapters)
        if (adapterViewModel.name == outcome.adapter.name)
          NetworkAdapterViewModel(outcome.adapter)
        else
          adapterViewModel,
    ];
  }

  StatusMessage _describeOutcome(
    ApplyProfileOutcome outcome,
    NetworkProfile profile,
    String adapterName,
  ) {
    return switch (outcome) {
      ProfileApplied() => StatusMessage.success(
        '"${profile.name}" is active on $adapterName.',
      ),
      ProfileInvalid(:final validationErrors) => StatusMessage.error(
        '"${profile.name}" is invalid: '
        '${validationErrors.map((error) => error.message).join(' ')}',
      ),
      ProfileNeedsConnectedAdapter() => StatusMessage.error(
        '$adapterName is not connected. Windows can only switch it from DHCP '
        'to a static address while a cable is connected. Connect it, refresh '
        'and try again.',
      ),
      ProfileRejectedBySystem(:final error) => StatusMessage.error(
        'Windows refused the setting (exit code ${error.exitCode}): '
        '${error.output}',
      ),
      ProfileNotActive(:final mismatches) => StatusMessage.error(
        '$adapterName does not show the profile settings: '
        '${mismatches.join('; ')}.',
      ),
      ProfileNotVerified(:final error) => StatusMessage.error(
        'Applied, but could not verify $adapterName: ${error.reason}',
      ),
    };
  }

  void _keepAdapterSelectionOnlyIfStillPresent() {
    final selectedAdapterStillExists = _adapters.any(
      (adapter) => adapter.name == _selectedAdapterName,
    );
    if (!selectedAdapterStillExists) _selectedAdapterName = null;
  }
}

enum StatusKind { progress, success, error }

/// One line of feedback shown at the bottom of the main window.
class StatusMessage {
  const StatusMessage.progress(this.text) : kind = StatusKind.progress;
  const StatusMessage.success(this.text) : kind = StatusKind.success;
  const StatusMessage.error(this.text) : kind = StatusKind.error;

  final StatusKind kind;
  final String text;
}
