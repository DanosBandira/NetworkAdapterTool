import 'package:flutter/material.dart';

/// A label on the left and a result on the right, filling the space between
/// them, e.g. "PLC · 10.100.10.1 ... 3 ms" in a profile card row.
///
/// Both shrink with an ellipsis when space runs out. The unused space stays
/// between the two, so buttons after this widget keep their place at the end
/// of the row.
class LabelAndResult extends StatelessWidget {
  const LabelAndResult({
    super.key,
    required this.label,
    required this.result,
    this.labelStyle,
  });

  final String label;
  final Widget result;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          flex: 3,
          child: Text(
            label,
            style: labelStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(flex: 2, child: result),
      ],
    );
  }
}
