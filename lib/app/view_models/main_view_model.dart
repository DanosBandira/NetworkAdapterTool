import 'package:flutter/foundation.dart';

import '../../core/contracts/network_adapter_reader.dart';
import '../../core/contracts/network_profile_repository.dart';
import '../../core/models/addressing_mode.dart';
import '../../core/models/network_profile.dart';
import '../../core/models/ping_target.dart';
import '../../core/network_profile_applier.dart';
import '../../core/reachability/ping_targets_checker.dart';
import 'network_adapter_view_model.dart';

/// State and commands of the main window: the adapter list, the profile list,
/// applying a profile to an adapter and pinging a profile's targets.
///
/// Holds no network logic itself; everything goes through the injected core
/// components, so it can be tested with fakes.
class MainViewModel extends ChangeNotifier {
  MainViewModel({
    required this._reader,
    required this._repository,
    required this._applier,
    required this._pingTargetsChecker,
  });

  // Applied by the "Switch to DHCP" shortcut; never stored.
  static const _dhcpShortcutProfile = NetworkProfile(
    name: 'DHCP',
    addressingMode: AddressingMode.dhcp,
  );

  final NetworkAdapterReader _reader;
  final NetworkProfileRepository _repository;
  final NetworkProfileApplier _applier;
  final PingTargetsChecker _pingTargetsChecker;

  // Ping results stay visible under their profile until the next ping, an
  // edit or a delete of that profile.
  final Map<String, List<PingTargetStatus>> _pingStatusesByProfileName = {};
  final Set<String> _profileNamesBeingPinged = {};
  bool _isDisposed = false;

  List<NetworkAdapterViewModel> _adapters = [];
  List<NetworkProfile> _profiles = [];
  String? _selectedAdapterName;
  String? _selectedProfileName;
  bool _isLoadingAdapters = false;
  bool _isApplying = false;
  bool _profilesAreLoaded = false;
  StatusMessage? _statusMessage;
  String _adapterSearchText = '';
  String _profileSearchText = '';

  List<NetworkAdapterViewModel> get adapters => List.unmodifiable(_adapters);
  List<NetworkProfile> get profiles => List.unmodifiable(_profiles);

  // Searching only hides list entries; the selection is kept, so typing a
  // search never silently changes the adapter or profile that gets applied.
  List<NetworkAdapterViewModel> get visibleAdapters => [
    for (final adapter in _adapters)
      if (adapter.matchesSearch(_adapterSearchText)) adapter,
  ];
  List<NetworkProfile> get visibleProfiles => [
    for (final profile in _profiles)
      if (_profileMatchesSearch(profile, _profileSearchText)) profile,
  ];
  String get adapterSearchText => _adapterSearchText;
  String get profileSearchText => _profileSearchText;
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

  /// `null` when the profile has not been pinged yet.
  List<PingTargetStatus>? pingStatusesFor(String profileName) {
    final statuses = _pingStatusesByProfileName[profileName];
    return statuses == null ? null : List.unmodifiable(statuses);
  }

  bool isPinging(String profileName) =>
      _profileNamesBeingPinged.contains(profileName);

  bool canPingProfile(NetworkProfile profile) =>
      profile.pingTargets.isNotEmpty && !isPinging(profile.name);

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

  void searchAdapters(String searchText) {
    _adapterSearchText = searchText;
    notifyListeners();
  }

  void searchProfiles(String searchText) {
    _profileSearchText = searchText;
    notifyListeners();
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

  /// Pings every target of [profile] until it answers or 10 seconds pass,
  /// updating [pingStatusesFor] as each result comes in.
  Future<void> pingTargetsOf(NetworkProfile profile) async {
    if (!canPingProfile(profile)) return;
    _startPinging(profile);
    await for (final result in _pingTargetsChecker.checkTargets(
      profile.pingTargets,
    )) {
      _recordPingResult(profile.name, result);
    }
    _profileNamesBeingPinged.remove(profile.name);
    _notifyListenersUnlessDisposed();
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
    if (isStored) {
      _selectedProfileName = savedProfile.name;
      // Results of the old targets no longer describe the edited profile.
      _pingStatusesByProfileName.remove(originalProfile?.name);
    }
    notifyListeners();
  }

  Future<void> deleteProfile(NetworkProfile profileToDelete) async {
    final updatedProfiles = [
      for (final profile in _profiles)
        if (profile.name != profileToDelete.name) profile,
    ];
    final isStored = await _storeProfiles(updatedProfiles);
    if (isStored) {
      _pingStatusesByProfileName.remove(profileToDelete.name);
      if (_selectedProfileName == profileToDelete.name) {
        _selectedProfileName = null;
      }
    }
    notifyListeners();
  }

  void dismissStatusMessage() {
    _statusMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
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

    // Adapter actions are already enabled again here; the returned future
    // only completes after pinging so callers (and tests) can await it.
    if (outcome is ProfileApplied) await pingTargetsOf(profile);
  }

  void _startPinging(NetworkProfile profile) {
    _profileNamesBeingPinged.add(profile.name);
    _pingStatusesByProfileName[profile.name] = [
      for (final target in profile.pingTargets)
        PingTargetStatus(target, PingState.pinging),
    ];
    notifyListeners();
  }

  void _recordPingResult(String profileName, PingTargetResult result) {
    final statuses = _pingStatusesByProfileName[profileName];
    // The profile may have been edited or deleted while pinging.
    if (statuses == null) return;
    _pingStatusesByProfileName[profileName] = [
      for (final status in statuses)
        if (status.target == result.target)
          PingTargetStatus(
            result.target,
            result.isReachable ? PingState.reachable : PingState.unreachable,
            roundTripTime: result.roundTripTime,
          )
        else
          status,
    ];
    _notifyListenersUnlessDisposed();
  }

  // Pinging runs up to 10 seconds and may outlive the window.
  void _notifyListenersUnlessDisposed() {
    if (!_isDisposed) notifyListeners();
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

  bool _profileMatchesSearch(NetworkProfile profile, String searchText) {
    final normalizedSearch = searchText.trim().toLowerCase();
    return [
      profile.name,
      ?profile.ipAddress,
      ?profile.defaultGateway,
    ].any((text) => text.toLowerCase().contains(normalizedSearch));
  }

  void _keepAdapterSelectionOnlyIfStillPresent() {
    final selectedAdapterStillExists = _adapters.any(
      (adapter) => adapter.name == _selectedAdapterName,
    );
    if (!selectedAdapterStillExists) _selectedAdapterName = null;
  }
}

enum PingState { pinging, reachable, unreachable }

/// Ping state of one target, shown under its profile card.
class PingTargetStatus {
  const PingTargetStatus(this.target, this.state, {this.roundTripTime});

  final PingTarget target;
  final PingState state;
  final Duration? roundTripTime;

  String get resultText => switch (state) {
    PingState.pinging => 'Pinging…',
    PingState.unreachable => 'No reply',
    PingState.reachable =>
      roundTripTime == Duration.zero
          ? '<1 ms'
          : '${roundTripTime!.inMilliseconds} ms',
  };
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
