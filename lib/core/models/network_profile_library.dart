import 'network_preset.dart';
import 'network_profile.dart';

/// Everything the user has saved: profiles, the presets that reference them
/// and a few personal settings. Stored together so a profile rename and the
/// matching preset update are written in one go.
class NetworkProfileLibrary {
  const NetworkProfileLibrary({
    this.profiles = const [],
    this.presets = const [],
    this.helpWasShown = false,
  });

  final List<NetworkProfile> profiles;
  final List<NetworkPreset> presets;

  /// Whether the help was opened automatically once. A personal setting:
  /// not exported and not taken over from an imported file.
  final bool helpWasShown;

  /// Every adapter name used by a preset, each once, in preset order.
  List<String> get adapterNamesUsedByPresets =>
      {for (final preset in presets) ...preset.adapterNames}.toList();

  NetworkProfileLibrary withAdaptersRenamed(
    Map<String, String> newAdapterNamesByOldName,
  ) {
    return copyWith(
      presets: [
        for (final preset in presets)
          preset.withAdaptersRenamed(newAdapterNamesByOldName),
      ],
    );
  }

  NetworkProfileLibrary copyWith({
    List<NetworkProfile>? profiles,
    List<NetworkPreset>? presets,
    bool? helpWasShown,
  }) {
    return NetworkProfileLibrary(
      profiles: profiles ?? this.profiles,
      presets: presets ?? this.presets,
      helpWasShown: helpWasShown ?? this.helpWasShown,
    );
  }
}
