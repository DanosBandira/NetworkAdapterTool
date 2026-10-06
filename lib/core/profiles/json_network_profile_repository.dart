import 'dart:convert';
import 'dart:io';

import '../contracts/network_profile_repository.dart';
import '../models/network_preset.dart';
import '../models/network_profile.dart';
import '../models/network_profile_library.dart';

/// Stores all profiles and presets in one indented JSON file, by default
/// `%APPDATA%\NetworkAdapterTool\profiles.json`.
///
/// The file carries a format version so an older app version refuses a file
/// written by a newer one instead of overwriting fields it does not know.
class JsonNetworkProfileRepository implements NetworkProfileRepository {
  const JsonNetworkProfileRepository(
    this._profilesFile, {
    this._legacyProfilesFile,
  });

  factory JsonNetworkProfileRepository.inRoamingAppData() {
    final roamingAppDataPath = Platform.environment['APPDATA'];
    if (roamingAppDataPath == null) {
      throw const NetworkProfileStorageException(
        'The APPDATA environment variable is not set.',
      );
    }
    return JsonNetworkProfileRepository(
      File('$roamingAppDataPath\\NetworkAdapterTool\\profiles.json'),
      // The app was called "NetworkProfileSwitcher" until 2026-10-06.
      legacyProfilesFile: File(
        '$roamingAppDataPath\\NetworkProfileSwitcher\\profiles.json',
      ),
    );
  }

  // Version history:
  // 1: initial format.
  // 2: profiles may contain "pingTargets".
  // 3: top-level "presets" list.
  // Older files load unchanged; each bump stops an older app from saving and
  // dropping data it does not know.
  static const _currentFormatVersion = 3;

  final File _profilesFile;

  // Read only while the current file does not exist yet; the next save
  // writes to the current location. The legacy file is never changed, so it
  // stays as a backup.
  final File? _legacyProfilesFile;

  @override
  Future<NetworkProfileLibrary> loadLibrary() async {
    final fileToRead = await _existingProfilesFile();
    if (fileToRead == null) return const NetworkProfileLibrary();
    final fileContent = await _readFile(fileToRead);
    return _parseLibrary(fileContent, fileToRead);
  }

  @override
  Future<void> saveLibrary(NetworkProfileLibrary library) async {
    final fileContent = _serializeLibrary(library);
    await _replaceProfilesFile(fileContent);
  }

  Future<File?> _existingProfilesFile() async {
    if (await _profilesFile.exists()) return _profilesFile;
    final legacyProfilesFile = _legacyProfilesFile;
    if (legacyProfilesFile != null && await legacyProfilesFile.exists()) {
      return legacyProfilesFile;
    }
    return null;
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
    };
    // Indented so users can read or back up the file by hand.
    return const JsonEncoder.withIndent('  ').convert(document);
  }

  // Write to a temporary file first and then rename it over the original, so
  // a crash or power loss mid-write never leaves a truncated profile file.
  Future<void> _replaceProfilesFile(String fileContent) async {
    final temporaryFile = File('${_profilesFile.path}.tmp');
    try {
      await _profilesFile.parent.create(recursive: true);
      await temporaryFile.writeAsString(fileContent, flush: true);
      await temporaryFile.rename(_profilesFile.path);
    } on FileSystemException catch (error) {
      throw NetworkProfileStorageException(
        'Cannot write ${_profilesFile.path}: ${error.message}',
      );
    }
  }
}
