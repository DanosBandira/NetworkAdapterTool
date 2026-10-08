import 'package:flutter/material.dart';

/// Help overlay explaining the main window: adapters, profiles, presets and
/// import/export. Opened from the app bar; closes with the close button, Esc
/// or a click next to it.
///
/// The text lives in [_helpSections] so it can be updated without touching
/// the layout.
class HelpView extends StatelessWidget {
  const HelpView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.help_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'How to use Network Adapter Tool',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close help',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final section in _helpSections)
                      _HelpSectionView(section: section),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpSectionView extends StatelessWidget {
  const _HelpSectionView({required this.section});

  final _HelpSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(section.icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(section.title, style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 6),
          for (final point in section.points)
            Padding(
              padding: const EdgeInsets.only(left: 28, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(
                    child: Text(point, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HelpSection {
  const _HelpSection({
    required this.icon,
    required this.title,
    required this.points,
  });

  final IconData icon;
  final String title;
  final List<String> points;
}

const _helpSections = [
  _HelpSection(
    icon: Icons.lan_outlined,
    title: 'Adapters (left)',
    points: [
      'Every network adapter of this PC.',
      'Green card = connected, red card = not connected.',
      'Double-click a card to change its settings directly.',
      'Use the refresh button to read the adapters again, e.g. after '
          'plugging in a cable. Reading takes a few seconds.',
    ],
  ),
  _HelpSection(
    icon: Icons.bookmark_outline,
    title: 'Profiles (top right)',
    points: [
      'A profile is a saved set of settings that is not tied to an adapter: '
          'you choose the adapter when applying it.',
      'To apply: select an adapter and a profile, then click the orange '
          'arrow button at the bottom.',
      'Ping targets (optional, e.g. "PLC 10.100.10.1") are pinged after '
          'applying, or with the Ping button. Each one is tried for up to '
          '10 seconds; the result shows under the profile.',
    ],
  ),
  _HelpSection(
    icon: Icons.playlist_play,
    title: 'Presets (bottom right)',
    points: [
      'A preset links adapters to profiles. With one click on Apply, one or '
          'more adapters are set to the right profile and their ping targets '
          'are pinged automatically, so you can switch setups quickly.',
      'Example: "Ethernet ← Machine" and "Wi-Fi ← Office".',
      'Ping pings the targets of all profiles in the preset, without '
          'changing anything.',
    ],
  ),
  _HelpSection(
    icon: Icons.swap_vert,
    title: 'Import and Export (top right)',
    points: [
      'Your changes are saved automatically; you never need to save.',
      'Export writes all profiles and presets to a file you choose, to share '
          'with colleagues or keep as a backup.',
      'Import loads the profiles and presets from such a file.',
      'If the file uses adapters this PC does not have, you can choose which '
          'local adapter to use instead while importing.',
    ],
  ),
  _HelpSection(
    icon: Icons.lightbulb_outline,
    title: 'Good to know',
    points: [
      'Windows can only switch an adapter from DHCP to a static IP while it '
          'is connected. Plug in the cable first; the app tells you when this '
          'is the case.',
      'Switching to DHCP, or between static IPs, also works on an adapter '
          'that is not connected.',
      'The app needs administrator rights to change network settings, which '
          'is why Windows asks for permission when it starts.',
      r'Profiles and presets are stored in '
          r'%APPDATA%\NetworkAdapterTool\user_data.json.',
    ],
  ),
];
