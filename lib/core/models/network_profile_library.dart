import 'network_preset.dart';
import 'network_profile.dart';

/// Everything the user has saved: profiles and the presets that reference
/// them. Stored together so a profile rename and the matching preset update
/// are written in one go.
class NetworkProfileLibrary {
  const NetworkProfileLibrary({
    this.profiles = const [],
    this.presets = const [],
  });

  final List<NetworkProfile> profiles;
  final List<NetworkPreset> presets;

  NetworkProfileLibrary copyWith({
    List<NetworkProfile>? profiles,
    List<NetworkPreset>? presets,
  }) {
    return NetworkProfileLibrary(
      profiles: profiles ?? this.profiles,
      presets: presets ?? this.presets,
    );
  }
}
