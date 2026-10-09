import 'package:flutter/material.dart';

import 'help_examples.dart';

/// Help overlay that walks through the app in steps: per step an example of
/// that part of the app (see help_examples.dart) and a few short points.
/// Opened from the app bar; closes with the close button, Done on the last
/// step, Esc or a click next to it.
///
/// The steps live in [_helpSteps] so text and order can be changed without
/// touching the layout.
class HelpView extends StatefulWidget {
  const HelpView({super.key});

  @override
  State<HelpView> createState() => _HelpViewState();
}

class _HelpViewState extends State<HelpView> {
  int _stepIndex = 0;

  _HelpStep get _step => _helpSteps[_stepIndex];
  bool get _isFirstStep => _stepIndex == 0;
  bool get _isLastStep => _stepIndex == _helpSteps.length - 1;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
                child: _HelpStepView(
                  // A new key per step resets the scroll position.
                  key: ValueKey(_stepIndex),
                  step: _step,
                ),
              ),
            ),
            const Divider(height: 1),
            _buildNavigation(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
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
          Text(
            'Step ${_stepIndex + 1} of ${_helpSteps.length}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          IconButton(
            tooltip: 'Close help',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigation(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isFirstStep ? null : _goToPreviousStep,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
              ),
            ),
          ),
          Expanded(child: _buildStepDots(context)),
          SizedBox(
            width: 120,
            child: Align(
              alignment: Alignment.centerRight,
              child: _isLastStep
                  ? FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    )
                  : FilledButton.icon(
                      onPressed: _goToNextStep,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Next'),
                      iconAlignment: IconAlignment.end,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // The dots double as navigation: clicking one jumps to that step.
  Widget _buildStepDots(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < _helpSteps.length; index++)
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => setState(() => _stepIndex = index),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Icon(
                Icons.circle,
                size: 10,
                color: index == _stepIndex
                    ? colors.primary
                    : colors.outlineVariant,
              ),
            ),
          ),
      ],
    );
  }

  void _goToPreviousStep() => setState(() => _stepIndex--);

  void _goToNextStep() => setState(() => _stepIndex++);
}

class _HelpStepView extends StatelessWidget {
  const _HelpStepView({super.key, required this.step});

  final _HelpStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final example = step.example;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(step.icon, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Text(step.title, style: theme.textTheme.titleLarge),
          ],
        ),
        if (example != null) ...[
          const SizedBox(height: 24),
          Center(child: example),
        ],
        const SizedBox(height: 24),
        for (final point in step.points)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(point, style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
      ],
    );
  }
}

class _HelpStep {
  const _HelpStep({
    required this.icon,
    required this.title,
    required this.points,
    this.example,
  });

  final IconData icon;
  final String title;
  final List<String> points;

  /// Picture of the part of the app this step is about; `null` for a text
  /// only step.
  final Widget? example;
}

const _helpSteps = [
  _HelpStep(
    icon: Icons.edit_outlined,
    title: 'Change an adapter directly',
    example: ChangeAdapterExample(),
    points: ['Double-click a card to change its settings directly.'],
  ),
  _HelpStep(
    icon: Icons.lan_outlined,
    title: 'Adapters (left)',
    example: AdapterColorsExample(),
    points: [
      'Every network adapter of this PC.',
      'Green card = connected, red card = not connected.',
      'Use the refresh button to read the adapters again, e.g. after '
          'plugging in a cable. Reading takes a few seconds.',
    ],
  ),
  _HelpStep(
    icon: Icons.bookmark_outline,
    title: 'Profiles (top right)',
    example: ApplyProfileExample(),
    points: [
      'A profile is a saved set of settings that is not tied to an adapter: '
          'you choose the adapter when applying it.',
      'To apply: select an adapter and a profile, then click the orange '
          'arrow button at the bottom.',
      'Ping targets (optional, e.g. "PLC 10.100.10.1") are pinged after '
          'applying, or with the Ping button. Each one is tried for up to '
          '10 seconds; the result shows under the profile.',
      'Commands (optional) run a program or script (.exe, .ps1, .bat, .cmd) '
          'after the ping targets, or with the Run button; Stop ends it. The '
          'output shows at the bottom and under the profile.',
    ],
  ),
  _HelpStep(
    icon: Icons.playlist_play,
    title: 'Presets (bottom right)',
    example: PresetExample(),
    points: [
      'A preset links adapters to profiles. With one click on Apply, one or '
          'more adapters are set to the right profile and their ping targets '
          'are pinged automatically, so you can switch setups quickly.',
      'Example: "Ethernet ← Machine" and "Wi-Fi ← Office".',
      'Ping pings the targets of all profiles in the preset, without '
          'changing anything.',
    ],
  ),
  _HelpStep(
    icon: Icons.swap_vert,
    title: 'Import and Export (top right)',
    example: ImportExportExample(),
    points: [
      'Your changes are saved automatically; you never need to save.',
      'Export writes all profiles and presets to a file you choose, to share '
          'with colleagues or keep as a backup.',
      'Import loads the profiles and presets from such a file.',
      'If the file uses adapters this PC does not have, you can choose which '
          'local adapter to use instead while importing.',
      'Import warns when the file contains commands. Only import files from '
          'people you trust.',
    ],
  ),
  _HelpStep(
    icon: Icons.lightbulb_outline,
    title: 'Good to know',
    points: [
      'Windows can only switch an adapter from DHCP to a static IP while it '
          'is connected. Plug in the cable first; the app tells you when this '
          'is the case.',
      'Switching to DHCP, or between static IPs, also works on an adapter '
          'that is not connected.',
      'The app needs administrator rights to change network settings, which '
          'is why Windows asks for permission when it starts. Commands run '
          'with the same rights.',
      'A command file without a folder, e.g. "tool.exe", is looked up in the '
          '"plugins" folder next to the app. Keep that folder when you update '
          'the app.',
      r'Profiles and presets are stored in '
          r'%APPDATA%\NetworkAdapterTool\user_data.json.',
    ],
  ),
];
