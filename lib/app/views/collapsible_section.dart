import 'package:flutter/material.dart';

/// A titled section of a form that folds open and closed with a click on its
/// header.
///
/// The caller owns [isExpanded], so it can open a section itself, e.g. to
/// show a validation error. While folded, the header shows [summary] so the
/// user still sees what the section holds. [headerAction] (e.g. a "Ping
/// all" button) sits in the header, so it works folded and open.
class CollapsibleSection extends StatelessWidget {
  const CollapsibleSection({
    super.key,
    required this.title,
    required this.isExpanded,
    required this.onToggle,
    required this.children,
    this.summary,
    this.hasError = false,
    this.headerAction,
    this.margin = const EdgeInsets.only(top: 12),
  });

  final String title;
  final bool isExpanded;
  final VoidCallback onToggle;
  final List<Widget> children;
  final String? summary;
  final bool hasError;
  final Widget? headerAction;
  final EdgeInsetsGeometry margin;

  static const double _headerHorizontalPadding = 8;
  static const double _gapBeforeArrow = 8;
  static const double _arrowSize = 24;
  static const double _childrenHorizontalPadding = 12;

  /// Extra space a child row leaves at its end so its buttons line up under
  /// [headerAction], which sits left of the fold arrow.
  static const double endInsetToAlignWithHeaderAction =
      _headerHorizontalPadding +
      _arrowSize +
      _gapBeforeArrow -
      _childrenHorizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        border: Border.all(color: _borderColor(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _childrenHorizontalPadding,
                      0,
                      _childrenHorizontalPadding,
                      8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final visibleSummary = summary;
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _headerHorizontalPadding,
          vertical: 10,
        ),
        child: Row(
          children: [
            const SizedBox(width: 4),
            // One text, so a narrow header cuts off the summary first
            // instead of overflowing.
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: title, style: theme.textTheme.titleSmall),
                    if (!isExpanded && visibleSummary != null)
                      TextSpan(
                        text: '   $visibleSummary',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasError)
              Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
                semanticLabel: 'Contains errors',
              ),
            ?headerAction,
            const SizedBox(width: _gapBeforeArrow),
            Tooltip(
              message: isExpanded ? 'Collapse' : 'Expand',
              child: Icon(
                size: _arrowSize,
                isExpanded ? Icons.expand_less : Icons.expand_more,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _borderColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return hasError ? colorScheme.error : colorScheme.outlineVariant;
  }
}
