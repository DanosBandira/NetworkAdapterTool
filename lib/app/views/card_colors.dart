import 'package:flutter/material.dart';

/// Background colors of the profile and preset cards, shared by the main
/// window and the examples in the help overlay so both look the same.
abstract final class CardColors {
  static const _profileLight = Color(0xFFFFF6D5);
  static const _profileDark = Color(0xFF3A3320);
  static const _selectedProfileLight = Color(0xFFFFE38C);
  static const _selectedProfileDark = Color(0xFF5E5024);
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

  /// Light purple.
  static Color preset(Brightness brightness) =>
      brightness == Brightness.dark ? _presetDark : _presetLight;
}
