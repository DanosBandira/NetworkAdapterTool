import 'package:flutter/foundation.dart';

import '../../core/contracts/network_adapter_reader.dart';
import '../../core/contracts/network_profile_repository.dart';
import '../../core/models/addressing_mode.dart';
import '../../core/models/network_adapter.dart';
import '../../core/models/network_preset.dart';
import '../../core/models/network_profile.dart';
import '../../core/models/network_profile_library.dart';
import '../../core/models/ping_target.dart';
import '../../core/network_preset_applier.dart';
import '../../core/network_profile_applier.dart';
import '../../core/reachability/ping_targets_checker.dart';
import 'network_adapter_view_model.dart';

/// State and commands of the main window: the adapter list, the profile and
/// preset lists, applying them to adapters and pinging profile targets.
///
/// Holds no network logic itself; everything goes through the injected core
/// components, so it can be tested with fakes.
class MainViewModel extends ChangeNotifier {
  MainViewModel({
    required this._reader,
    required this._repository,
    required this._applier,
    required this._presetApplier,
    required this._pingTargetsChecker,
  });

  // Applied by the "Switch to DHCP" shortcut; never stored.
  static const _dhcpShortcutProfile = NetworkProfile(
    name: 'DHCP',
    addressingMode: AddressingMode.dhcp,
  );

  /// Name of the unsaved profile built by the adapter settings dialog.
  static const manualSettingsName = 'Manual settings';

  final NetworkAdapterReader _reader;
  final NetworkProfileRepository _repository;
  final NetworkProfileApplier _applier;
  final NetworkPresetApplier _presetApplier;
  final PingTargetsChecker _pingTargetsChecker;

  // Ping results stay visible under their profile until the next ping, an
  // edit or a delete of that profile. Preset results likewise per preset.
  final Map<String, List<PingTargetStatus>> _pingStatusesByProfileName = {};
  final Set<String> _profileNamesBeingPinged = {};
  final Map<String, List<PresetLineStatus>> _lineStatusesByPresetName = {};
  bool _isDisposed = false;

  List<NetworkAdapterViewModel> _adapters = [];
  NetworkProfileLibrary _library = const NetworkProfileLibrary();
  String? _selectedAdapterName;
  String? _selectedProfileName;
  String? _presetNameBeingApplied;
  bool _isLoadingAdapters = false;
  bool _isApplying = false;
  bool _libraryIsLoaded = false;
  StatusMessage? _statusMessage;
  String _adapterSearchText = '';
  String _profileSearchText = '';

  List<NetworkAdapterViewModel> get adapters => List.unmodifiable(_adapters);
  List<NetworkProfile> get profiles => List.unmodifiable(_library.profiles);
  List<NetworkPreset> get presets => List.unmodifiable(_library.presets);

  // Searching only hides list entries; the selection is kept, so typing a
  // search never silently changes the adapter or profile that gets applied.
  List<NetworkAdapterViewModel> get visibleAdapters => [
    for (final adapter in _adapters)
      if (adapter.matchesSearch(_adapterSearchText)) adapter,
  ];
  List<NetworkProfile> get visibleProfiles => [
    for (final profile in _library.profiles)
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
      _canChangeAdapters &&
      _selectedAdapterName != null &&
      _selectedProfile != null;
  bool get canSwitchSelectedAdapterToDhcp =>
      _canChangeAdapters && _selectedAdapterName != null;
  bool get canApplyPresets => _canChangeAdapters && _libraryIsLoaded;
  bool get canConfigureAdapters => _canChangeAdapters;

  // Editing is blocked until loading succeeded: saving over a file that
  // failed to load would replace the user's profiles and presets.
  bool get canEditProfiles => _libraryIsLoaded;
  bool get canEditPresets => _libraryIsLoaded;

  /// `null` when the profile has not been pinged yet.
  List<PingTargetStatus>? pingStatusesFor(String profileName) {
    final statuses = _pingStatusesByProfileName[profileName];
    return statuses == null ? null : List.unmodifiable(statuses);
  }

  bool isPinging(String profileName) =>
      _profileNamesBeingPinged.contains(profileName);

  bool canPingProfile(NetworkProfile profile) =>
      profile.pingTargets.isNotEmpty && !isPinging(profile.name);

  /// `null` when the preset has not been applied yet.
  List<PresetLineStatus>? lineStatusesFor(String presetName) {
    final statuses = _lineStatusesByPresetName[presetName];
    return statuses == null ? null : List.unmodifiable(statuses);
  }

  bool isApplyingPreset(String presetName) =>
      _presetNameBeingApplied == presetName;

  /// The profiles a preset uses that have ping targets, each once, in preset
  /// order. Lines whose profile no longer exists are skipped.
  List<NetworkProfile> pingableProfilesOf(NetworkPreset preset) {
    final profiles = <NetworkProfile>[];
    for (final assignment in preset.assignments) {
      final profile = _profileNamed(assignment.profileName);
      if (profile != null &&
          profile.pingTargets.isNotEmpty &&
          !profiles.contains(profile)) {
        profiles.add(profile);
      }
    }
    return profiles;
  }

  bool isPingingPreset(NetworkPreset preset) =>
      pingableProfilesOf(preset).any((profile) => isPinging(profile.name));

  bool canPingPreset(NetworkPreset preset) =>
      pingableProfilesOf(preset).isNotEmpty && !isPingingPreset(preset);

  List<NetworkPreset> presetsUsingProfile(String profileName) => [
    for (final preset in _library.presets)
      if (preset.usesProfile(profileName)) preset,
  ];

  bool get _canChangeAdapters => !_isApplying && !_isLoadingAdapters;

  NetworkProfile? get _selectedProfile => _profileNamed(_selectedProfileName);

  Future<void> initialize() async {
    await Future.wait([_loadLibrary(), refreshAdapters()]);
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
    await _applyProfileToAdapter(profile, _selectedAdapterName!);
  }

  Future<void> switchSelectedAdapterToDhcp() async {
    if (!canSwitchSelectedAdapterToDhcp) return;
    await _applyProfileToAdapter(_dhcpShortcutProfile, _selectedAdapterName!);
  }

  /// The adapter's current IPv4 settings as an unsaved profile, the starting
  /// point of the adapter settings dialog. A DHCP adapter starts as DHCP with
  /// empty fields, since its current address is only leased.
  NetworkProfile currentSettingsOf(NetworkAdapter adapter) {
    if (adapter.addressingMode != AddressingMode.staticIp) {
      return const NetworkProfile(
        name: manualSettingsName,
        addressingMode: AddressingMode.dhcp,
      );
    }
    return NetworkProfile(
      name: manualSettingsName,
      addressingMode: AddressingMode.staticIp,
      ipAddress: adapter.ipAddress,
      subnetMask: adapter.subnetMask,
      defaultGateway: adapter.defaultGateway,
      dnsServers: adapter.dnsServers,
    );
  }

  /// Applies settings entered directly for one adapter, without storing them
  /// as a profile. Goes through the same validation, disconnected-adapter
  /// check and verification as a saved profile.
  Future<void> applyManualSettings(
    NetworkProfile settings,
    String adapterName,
  ) async {
    if (!canConfigureAdapters) return;
    _selectedAdapterName = adapterName;
    await _applyProfileToAdapter(settings, adapterName);
  }

  /// Applies every line of [preset]; a failing line does not stop the rest.
  /// Afterwards the ping targets of all successfully applied profiles are
  /// pinged.
  Future<void> applyPreset(NetworkPreset preset) async {
    if (!canApplyPresets) return;
    _startApplyingPreset(preset);
    final appliedProfiles = <NetworkProfile>[];
    await for (final result in _presetApplier.applyPreset(
      preset,
      _library.profiles,
    )) {
      _recordPresetLineResult(preset.name, result);
      if (result.isSuccess) appliedProfiles.add(result.profile!);
    }
    _finishApplyingPreset(preset);
    await Future.wait([
      for (final profile in appliedProfiles) pingTargetsOf(profile),
    ]);
  }

  /// Pings the targets of every profile in [preset] at the same time, without
  /// applying anything. Results appear per profile ([pingStatusesFor]).
  Future<void> pingPreset(NetworkPreset preset) async {
    if (!canPingPreset(preset)) return;
    await Future.wait([
      for (final profile in pingableProfilesOf(preset)) pingTargetsOf(profile),
    ]);
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
    for (final profile in _library.profiles)
      if (profile.name != profileBeingEdited?.name) profile.name,
  ];

  List<String> presetNamesOtherThan(NetworkPreset? presetBeingEdited) => [
    for (final preset in _library.presets)
      if (preset.name != presetBeingEdited?.name) preset.name,
  ];

  /// Adds [savedProfile], or replaces [originalProfile] with it when editing.
  /// A rename is carried into every preset that uses the profile.
  Future<void> saveProfile(
    NetworkProfile savedProfile, {
    NetworkProfile? originalProfile,
  }) async {
    final originalName = originalProfile?.name;
    final updatedLibrary = _library.copyWith(
      profiles: [
        for (final profile in _library.profiles)
          if (profile.name == originalName) savedProfile else profile,
        if (originalProfile == null) savedProfile,
      ],
      presets: originalName == null || originalName == savedProfile.name
          ? null
          : [
              for (final preset in _library.presets)
                preset.withProfileRenamed(originalName, savedProfile.name),
            ],
    );
    final isStored = await _storeLibrary(updatedLibrary);
    if (isStored) {
      _selectedProfileName = savedProfile.name;
      // Results of the old targets no longer describe the edited profile.
      _pingStatusesByProfileName.remove(originalName);
    }
    notifyListeners();
  }

  /// Refused while a preset uses the profile, so presets never point to a
  /// profile that is gone.
  Future<void> deleteProfile(NetworkProfile profileToDelete) async {
    final usingPresets = presetsUsingProfile(profileToDelete.name);
    if (usingPresets.isNotEmpty) {
      _statusMessage = StatusMessage.error(
        '"${profileToDelete.name}" is used by preset '
        '${usingPresets.map((preset) => '"${preset.name}"').join(', ')}. '
        'Remove it from the preset first.',
      );
      notifyListeners();
      return;
    }
    final isStored = await _storeLibrary(
      _library.copyWith(
        profiles: [
          for (final profile in _library.profiles)
            if (profile.name != profileToDelete.name) profile,
        ],
      ),
    );
    if (isStored) {
      _pingStatusesByProfileName.remove(profileToDelete.name);
      if (_selectedProfileName == profileToDelete.name) {
        _selectedProfileName = null;
      }
    }
    notifyListeners();
  }

  /// Adds [savedPreset], or replaces [originalPreset] with it when editing.
  Future<void> savePreset(
    NetworkPreset savedPreset, {
    NetworkPreset? originalPreset,
  }) async {
    final isStored = await _storeLibrary(
      _library.copyWith(
        presets: [
          for (final preset in _library.presets)
            if (preset.name == originalPreset?.name) savedPreset else preset,
          if (originalPreset == null) savedPreset,
        ],
      ),
    );
    if (isStored) _lineStatusesByPresetName.remove(originalPreset?.name);
    notifyListeners();
  }

  Future<void> deletePreset(NetworkPreset presetToDelete) async {
    final isStored = await _storeLibrary(
      _library.copyWith(
        presets: [
          for (final preset in _library.presets)
            if (preset.name != presetToDelete.name) preset,
        ],
      ),
    );
    if (isStored) _lineStatusesByPresetName.remove(presetToDelete.name);
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

  Future<void> _loadLibrary() async {
    try {
      _library = await _repository.loadLibrary();
      _libraryIsLoaded = true;
    } on NetworkProfileStorageException catch (error) {
      _statusMessage = StatusMessage.error(
        'Could not load profiles: ${error.reason}',
      );
    }
    notifyListeners();
  }

  Future<bool> _storeLibrary(NetworkProfileLibrary updatedLibrary) async {
    try {
      await _repository.saveLibrary(updatedLibrary);
      _library = updatedLibrary;
      return true;
    } on NetworkProfileStorageException catch (error) {
      _statusMessage = StatusMessage.error(
        'Could not save profiles: ${error.reason}',
      );
      return false;
    }
  }

  Future<void> _applyProfileToAdapter(
    NetworkProfile profile,
    String adapterName,
  ) async {
    _isApplying = true;
    _statusMessage = StatusMessage.progress(
      'Applying "${profile.name}" to $adapterName…',
    );
    notifyListeners();

    final outcome = await _applier.applyProfileToAdapter(profile, adapterName);
    _showUpdatedAdapterAfter(outcome);
    _statusMessage = _describeOutcome(outcome, profile.name, adapterName);
    _isApplying = false;
    notifyListeners();

    // Adapter actions are already enabled again here; the returned future
    // only completes after pinging so callers (and tests) can await it.
    if (outcome is ProfileApplied) await pingTargetsOf(profile);
  }

  void _startApplyingPreset(NetworkPreset preset) {
    _isApplying = true;
    _presetNameBeingApplied = preset.name;
    _lineStatusesByPresetName[preset.name] = [
      for (final assignment in preset.assignments)
        PresetLineStatus(assignment, PresetLineState.pending, null),
    ];
    _statusMessage = StatusMessage.progress(
      'Applying preset "${preset.name}"…',
    );
    notifyListeners();
  }

  void _recordPresetLineResult(
    String presetName,
    PresetAssignmentResult result,
  ) {
    final outcome = result.outcome;
    if (outcome != null) _showUpdatedAdapterAfter(outcome);
    final message = outcome == null
        ? 'Profile "${result.assignment.profileName}" no longer exists.'
        : _describeOutcome(
            outcome,
            result.assignment.profileName,
            result.assignment.adapterName,
          ).text;
    final statuses = _lineStatusesByPresetName[presetName] ?? [];
    _lineStatusesByPresetName[presetName] = [
      for (final status in statuses)
        if (status.assignment == result.assignment)
          PresetLineStatus(
            result.assignment,
            result.isSuccess ? PresetLineState.applied : PresetLineState.failed,
            message,
          )
        else
          status,
    ];
    _notifyListenersUnlessDisposed();
  }

  void _finishApplyingPreset(NetworkPreset preset) {
    final statuses = _lineStatusesByPresetName[preset.name] ?? [];
    final appliedCount = statuses
        .where((status) => status.state == PresetLineState.applied)
        .length;
    final summary =
        'Preset "${preset.name}": $appliedCount of ${statuses.length} '
        'adapters switched.';
    _statusMessage = appliedCount == statuses.length
        ? StatusMessage.success(summary)
        : StatusMessage.error('$summary See the preset for details.');
    _presetNameBeingApplied = null;
    _isApplying = false;
    _notifyListenersUnlessDisposed();
  }

  void _startPinging(NetworkProfile profile) {
    _profileNamesBeingPinged.add(profile.name);
    _pingStatusesByProfileName[profile.name] = [
      for (final target in profile.pingTargets)
        PingTargetStatus(target, PingState.pinging),
    ];
    _notifyListenersUnlessDisposed();
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
    String profileName,
    String adapterName,
  ) {
    return switch (outcome) {
      ProfileApplied() => StatusMessage.success(
        '"$profileName" is active on $adapterName.',
      ),
      ProfileInvalid(:final validationErrors) => StatusMessage.error(
        '"$profileName" is invalid: '
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

  NetworkProfile? _profileNamed(String? profileName) => _library.profiles
      .where((profile) => profile.name == profileName)
      .firstOrNull;

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

enum PresetLineState { pending, applied, failed }

/// Result of one preset line, shown under its preset card.
class PresetLineStatus {
  const PresetLineStatus(this.assignment, this.state, this.message);

  final PresetAssignment assignment;
  final PresetLineState state;

  /// `null` while pending.
  final String? message;
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
