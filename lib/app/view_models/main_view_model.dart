import 'package:flutter/foundation.dart';

import '../../core/commands/profile_command_runner.dart';
import '../../core/contracts/folder_opener.dart';
import '../../core/contracts/network_adapter_reader.dart';
import '../../core/contracts/network_profile_library_transfer.dart';
import '../../core/contracts/network_profile_repository.dart';
import '../../core/models/addressing_mode.dart';
import '../../core/models/ipv4_address.dart';
import '../../core/models/network_adapter.dart';
import '../../core/models/network_preset.dart';
import '../../core/models/network_profile.dart';
import '../../core/models/network_profile_library.dart';
import '../../core/models/ping_target.dart';
import '../../core/models/profile_command.dart';
import '../../core/network_preset_applier.dart';
import '../../core/network_profile_applier.dart';
import '../../core/platform/host_platform.dart';
import '../../core/profiles/network_profile_comparer.dart';
import '../../core/profiles/network_profile_library_merger.dart';
import '../../core/reachability/ping_targets_checker.dart';
import 'network_adapter_view_model.dart';

/// State and commands of the main window: the adapter list, the profile and
/// preset lists, applying them to adapters, pinging profile targets and
/// running profile commands.
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
    required this._libraryTransfer,
    required this._profileCommandRunner,
    required this._folderOpener,
    this._libraryMerger = const NetworkProfileLibraryMerger(),
    this._profileComparer = const NetworkProfileComparer(),
    this.platform = HostPlatform.windows,
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
  final NetworkProfileLibraryTransfer _libraryTransfer;
  final ProfileCommandRunner _profileCommandRunner;
  final FolderOpener _folderOpener;
  final NetworkProfileLibraryMerger _libraryMerger;
  final NetworkProfileComparer _profileComparer;

  /// Decides the platform rules here and the wording in the views.
  final HostPlatform platform;

  // Which saved profile was last applied to which adapter, in this session.
  // Needed for DHCP profiles: every DHCP adapter matches every DHCP profile,
  // so only the apply itself tells which one the user chose.
  final Map<String, String> _lastAppliedProfileNameByAdapterName = {};

  // Ping results stay visible under their profile until that target is
  // pinged again, or the profile is edited or deleted. Targets can be pinged
  // one by one, so each keeps its own result. Preset results per preset.
  final Map<String, Map<PingTarget, PingTargetStatus>>
  _pingStatusesByProfileName = {};
  final Map<String, Set<PingTarget>> _targetsBeingPingedByProfileName = {};
  final Map<String, List<PresetLineStatus>> _lineStatusesByPresetName = {};

  // Command results behave like ping results, keyed by the command's index in
  // the profile because commands can run one by one too. A profile runs its
  // commands one at a time, so it has at most one active run to stop.
  final Map<String, Map<int, CommandStatus>> _commandStatusesByProfileName = {};
  final Map<String, ProfileCommandRun> _activeCommandRunByProfileName = {};
  final Set<String> _profileNamesRunningCommands = {};
  final Set<String> _profileNamesStoppingCommands = {};
  final Set<String> _presetNamesStoppingCommands = {};
  bool _isDisposed = false;

  List<NetworkAdapterViewModel> _adapters = [];
  NetworkProfileLibrary _library = const NetworkProfileLibrary();
  String? _selectedAdapterName;
  String? _selectedProfileName;
  String? _presetNameBeingApplied;
  bool _isLoadingAdapters = false;
  bool _isApplying = false;
  bool _libraryIsLoaded = false;

  // Until adapters were read once, every preset adapter would look missing.
  bool _adaptersAreLoaded = false;

  // Set before saving, so a slow or failing save never opens the help twice.
  bool _helpShownThisSession = false;
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

  // Same guard as editing: never overwrite or export a library that failed
  // to load.
  bool get canTransferUserData => _libraryIsLoaded && !_isApplying;

  /// True on the first start: the stored data says the help was never shown.
  /// Stays false when the data failed to load, so a broken file does not
  /// keep opening the help.
  bool get shouldShowHelpOnStart =>
      _libraryIsLoaded && !_library.helpWasShown && !_helpShownThisSession;

  /// Adapters of [preset] that do not exist on this PC (e.g. after loading a
  /// file from another PC). Empty until adapters have been read once.
  List<String> missingAdaptersOf(NetworkPreset preset) {
    if (!_adaptersAreLoaded) return const [];
    return [
      for (final adapterName in preset.adapterNames)
        if (!_isPresentAdapter(adapterName)) adapterName,
    ];
  }

  // Editing is blocked until loading succeeded: saving over a file that
  // failed to load would replace the user's profiles and presets.
  bool get canEditProfiles => _libraryIsLoaded;
  bool get canEditPresets => _libraryIsLoaded;

  /// The targets pinged so far, in profile order; `null` when none was.
  List<PingTargetStatus>? pingStatusesFor(String profileName) {
    final statuses = _pingStatusesByProfileName[profileName];
    return statuses == null ? null : List.unmodifiable(statuses.values);
  }

  /// `null` when [target] has not been pinged yet.
  PingTargetStatus? pingStatusOf(String profileName, PingTarget target) =>
      _pingStatusesByProfileName[profileName]?[target];

  bool isPinging(String profileName) =>
      _targetsBeingPingedByProfileName[profileName]?.isNotEmpty ?? false;

  bool isPingingTarget(String profileName, PingTarget target) =>
      _targetsBeingPingedByProfileName[profileName]?.contains(target) ?? false;

  bool canPingProfile(NetworkProfile profile) =>
      profile.pingTargets.isNotEmpty && !isPinging(profile.name);

  bool canPingTarget(NetworkProfile profile, PingTarget target) =>
      !isPingingTarget(profile.name, target);

  /// The commands run so far, in profile order; `null` when none ran.
  List<CommandStatus>? commandStatusesFor(String profileName) {
    final statuses = _commandStatusesByProfileName[profileName];
    if (statuses == null) return null;
    final sortedIndexes = statuses.keys.toList()..sort();
    return List.unmodifiable([
      for (final index in sortedIndexes) statuses[index]!,
    ]);
  }

  /// `null` when the command at [commandIndex] has not run yet.
  CommandStatus? commandStatusOf(String profileName, int commandIndex) =>
      _commandStatusesByProfileName[profileName]?[commandIndex];

  bool isRunningCommands(String profileName) =>
      _profileNamesRunningCommands.contains(profileName);

  bool canRunCommands(NetworkProfile profile) =>
      profile.commands.isNotEmpty && !isRunningCommands(profile.name);

  /// One command at a time per profile, so a single command waits until
  /// the running ones are done or stopped.
  bool canRunCommand(NetworkProfile profile) =>
      !isRunningCommands(profile.name);

  bool canStopCommands(String profileName) =>
      isRunningCommands(profileName) &&
      !_profileNamesStoppingCommands.contains(profileName);

  /// The saved profile whose settings [adapter] has now, for its card;
  /// `null` when none matches.
  ///
  /// The profile last applied to the adapter wins while the adapter still
  /// matches it. Otherwise a static profile with exactly these settings is
  /// recognized (also after a restart or a change outside the app); a DHCP
  /// profile is never guessed, since every DHCP profile would match.
  String? activeProfileNameOf(NetworkAdapterViewModel adapter) {
    final lastAppliedProfile = _profileNamed(
      _lastAppliedProfileNameByAdapterName[adapter.name],
    );
    if (lastAppliedProfile != null &&
        _profileComparer.isActiveOn(lastAppliedProfile, adapter.adapter)) {
      return lastAppliedProfile.name;
    }
    for (final profile in _library.profiles) {
      if (profile.addressingMode == AddressingMode.staticIp &&
          _profileComparer.isActiveOn(profile, adapter.adapter)) {
        return profile.name;
      }
    }
    return null;
  }

  /// Where a command path without a folder (e.g. `tool.exe`) is looked up.
  String get pluginFolderPath => _profileCommandRunner.pluginFolderPath;

  /// The command path to fill in for a file picked with Browse: relative
  /// inside the plugin folder, absolute elsewhere.
  String commandPathFor(String selectedFilePath) =>
      _profileCommandRunner.commandPathFor(selectedFilePath);

  /// Where the Browse dialog for [commandPath] opens.
  String folderToBrowseFrom(String commandPath) =>
      _profileCommandRunner.folderToBrowseFrom(commandPath);

  /// `null` when the preset has not been applied yet.
  List<PresetLineStatus>? lineStatusesFor(String presetName) {
    final statuses = _lineStatusesByPresetName[presetName];
    return statuses == null ? null : List.unmodifiable(statuses);
  }

  bool isApplyingPreset(String presetName) =>
      _presetNameBeingApplied == presetName;

  /// The profiles a preset uses that have ping targets, each once, in preset
  /// order. Lines whose profile no longer exists are skipped.
  List<NetworkProfile> pingableProfilesOf(NetworkPreset preset) =>
      _profilesUsedBy(preset, (profile) => profile.pingTargets.isNotEmpty);

  /// The profiles a preset uses that have commands, each once, in preset
  /// order.
  List<NetworkProfile> profilesWithCommandsOf(NetworkPreset preset) =>
      _profilesUsedBy(preset, (profile) => profile.commands.isNotEmpty);

  bool isRunningPresetCommands(NetworkPreset preset) =>
      profilesWithCommandsOf(preset)
          .any((profile) => isRunningCommands(profile.name));

  bool canRunPresetCommands(NetworkPreset preset) =>
      profilesWithCommandsOf(preset).isNotEmpty &&
      !isRunningPresetCommands(preset);

  bool canStopPresetCommands(NetworkPreset preset) =>
      isRunningPresetCommands(preset) &&
      !_presetNamesStoppingCommands.contains(preset.name);

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
      _adaptersAreLoaded = true;
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

  /// With [confirmFreeingAddress], a static address already set on another
  /// adapter is offered to be freed: when confirmed, that adapter is
  /// switched to DHCP first. Without it, the refusal by Windows is reported.
  Future<void> applySelectedProfileToSelectedAdapter({
    ConfirmFreeingAddress? confirmFreeingAddress,
  }) async {
    final profile = _selectedProfile;
    if (!canApplySelectedProfile || profile == null) return;
    await _applyProfileToAdapter(
      profile,
      _selectedAdapterName!,
      confirmFreeingAddress: confirmFreeingAddress,
    );
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
    String adapterName, {
    ConfirmFreeingAddress? confirmFreeingAddress,
  }) async {
    if (!canConfigureAdapters) return;
    _selectedAdapterName = adapterName;
    await _applyProfileToAdapter(
      settings,
      adapterName,
      confirmFreeingAddress: confirmFreeingAddress,
    );
  }

  /// Applies every line of [preset]; a failing line does not stop the rest.
  /// Afterwards the ping targets of all successfully applied profiles are
  /// pinged.
  ///
  /// With [confirmFreeingAddress], addresses the preset needs that are set on
  /// other adapters are offered to be freed first (switching those adapters
  /// to DHCP), like when applying one profile. Declining applies nothing.
  Future<void> applyPreset(
    NetworkPreset preset, {
    ConfirmFreeingAddress? confirmFreeingAddress,
  }) async {
    if (!canApplyPresets) return;
    final freedAdapterNames = <String>[];
    if (confirmFreeingAddress != null) {
      final allFreed = await _freeAddressesNeededBy(
        preset,
        confirmFreeingAddress,
        freedAdapterNames,
      );
      if (!allFreed) return;
    }
    _startApplyingPreset(preset);
    final appliedProfiles = <NetworkProfile>[];
    await for (final presetResult in _presetApplier.applyPreset(
      preset,
      _library.profiles,
    )) {
      final result = await _retryLineAfterFreeingAddress(
        presetResult,
        confirmFreeingAddress,
        freedAdapterNames,
      );
      _recordPresetLineResult(preset.name, result);
      if (result.isSuccess) appliedProfiles.add(result.profile!);
    }
    _finishApplyingPreset(preset, freedAdapterNames: freedAdapterNames);
    await Future.wait([
      for (final profile in appliedProfiles) pingTargetsOf(profile),
    ]);
    // A profile used for two adapters runs its commands once; commands do
    // not know about adapters.
    for (final profile in {...appliedProfiles}) {
      await _runCommandsToRunAfterApply(profile);
    }
  }

  // Asks for every conflict before anything changes, so declining one leaves
  // all adapters as they were. Returns false when nothing may be applied.
  Future<bool> _freeAddressesNeededBy(
    NetworkPreset preset,
    ConfirmFreeingAddress confirmFreeingAddress,
    List<String> freedAdapterNames,
  ) async {
    _isApplying = true;
    notifyListeners();
    for (final assignment in preset.assignments) {
      final profile = _profileNamed(assignment.profileName);
      if (profile == null) continue;
      final conflict = _addressConflictOf(profile, assignment.adapterName);
      if (conflict == null) continue;
      if (!await _freeAddressIfConfirmed(conflict, confirmFreeingAddress)) {
        _isApplying = false;
        notifyListeners();
        return false;
      }
      freedAdapterNames.add(conflict.otherAdapterName);
    }
    return true;
  }

  // The adapter list can be out of date; when Windows still finds a line's
  // address on another adapter, the same question follows and that line is
  // applied once more.
  Future<PresetAssignmentResult> _retryLineAfterFreeingAddress(
    PresetAssignmentResult result,
    ConfirmFreeingAddress? confirmFreeingAddress,
    List<String> freedAdapterNames,
  ) async {
    final profile = result.profile;
    if (confirmFreeingAddress == null || profile == null) return result;
    if (result.outcome case ProfileAddressInUse(
      :final ipAddress,
      :final otherAdapterName,
    )) {
      final conflict = AddressConflict(
        profileName: profile.name,
        ipAddress: ipAddress,
        otherAdapterName: otherAdapterName,
      );
      if (!await _freeAddressIfConfirmed(conflict, confirmFreeingAddress)) {
        return result;
      }
      freedAdapterNames.add(otherAdapterName);
      final outcome = await _applier.applyProfileToAdapter(
        profile,
        result.assignment.adapterName,
      );
      return PresetAssignmentResult.applied(
        result.assignment,
        profile,
        outcome,
      );
    }
    return result;
  }

  /// Pings the targets of every profile in [preset] at the same time, without
  /// applying anything. Results appear per profile ([pingStatusesFor]).
  Future<void> pingPreset(NetworkPreset preset) async {
    if (!canPingPreset(preset)) return;
    await Future.wait([
      for (final profile in pingableProfilesOf(preset)) pingTargetsOf(profile),
    ]);
  }

  /// Runs the commands of every profile in [preset], profile after profile,
  /// without applying anything. Stop ends the running one and skips the
  /// rest, also of the following profiles.
  Future<void> runPresetCommands(NetworkPreset preset) async {
    if (!canRunPresetCommands(preset)) return;
    for (final profile in profilesWithCommandsOf(preset)) {
      if (_presetNamesStoppingCommands.contains(preset.name)) break;
      await runCommandsOf(profile);
    }
    _presetNamesStoppingCommands.remove(preset.name);
    _notifyListenersUnlessDisposed();
  }

  Future<void> stopPresetCommands(NetworkPreset preset) async {
    if (!canStopPresetCommands(preset)) return;
    _presetNamesStoppingCommands.add(preset.name);
    notifyListeners();
    await Future.wait([
      for (final profile in profilesWithCommandsOf(preset))
        if (isRunningCommands(profile.name)) stopCommandsOf(profile.name),
    ]);
  }

  /// Pings every target of [profile] until it answers or 10 seconds pass,
  /// updating [pingStatusesFor] as each result comes in.
  Future<void> pingTargetsOf(NetworkProfile profile) async {
    if (!canPingProfile(profile)) return;
    await _pingTargets(profile, profile.pingTargets);
  }

  /// Pings only [target] of [profile]; the other results stay as they are.
  Future<void> pingTarget(NetworkProfile profile, PingTarget target) async {
    if (!canPingTarget(profile, target)) return;
    await _pingTargets(profile, [target]);
  }

  /// Runs every command of [profile] one after another, including those not
  /// marked to run after applying. A failing command does not stop the rest.
  Future<void> runCommandsOf(NetworkProfile profile) => _runCommands(profile, [
    for (var index = 0; index < profile.commands.length; index++) index,
  ]);

  /// Runs only the command at [commandIndex] of [profile].
  Future<void> runCommand(NetworkProfile profile, int commandIndex) async {
    if (!canRunCommand(profile)) return;
    await _runCommands(profile, [commandIndex]);
  }

  /// Stops the running command of [profileName] and skips the ones after it.
  Future<void> stopCommandsOf(String profileName) async {
    if (!canStopCommands(profileName)) return;
    _profileNamesStoppingCommands.add(profileName);
    notifyListeners();
    await _activeCommandRunByProfileName[profileName]?.stop();
  }

  Future<void> openPluginFolder() async {
    try {
      await _folderOpener.openFolder(pluginFolderPath);
    } on FolderOpenException catch (error) {
      _statusMessage = StatusMessage.error(
        'Could not open the plugin folder: ${error.reason}',
      );
      notifyListeners();
    }
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
      _commandStatusesByProfileName.remove(originalName);
      _followRenameInLastAppliedProfiles(originalName, savedProfile.name);
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
      _commandStatusesByProfileName.remove(profileToDelete.name);
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

  /// Records that the help was opened automatically, so later starts skip
  /// it. Saved right away rather than when the help closes, so quitting
  /// during the help does not bring it back.
  Future<void> markHelpAsShown() async {
    _helpShownThisSession = true;
    notifyListeners();
    await _storeLibrary(_library.copyWith(helpWasShown: true));
  }

  /// Writes all profiles and presets to [filePath] for sharing.
  Future<void> exportUserData(String filePath) async {
    if (!canTransferUserData) return;
    try {
      // Personal settings stay out of a file meant for other users.
      await _libraryTransfer.exportLibrary(
        _library.copyWith(helpWasShown: false),
        filePath,
      );
      _statusMessage = StatusMessage.success(
        'Exported ${_describeCounts(_library)} to $filePath.',
      );
    } on NetworkProfileStorageException catch (error) {
      _statusMessage = StatusMessage.error(
        'Could not export user data: ${error.reason}',
      );
    }
    notifyListeners();
  }

  /// First step of importing a shared file: reads it and lists the preset
  /// adapters this PC does not have, so the user can map them before
  /// [completeImport]. Returns `null` (with an error message) when the file
  /// cannot be used.
  Future<LibraryImport?> prepareImport(String filePath) async {
    if (!canTransferUserData) return null;
    try {
      final importedLibrary = await _libraryTransfer.importLibrary(filePath);
      return LibraryImport(
        filePath: filePath,
        library: importedLibrary,
        unknownAdapterNames: [
          for (final adapterName in importedLibrary.adapterNamesUsedByPresets)
            if (!_isPresentAdapter(adapterName)) adapterName,
        ],
      );
    } on NetworkProfileStorageException catch (error) {
      _statusMessage = StatusMessage.error(
        'Could not import user data: ${error.reason}',
      );
      notifyListeners();
      return null;
    }
  }

  /// Second step: maps unknown adapters as chosen, then merges the file into
  /// the current data or replaces it (after a backup).
  Future<void> completeImport(
    LibraryImport libraryImport, {
    required LibraryImportMode mode,
    required Map<String, String> newAdapterNamesByImportedName,
  }) async {
    if (!canTransferUserData) return;
    final mappedLibrary = libraryImport.library.withAdaptersRenamed(
      newAdapterNamesByImportedName,
    );
    switch (mode) {
      case LibraryImportMode.merge:
        await _mergeImportedLibrary(mappedLibrary, libraryImport.filePath);
      case LibraryImportMode.replace:
        await _replaceWithImportedLibrary(
          mappedLibrary,
          libraryImport.filePath,
        );
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
    String adapterName, {
    ConfirmFreeingAddress? confirmFreeingAddress,
  }) async {
    _isApplying = true;
    _statusMessage = StatusMessage.progress(
      'Applying "${profile.name}" to $adapterName…',
    );
    notifyListeners();

    final result = await _applyFreeingAddressIfConfirmed(
      profile,
      adapterName,
      confirmFreeingAddress,
    );
    if (result == null) {
      _isApplying = false;
      notifyListeners();
      return;
    }
    final (:outcome, :freedAdapterName) = result;
    _showUpdatedAdapterAfter(outcome);
    _rememberAppliedProfile(outcome, profile, adapterName);
    _statusMessage = _describeOutcome(outcome, profile.name, adapterName);
    if (freedAdapterName != null && outcome is ProfileApplied) {
      _statusMessage = StatusMessage.success(
        '${_statusMessage!.text} "$freedAdapterName" was switched to DHCP.',
      );
    }
    _isApplying = false;
    notifyListeners();

    // Adapter actions are already enabled again here; the returned future
    // only completes after pinging and running commands so callers (and
    // tests) can await it. Commands start after pinging, because a command
    // like mapping a share needs the link, ARP and devices the ping waits
    // for.
    if (outcome is! ProfileApplied) return;
    await pingTargetsOf(profile);
    await _runCommandsToRunAfterApply(profile);
  }

  /// `null` when nothing was applied: the user kept the address on the other
  /// adapter, or switching that adapter to DHCP failed (the status line
  /// says which).
  Future<({ApplyProfileOutcome outcome, String? freedAdapterName})?>
  _applyFreeingAddressIfConfirmed(
    NetworkProfile profile,
    String adapterName,
    ConfirmFreeingAddress? confirmFreeingAddress,
  ) async {
    if (confirmFreeingAddress == null) {
      final outcome = await _applier.applyProfileToAdapter(
        profile,
        adapterName,
      );
      return (outcome: outcome, freedAdapterName: null);
    }

    String? freedAdapterName;
    final knownConflict = _addressConflictOf(profile, adapterName);
    if (knownConflict != null) {
      if (!await _freeAddressIfConfirmed(
        knownConflict,
        confirmFreeingAddress,
      )) {
        return null;
      }
      freedAdapterName = knownConflict.otherAdapterName;
    }

    var outcome = await _applier.applyProfileToAdapter(profile, adapterName);
    // The adapter list can be out of date; Windows then still finds the
    // address on another adapter.
    if (outcome case ProfileAddressInUse(
      :final ipAddress,
      :final otherAdapterName,
    )) {
      final conflict = AddressConflict(
        profileName: profile.name,
        ipAddress: ipAddress,
        otherAdapterName: otherAdapterName,
      );
      if (!await _freeAddressIfConfirmed(conflict, confirmFreeingAddress)) {
        return null;
      }
      freedAdapterName = otherAdapterName;
      outcome = await _applier.applyProfileToAdapter(profile, adapterName);
    }
    return (outcome: outcome, freedAdapterName: freedAdapterName);
  }

  // Uses the adapter list already on screen, so the question comes before
  // anything changes and costs no extra read.
  AddressConflict? _addressConflictOf(
    NetworkProfile profile,
    String adapterName,
  ) {
    final ipAddress = profile.ipAddress;
    if (!platform.allowsAddressOnOneAdapterOnly ||
        profile.addressingMode != AddressingMode.staticIp ||
        ipAddress == null) {
      return null;
    }
    final address = Ipv4Address.tryParse(ipAddress);
    if (address == null) return null;
    for (final adapter in _adapters) {
      final isOtherAdapter = !platform.isSameAdapterName(
        adapter.name,
        adapterName,
      );
      if (isOtherAdapter &&
          Ipv4Address.tryParse(adapter.adapter.ipAddress ?? '') == address) {
        return AddressConflict(
          profileName: profile.name,
          ipAddress: ipAddress,
          otherAdapterName: adapter.name,
        );
      }
    }
    return null;
  }

  // Switching to DHCP also works on a disconnected adapter, so the address
  // can always be freed this way.
  Future<bool> _freeAddressIfConfirmed(
    AddressConflict conflict,
    ConfirmFreeingAddress confirmFreeingAddress,
  ) async {
    final otherAdapterName = conflict.otherAdapterName;
    if (!await confirmFreeingAddress(conflict)) {
      _statusMessage = StatusMessage.error(
        'Not applied: ${conflict.ipAddress} stays on "$otherAdapterName".',
      );
      return false;
    }
    _statusMessage = StatusMessage.progress(
      'Switching "$otherAdapterName" to DHCP to free ${conflict.ipAddress}…',
    );
    _notifyListenersUnlessDisposed();

    final outcome = await _applier.applyProfileToAdapter(
      _dhcpShortcutProfile,
      otherAdapterName,
    );
    _showUpdatedAdapterAfter(outcome);
    _rememberAppliedProfile(outcome, _dhcpShortcutProfile, otherAdapterName);
    if (outcome is! ProfileApplied) {
      final reason = _describeOutcome(
        outcome,
        _dhcpShortcutProfile.name,
        otherAdapterName,
      ).text;
      _statusMessage = StatusMessage.error(
        'Not applied: could not switch "$otherAdapterName" to DHCP. $reason',
      );
      return false;
    }
    _statusMessage = StatusMessage.progress(
      'Applying "${conflict.profileName}"…',
    );
    _notifyListenersUnlessDisposed();
    return true;
  }

  Future<void> _runCommandsToRunAfterApply(NetworkProfile profile) =>
      _runCommands(profile, [
        for (final (index, command) in profile.commands.indexed)
          if (command.runAfterApply) index,
      ]);

  Future<void> _runCommands(
    NetworkProfile profile,
    List<int> commandIndexes,
  ) async {
    if (commandIndexes.isEmpty || isRunningCommands(profile.name)) return;
    _startRunningCommands(profile, commandIndexes);
    for (final index in commandIndexes) {
      if (_profileNamesStoppingCommands.contains(profile.name)) break;
      await _runCommand(profile.name, index, profile.commands[index]);
    }
    _finishRunningCommands(profile.name);
  }

  void _startRunningCommands(NetworkProfile profile, List<int> commandIndexes) {
    _profileNamesRunningCommands.add(profile.name);
    final statuses = _commandStatusesByProfileName.putIfAbsent(
      profile.name,
      () => {},
    );
    for (final index in commandIndexes) {
      statuses[index] = CommandStatus(
        profile.commands[index],
        CommandState.waiting,
      );
    }
    _notifyListenersUnlessDisposed();
  }

  Future<void> _runCommand(
    String profileName,
    int index,
    ProfileCommand command,
  ) async {
    _recordCommandStatus(
      profileName,
      index,
      CommandStatus(command, CommandState.running, startedAt: DateTime.now()),
    );
    _statusMessage = StatusMessage.progress(
      'Running "${command.displayName}"…',
    );
    _notifyListenersUnlessDisposed();

    final run = _profileCommandRunner.start(command);
    _activeCommandRunByProfileName[profileName] = run;
    final outcome = await run.outcome;
    _activeCommandRunByProfileName.remove(profileName);

    _recordCommandStatus(
      profileName,
      index,
      CommandStatus.ended(command, outcome),
    );
    _statusMessage = _describeCommandOutcome(command, outcome);
    _notifyListenersUnlessDisposed();
  }

  void _recordCommandStatus(
    String profileName,
    int index,
    CommandStatus status,
  ) {
    final statuses = _commandStatusesByProfileName[profileName];
    // The profile may have been edited or deleted while its commands ran.
    if (statuses == null || !statuses.containsKey(index)) return;
    statuses[index] = status;
  }

  // Commands after a stopped one never started.
  void _finishRunningCommands(String profileName) {
    final statuses = _commandStatusesByProfileName[profileName];
    if (statuses != null) {
      for (final MapEntry(key: index, value: status) in statuses.entries) {
        if (status.state == CommandState.waiting) {
          statuses[index] = CommandStatus(status.command, CommandState.skipped);
        }
      }
    }
    _profileNamesRunningCommands.remove(profileName);
    _profileNamesStoppingCommands.remove(profileName);
    _notifyListenersUnlessDisposed();
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
    if (outcome != null) {
      _showUpdatedAdapterAfter(outcome);
      final profile = result.profile;
      if (profile != null) {
        _rememberAppliedProfile(
          outcome,
          profile,
          result.assignment.adapterName,
        );
      }
    }
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

  void _finishApplyingPreset(
    NetworkPreset preset, {
    List<String> freedAdapterNames = const [],
  }) {
    final statuses = _lineStatusesByPresetName[preset.name] ?? [];
    final appliedCount = statuses
        .where((status) => status.state == PresetLineState.applied)
        .length;
    final freedNote = freedAdapterNames.isEmpty
        ? ''
        : ' Switched to DHCP to free an address: '
              '${freedAdapterNames.map((name) => '"$name"').join(', ')}.';
    final summary =
        'Preset "${preset.name}": $appliedCount of ${statuses.length} '
        'adapters switched.$freedNote';
    _statusMessage = appliedCount == statuses.length
        ? StatusMessage.success(summary)
        : StatusMessage.error('$summary See the preset for details.');
    _presetNameBeingApplied = null;
    _isApplying = false;
    _notifyListenersUnlessDisposed();
  }

  Future<void> _pingTargets(
    NetworkProfile profile,
    List<PingTarget> targets,
  ) async {
    _startPinging(profile, targets);
    await for (final result in _pingTargetsChecker.checkTargets(targets)) {
      _recordPingResult(profile.name, result);
    }
    _targetsBeingPingedByProfileName[profile.name]?.removeAll(targets);
    _notifyListenersUnlessDisposed();
  }

  void _startPinging(NetworkProfile profile, List<PingTarget> targets) {
    _targetsBeingPingedByProfileName
        .putIfAbsent(profile.name, () => {})
        .addAll(targets);
    final previousStatuses = _pingStatusesByProfileName[profile.name] ?? {};
    // Rebuilt in profile order, so results list like the targets do.
    _pingStatusesByProfileName[profile.name] = {
      for (final target in profile.pingTargets)
        if (targets.contains(target))
          target: PingTargetStatus(target, PingState.pinging)
        else
          target: ?previousStatuses[target],
    };
    _notifyListenersUnlessDisposed();
  }

  void _recordPingResult(String profileName, PingTargetResult result) {
    final statuses = _pingStatusesByProfileName[profileName];
    // The profile may have been edited or deleted while pinging.
    if (statuses == null || !statuses.containsKey(result.target)) return;
    statuses[result.target] = PingTargetStatus(
      result.target,
      result.isReachable ? PingState.reachable : PingState.unreachable,
      roundTripTime: result.roundTripTime,
    );
    _notifyListenersUnlessDisposed();
  }

  // Pinging runs up to 10 seconds and commands run without a time limit;
  // both may outlive the window.
  void _notifyListenersUnlessDisposed() {
    if (!_isDisposed) notifyListeners();
  }

  void _followRenameInLastAppliedProfiles(
    String? originalName,
    String newName,
  ) {
    if (originalName == null) return;
    _lastAppliedProfileNameByAdapterName.updateAll(
      (adapterName, profileName) =>
          profileName == originalName ? newName : profileName,
    );
  }

  List<NetworkProfile> _profilesUsedBy(
    NetworkPreset preset,
    bool Function(NetworkProfile profile) isWanted,
  ) {
    final profiles = <NetworkProfile>[];
    for (final assignment in preset.assignments) {
      final profile = _profileNamed(assignment.profileName);
      if (profile != null && isWanted(profile) && !profiles.contains(profile)) {
        profiles.add(profile);
      }
    }
    return profiles;
  }

  // Manual settings and the DHCP shortcut are not saved profiles; for those
  // the card falls back to recognizing a static profile by its settings.
  void _rememberAppliedProfile(
    ApplyProfileOutcome outcome,
    NetworkProfile profile,
    String adapterName,
  ) {
    if (outcome is! ProfileApplied) return;
    if (_library.profiles.contains(profile)) {
      _lastAppliedProfileNameByAdapterName[adapterName] = profile.name;
    } else {
      _lastAppliedProfileNameByAdapterName.remove(adapterName);
    }
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
      ProfileAddressInUse(:final ipAddress, :final otherAdapterName) =>
        StatusMessage.error(
          '$ipAddress is already set on adapter "$otherAdapterName". Windows '
          'allows an address on one adapter only, also when that adapter is '
          'not connected. Give "$otherAdapterName" another address or switch '
          'it to DHCP (double-click its card), then apply again.',
        ),
      ProfileRejectedBySystem(:final error) => StatusMessage.error(
        'The system refused the setting (exit code ${error.exitCode}): '
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

  StatusMessage _describeCommandOutcome(
    ProfileCommand command,
    ProfileCommandOutcome outcome,
  ) {
    final name = '"${command.displayName}"';
    return switch (outcome) {
      CommandFinished(:final exitCode, :final output, :final duration) =>
        outcome.isSuccess
            ? StatusMessage.success(
                _withOutput(
                  '$name finished in ${describeDuration(duration)}.',
                  output,
                ),
              )
            : StatusMessage.error(
                _withOutput(
                  '$name failed with exit code $exitCode after '
                  '${describeDuration(duration)}.',
                  output,
                ),
              ),
      CommandStopped(:final output, :final duration) => StatusMessage.error(
        _withOutput(
          '$name was stopped after ${describeDuration(duration)}.',
          output,
        ),
      ),
      CommandFileNotFound(:final resolvedPath) => StatusMessage.error(
        '$name: $resolvedPath does not exist. Put the file in the plugin '
        'folder or enter its full path.',
      ),
      CommandNotStarted(:final reason) => StatusMessage.error(
        '$name could not start: $reason',
      ),
    };
  }

  // The last lines usually explain the result; the full output is available
  // under the profile card.
  String _withOutput(String summary, String output) {
    const shownLineCount = 4;
    final lines = [
      for (final line in output.split('\n'))
        if (line.trim().isNotEmpty) line.trimRight(),
    ];
    if (lines.isEmpty) return summary;
    final lastLines = lines.skip(
      lines.length > shownLineCount ? lines.length - shownLineCount : 0,
    );
    return '$summary\n${lastLines.join('\n')}';
  }

  Future<void> _mergeImportedLibrary(
    NetworkProfileLibrary importedLibrary,
    String filePath,
  ) async {
    final mergeResult = _libraryMerger.merge(_library, importedLibrary);
    final isStored = await _storeLibrary(mergeResult.library);
    if (!isStored) return;
    final renamedNote = mergeResult.renamedCount == 0
        ? ''
        : ' ${mergeResult.renamedCount} got "(imported)" added because the '
              'name already existed.';
    _statusMessage = StatusMessage.success(
      'Imported ${_describeCounts(importedLibrary)} from $filePath.$renamedNote',
    );
  }

  Future<void> _replaceWithImportedLibrary(
    NetworkProfileLibrary importedLibrary,
    String filePath,
  ) async {
    final String? backupPath;
    try {
      backupPath = await _repository.backupLibrary();
    } on NetworkProfileStorageException catch (error) {
      // Without a backup the user could lose data they cannot get back.
      _statusMessage = StatusMessage.error(
        'Nothing was replaced, the backup failed: ${error.reason}',
      );
      return;
    }
    // Replacing takes over profiles and presets, not personal settings.
    final isStored = await _storeLibrary(
      importedLibrary.copyWith(helpWasShown: _library.helpWasShown),
    );
    if (!isStored) return;
    _forgetStateOfReplacedLibrary();
    final backupNote = backupPath == null ? '' : ' Backup: $backupPath';
    _statusMessage = StatusMessage.success(
      'Replaced your data with ${_describeCounts(importedLibrary)} from '
      '$filePath.$backupNote',
    );
  }

  void _forgetStateOfReplacedLibrary() {
    _pingStatusesByProfileName.clear();
    _commandStatusesByProfileName.clear();
    _lineStatusesByPresetName.clear();
    if (_profileNamed(_selectedProfileName) == null) {
      _selectedProfileName = null;
    }
  }

  String _describeCounts(NetworkProfileLibrary library) {
    String counted(int count, String noun) =>
        '$count $noun${count == 1 ? '' : 's'}';
    return '${counted(library.profiles.length, 'profile')} and '
        '${counted(library.presets.length, 'preset')}';
  }

  bool _isPresentAdapter(String adapterName) => _adapters.any(
    (adapter) => platform.isSameAdapterName(adapter.name, adapterName),
  );

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

enum CommandState { waiting, running, succeeded, failed, stopped, skipped }

/// State of one command, shown under its profile card.
class CommandStatus {
  const CommandStatus(this.command, this.state, {this.startedAt, this.outcome});

  CommandStatus.ended(this.command, ProfileCommandOutcome this.outcome)
    : state = switch (outcome) {
        CommandFinished(isSuccess: true) => CommandState.succeeded,
        CommandStopped() => CommandState.stopped,
        _ => CommandState.failed,
      },
      startedAt = null;

  final ProfileCommand command;
  final CommandState state;

  /// Set while running, so the view can show the elapsed time.
  final DateTime? startedAt;

  /// Set once the command has ended.
  final ProfileCommandOutcome? outcome;

  /// Everything the program wrote; empty when it wrote nothing or did not
  /// start.
  String get output => switch (outcome) {
    CommandFinished(:final output) || CommandStopped(:final output) => output,
    _ => '',
  };

  /// Short result for the profile card; while running the view shows the
  /// elapsed time instead.
  String get resultText => switch (outcome) {
    null => switch (state) {
      CommandState.waiting => 'Waiting…',
      CommandState.skipped => 'Not run',
      _ => 'Running…',
    },
    CommandFinished(:final exitCode, :final duration, :final isSuccess) =>
      isSuccess
          ? 'Done · ${describeDuration(duration)}'
          : 'Exit code $exitCode · ${describeDuration(duration)}',
    CommandStopped(:final duration) =>
      'Stopped · ${describeDuration(duration)}',
    CommandFileNotFound() => 'File not found',
    CommandNotStarted() => 'Could not start',
  };
}

/// "0.4 s", "12 s" or "3:05", for command running times.
String describeDuration(Duration duration) {
  if (duration < const Duration(seconds: 10)) {
    return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s';
  }
  if (duration < const Duration(minutes: 1)) return '${duration.inSeconds} s';
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '${duration.inMinutes}:$seconds';
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

enum LibraryImportMode { merge, replace }

/// A shared file that has been read but not applied yet; see
/// [MainViewModel.prepareImport].
class LibraryImport {
  const LibraryImport({
    required this.filePath,
    required this.library,
    required this.unknownAdapterNames,
  });

  final String filePath;
  final NetworkProfileLibrary library;

  /// Adapters used by the file's presets that this PC does not have.
  final List<String> unknownAdapterNames;

  /// Every command in the file with the profile it belongs to. They run with
  /// administrator rights, so the user is warned before importing.
  List<(String profileName, ProfileCommand command)> get commands => [
    for (final profile in library.profiles)
      for (final command in profile.commands) (profile.name, command),
  ];
}

enum StatusKind { progress, success, error }

/// One line of feedback shown at the bottom of the main window.
/// Asks the user whether [AddressConflict.otherAdapterName] may be switched
/// to DHCP, so its address can go to the profile being applied.
typedef ConfirmFreeingAddress = Future<bool> Function(AddressConflict conflict);

/// A static address the profile needs is already set on another adapter.
class AddressConflict {
  const AddressConflict({
    required this.profileName,
    required this.ipAddress,
    required this.otherAdapterName,
  });

  final String profileName;
  final String ipAddress;
  final String otherAdapterName;
}

class StatusMessage {
  const StatusMessage.progress(this.text) : kind = StatusKind.progress;
  const StatusMessage.success(this.text) : kind = StatusKind.success;
  const StatusMessage.error(this.text) : kind = StatusKind.error;

  final StatusKind kind;
  final String text;
}
