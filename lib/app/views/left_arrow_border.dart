import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Button outline shaped as an arrow pointing left: a triangular head on the
/// left and a body with rounded corners on the right.
///
/// Used for "Apply profile to selected adapter": the profile list is on the
/// right and the adapters on the left, so the arrow shows the direction in
/// which the profile goes.
class LeftArrowBorder extends OutlinedBorder {
  const LeftArrowBorder({super.side, this.cornerRadius = 8});

  final double cornerRadius;

  /// Width of the arrow head relative to the button height.
  static const headWidthFactor = 0.5;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final headWidth = rect.height * headWidthFactor;
    final radius = math.min(cornerRadius, rect.height / 2);
    return Path()
      ..moveTo(rect.left, rect.center.dy)
      ..lineTo(rect.left + headWidth, rect.top)
      ..lineTo(rect.right - radius, rect.top)
      ..arcToPoint(
        Offset(rect.right, rect.top + radius),
        radius: Radius.circular(radius),
      )
      ..lineTo(rect.right, rect.bottom - radius)
      ..arcToPoint(
        Offset(rect.right - radius, rect.bottom),
        radius: Radius.circular(radius),
      )
      ..lineTo(rect.left + headWidth, rect.bottom)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(getOuterPath(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  LeftArrowBorder copyWith({BorderSide? side}) =>
      LeftArrowBorder(side: side ?? this.side, cornerRadius: cornerRadius);

  @override
  ShapeBorder scale(double t) =>
      LeftArrowBorder(side: side.scale(t), cornerRadius: cornerRadius * t);
}
