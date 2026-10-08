import 'dart:convert';
import 'dart:io';

import '../contracts/network_profile_repository.dart';
import '../models/network_preset.dart';
import '../models/network_profile.dart';
import '../models/network_profile_library.dart';

/// Stores all profiles and presets in one indented JSON file, by default
/// `%APPDATA%\NetworkAdapterTool\user_data.json`.
///
/// The file carries a format version so an older app version refuses a file
/// written by a newer one instead of overwriting fields it does not know.
class JsonNetworkProfileRepository implements NetworkProfileRepository {
  const JsonNetworkProfileRepository(this._userDataFile);

  factory JsonNetworkProfileRepository.inRoamingAppData() {
    final roamingAppDataPath = Platform.environment['APPDATA'];
    if (roamingAppDataPath == null) {
      throw const NetworkProfileStorageException(
        'The APPDATA environment variable is not set.',
      );
    }
    return JsonNetworkProfileRepository(
      File('$roamingAppDataPath\\NetworkAdapterTool\\user_data.json'),
    );
  }

  // Version history:
  // 1: initial format.
  // 2: profiles may contain "pingTargets".
  // 3: top-level "presets" list.
  // Older files load unchanged; each bump stops an older app from saving and
  // dropping data it does not know.
  static const _currentFormatVersion = 3;

  final File _userDataFile;

  @override
  Future<NetworkProfileLibrary> loadLibrary() async {
    if (!await _userDataFile.exists()) return const NetworkProfileLibrary();
    final fileContent = await _readFile(_userDataFile);
    return _parseLibrary(fileContent, _userDataFile);
  }

  @override
  Future<String?> backupLibrary() async {
    if (!await _userDataFile.exists()) return null;
    final backupFile = File(_backupPathFor(DateTime.now()));
    try {
      await _userDataFile.copy(backupFile.path);
      return backupFile.path;
    } on FileSystemException catch (error) {
      throw NetworkProfileStorageException(
        'Cannot back up ${_userDataFile.path}: ${error.message}',
      );
    }
  }

  // e.g. user_data.backup-20261007-143005.json next to user_data.json.
  String _backupPathFor(DateTime moment) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final timestamp =
        '${moment.year}${twoDigits(moment.month)}${twoDigits(moment.day)}-'
        '${twoDigits(moment.hour)}${twoDigits(moment.minute)}'
        '${twoDigits(moment.second)}';
    final path = _userDataFile.path;
    final extensionStart = path.lastIndexOf('.');
    return extensionStart == -1
        ? '$path.backup-$timestamp'
        : '${path.substring(0, extensionStart)}.backup-$timestamp'
              '${path.substring(extensionStart)}';
  }

  @override
  Future<void> saveLibrary(NetworkProfileLibrary library) async {
    final fileContent = _serializeLibrary(library);
    await _replaceUserDataFile(fileContent);
  }

  Future<String> _readFile(File file) async {
    try {
      return await file.readAsString();
    } on FileSystemException catch (error) {
      throw NetworkProfileStorageException(
        'Cannot read ${file.path}: ${error.message}',
      );
    }
  }

  NetworkProfileLibrary _parseLibrary(String fileContent, File file) {
    try {
      final document = jsonDecode(fileContent) as Map<String, Object?>;
      _ensureFormatVersionIsSupported(document['formatVersion'] as int?, file);
      return NetworkProfileLibrary(
        profiles: [
          for (final profileEntry in document['profiles'] as List<Object?>)
            NetworkProfile.fromJson(profileEntry as Map<String, Object?>),
        ],
        presets: [
          for (final presetEntry
              in document['presets'] as List<Object?>? ?? const <Object?>[])
            NetworkPreset.fromJson(presetEntry as Map<String, Object?>),
        ],
        helpWasShown: document['helpWasShown'] as bool? ?? false,
      );
    } on FormatException catch (error) {
      throw NetworkProfileStorageException(
        '${file.path} is not valid JSON: ${error.message}',
      );
    } on TypeError catch (error) {
      throw NetworkProfileStorageException(
        '${file.path} has an unexpected structure: $error',
      );
    } on ArgumentError catch (error) {
      // Thrown by AddressingMode.values.byName for an unknown mode.
      throw NetworkProfileStorageException(
        '${file.path} contains an unknown value: ${error.message}',
      );
    }
  }

  void _ensureFormatVersionIsSupported(int? formatVersion, File file) {
    if (formatVersion == null || formatVersion > _currentFormatVersion) {
      throw NetworkProfileStorageException(
        '${file.path} has format version $formatVersion; this app '
        'supports up to $_currentFormatVersion.',
      );
    }
  }

  String _serializeLibrary(NetworkProfileLibrary library) {
    final document = {
      'formatVersion': _currentFormatVersion,
      'profiles': [for (final profile in library.profiles) profile.toJson()],
      'presets': [for (final preset in library.presets) preset.toJson()],
      // Added without a format version bump: older app versions ignore the
      // key, so at worst they show the help once more.
      if (library.helpWasShown) 'helpWasShown': true,
    };
    // Indented so users can read or back up the file by hand.
    return const JsonEncoder.withIndent('  ').convert(document);
  }

  // Write to a temporary file first and then rename it over the original, so
  // a crash or power loss mid-write never leaves a truncated profile file.
  Future<void> _replaceUserDataFile(String fileContent) async {
    final temporaryFile = File('${_userDataFile.path}.tmp');
    try {
      await _userDataFile.parent.create(recursive: true);
      await temporaryFile.writeAsString(fileContent, flush: true);
      await temporaryFile.rename(_userDataFile.path);
    } on FileSystemException catch (error) {
      throw NetworkProfileStorageException(
        'Cannot write ${_userDataFile.path}: ${error.message}',
      );
    }
  }
}
