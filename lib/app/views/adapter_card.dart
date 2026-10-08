import 'package:flutter/material.dart';

import '../view_models/network_adapter_view_model.dart';

/// One adapter in the adapter grid: green when connected, red otherwise,
/// darker with a border when selected. Also shown as an example in the
/// help overlay.
class AdapterCard extends StatelessWidget {
  const AdapterCard({
    super.key,
    required this.adapter,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
  });

  static const _connectedBackgroundLight = Color(0xFFE6F4EA);
  static const _connectedBackgroundDark = Color(0xFF1E3A2A);
  static const _notConnectedBackgroundLight = Color(0xFFFCE8E6);
  static const _notConnectedBackgroundDark = Color(0xFF3D2222);
  static const _selectedConnectedBackgroundLight = Color(0xFFB4DDBF);
  static const _selectedConnectedBackgroundDark = Color(0xFF2E5C40);
  static const _selectedNotConnectedBackgroundLight = Color(0xFFF4B6AE);
  static const _selectedNotConnectedBackgroundDark = Color(0xFF633030);

  final NetworkAdapterViewModel adapter;
  final bool isSelected;
  final VoidCallback onTap;

  /// Opens the adapter settings dialog; `null` while adapters are busy.
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = adapter.isConnected ? colors.primary : colors.outline;
    final detailStyle = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: _connectionBackground(theme.brightness),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: colors.primary, width: 2)
            : BorderSide.none,
      ),
      // Select on the raw pointer-down: with a double-tap handler, the tap
      // gesture (even onTapDown) only resolves after the double-tap timeout,
      // which made selecting feel laggy.
      child: Listener(
        onPointerDown: (_) => onTap(),
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lan_outlined, color: statusColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        adapter.name,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      adapter.addressingModeText,
                      style: theme.textTheme.labelLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  adapter.statusText,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  adapter.description,
                  style: detailStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                for (final detailLine in [
                  adapter.addressText,
                  ?adapter.gatewayText,
                  ?adapter.dnsServersText,
                ])
                  Text(detailLine, style: detailStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // The selected card keeps its connection color, only a darker shade.
  Color _connectionBackground(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch ((adapter.isConnected, isSelected, isDark)) {
      (true, false, false) => _connectedBackgroundLight,
      (true, false, true) => _connectedBackgroundDark,
      (true, true, false) => _selectedConnectedBackgroundLight,
      (true, true, true) => _selectedConnectedBackgroundDark,
      (false, false, false) => _notConnectedBackgroundLight,
      (false, false, true) => _notConnectedBackgroundDark,
      (false, true, false) => _selectedNotConnectedBackgroundLight,
      (false, true, true) => _selectedNotConnectedBackgroundDark,
    };
  }
}
