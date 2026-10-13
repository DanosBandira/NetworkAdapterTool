import 'package:flutter/material.dart';

/// Colors of the profile and preset cards (and of the active profile on an
/// adapter card), shared by the main window and the examples in the help
/// overlay so both look the same.
abstract final class CardColors {
  static const _profileLight = Color(0xFFFFF6D5);
  static const _profileDark = Color(0xFF3A3320);
  static const _selectedProfileLight = Color(0xFFFFE38C);
  static const _selectedProfileDark = Color(0xFF5E5024);
  // Dark enough to read on the light green and red adapter cards.
  static const _activeProfileTextLight = Color(0xFF7A5F00);
  static const _activeProfileTextDark = Color(0xFFFFD54F);
  static const _presetLight = Color(0xFFEDE7F6);
  static const _presetDark = Color(0xFF2E2640);

  /// Light yellow; a darker yellow when selected.
  static Color profile(Brightness brightness, {required bool isSelected}) {
    final isDark = brightness == Brightness.dark;
    return switch ((isSelected, isDark)) {
      (false, false) => _profileLight,
      (false, true) => _profileDark,
      (true, false) => _selectedProfileLight,
      (true, true) => _selectedProfileDark,
    };
  }

  /// Dark yellow text for "Profile ... active" on an adapter card, so it
  /// reads as belonging to the yellow profile cards.
  static Color activeProfileText(Brightness brightness) =>
      brightness == Brightness.dark
      ? _activeProfileTextDark
      : _activeProfileTextLight;

  /// Light purple.
  static Color preset(Brightness brightness) =>
      brightness == Brightness.dark ? _presetDark : _presetLight;
}
