import 'package:flutter/material.dart';

/// A titled section of a form that folds open and closed with a click on its
/// header.
///
/// The caller owns [isExpanded], so it can open a section itself, e.g. to
/// show a validation error. While folded, the header shows [summary] so the
/// user still sees what the section holds.
class CollapsibleSection extends StatelessWidget {
  const CollapsibleSection({
    super.key,
    required this.title,
    required this.isExpanded,
    required this.onToggle,
    required this.children,
    this.summary,
    this.hasError = false,
  });

  final String title;
  final bool isExpanded;
  final VoidCallback onToggle;
  final List<Widget> children;
  final String? summary;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
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
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            const SizedBox(width: 4),
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(width: 12),
            Expanded(
              child: !isExpanded && visibleSummary != null
                  ? Text(
                      visibleSummary,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    )
                  : const SizedBox.shrink(),
            ),
            if (hasError)
              Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
                semanticLabel: 'Contains errors',
              ),
            const SizedBox(width: 8),
            Tooltip(
              message: isExpanded ? 'Collapse' : 'Expand',
              child: Icon(
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
