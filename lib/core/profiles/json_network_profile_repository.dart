import 'dart:convert';
import 'dart:io';

import '../contracts/network_profile_repository.dart';
import '../models/network_profile.dart';

/// Stores all profiles in one indented JSON file, by default
/// `%APPDATA%\NetworkProfileSwitcher\profiles.json`.
///
/// The file carries a format version so an older app version refuses a file
/// written by a newer one instead of overwriting fields it does not know.
class JsonNetworkProfileRepository implements NetworkProfileRepository {
  const JsonNetworkProfileRepository(this._profilesFile);

  factory JsonNetworkProfileRepository.inRoamingAppData() {
    final roamingAppDataPath = Platform.environment['APPDATA'];
    if (roamingAppDataPath == null) {
      throw const NetworkProfileStorageException(
        'The APPDATA environment variable is not set.',
      );
    }
    return JsonNetworkProfileRepository(
      File('$roamingAppDataPath\\NetworkProfileSwitcher\\profiles.json'),
    );
  }

  // Version history:
  // 1: initial format.
  // 2: profiles may contain "pingTargets". Version 1 files load unchanged;
  //    the bump stops an older app from saving and dropping ping targets.
  static const _currentFormatVersion = 2;

  final File _profilesFile;

  @override
  Future<List<NetworkProfile>> loadAllProfiles() async {
    if (!await _profilesFile.exists()) return [];
    final fileContent = await _readProfilesFile();
    return _parseProfiles(fileContent);
  }

  @override
  Future<void> saveAllProfiles(List<NetworkProfile> profiles) async {
    final fileContent = _serializeProfiles(profiles);
    await _replaceProfilesFile(fileContent);
  }

  Future<String> _readProfilesFile() async {
    try {
      return await _profilesFile.readAsString();
    } on FileSystemException catch (error) {
      throw NetworkProfileStorageException(
        'Cannot read ${_profilesFile.path}: ${error.message}',
      );
    }
  }

  List<NetworkProfile> _parseProfiles(String fileContent) {
    try {
      final document = jsonDecode(fileContent) as Map<String, Object?>;
      _ensureFormatVersionIsSupported(document['formatVersion'] as int?);
      final profileEntries = document['profiles'] as List<Object?>;
      return [
        for (final profileEntry in profileEntries)
          NetworkProfile.fromJson(profileEntry as Map<String, Object?>),
      ];
    } on FormatException catch (error) {
      throw NetworkProfileStorageException(
        '${_profilesFile.path} is not valid JSON: ${error.message}',
      );
    } on TypeError catch (error) {
      throw NetworkProfileStorageException(
        '${_profilesFile.path} has an unexpected structure: $error',
      );
    } on ArgumentError catch (error) {
      // Thrown by AddressingMode.values.byName for an unknown mode.
      throw NetworkProfileStorageException(
        '${_profilesFile.path} contains an unknown value: ${error.message}',
      );
    }
  }

  void _ensureFormatVersionIsSupported(int? formatVersion) {
    if (formatVersion == null || formatVersion > _currentFormatVersion) {
      throw NetworkProfileStorageException(
        '${_profilesFile.path} has format version $formatVersion; this app '
        'supports up to $_currentFormatVersion.',
      );
    }
  }

  String _serializeProfiles(List<NetworkProfile> profiles) {
    final document = {
      'formatVersion': _currentFormatVersion,
      'profiles': [for (final profile in profiles) profile.toJson()],
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
