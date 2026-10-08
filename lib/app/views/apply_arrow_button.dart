import 'package:flutter/material.dart';

import 'left_arrow_border.dart';

/// The main action, shaped as an arrow pointing from the profiles (right)
/// to the adapters (left).
class ApplyArrowButton extends StatelessWidget {
  const ApplyArrowButton({super.key, required this.onPressed});

  static const _height = 52.0;

  // Orange stands out from the green, red and yellow cards; the disabled
  // state keeps the theme's grey so it is clear when nothing can be applied.
  static const _background = Color(0xFFF57C00);
  static const _foreground = Colors.white;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    const headWidth = _height * LeftArrowBorder.headWidthFactor;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        shape: const LeftArrowBorder(),
        backgroundColor: _background,
        foregroundColor: _foreground,
        minimumSize: const Size(0, _height),
        // Extra room on the left keeps the text out of the arrow head.
        padding: const EdgeInsets.fromLTRB(headWidth + 12, 0, 28, 0),
        textStyle: Theme.of(context).textTheme.titleMedium,
      ),
      child: const Text('Apply profile to selected adapter'),
    );
  }
}
