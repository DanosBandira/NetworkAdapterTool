import '../../core/platform/host_platform.dart';

/// UI wording that differs between Windows and Linux: which command files
/// run, with which rights, and the platform notes in the help.
class PlatformTexts {
  const PlatformTexts._({
    required this.commandFileTypes,
    required this.commandFileExtensions,
    required this.commandFileHint,
    required this.commandRights,
    required this.goodToKnow,
  });

  factory PlatformTexts.of(HostPlatform platform) => switch (platform) {
    HostPlatform.windows => _windows,
    HostPlatform.linux => _linux,
  };

  static const _windows = PlatformTexts._(
    commandFileTypes: '.exe, .ps1, .bat, .cmd',
    commandFileExtensions: ['exe', 'ps1', 'bat', 'cmd'],
    commandFileHint: r'map_drive.ps1 or C:\Tools\tool.exe',
    commandRights: 'with administrator rights',
    goodToKnow: [
      'Windows can only switch an adapter from DHCP to a static IP while it '
          'is connected. Plug in the cable first; the app tells you when this '
          'is the case.',
      'Switching to DHCP, or between static IPs, also works on an adapter '
          'that is not connected.',
      'An IP address can be set on one adapter only, also when that adapter '
          'is not connected. If another adapter already has it, the app asks '
          'whether to switch that adapter to DHCP first.',
      'The app needs administrator rights to change network settings, which '
          'is why Windows asks for permission when it starts. Commands run '
          'with the same rights.',
      'Keep the "plugins" folder when you update the app: your own command '
          'files may be in it.',
      r'Profiles and presets are stored in '
          r'%APPDATA%\NetworkAdapterTool\user_data.json.',
    ],
  );

  static const _linux = PlatformTexts._(
    commandFileTypes: '.sh, or .ps1 with PowerShell 7 (pwsh)',
    commandFileExtensions: ['sh', 'ps1'],
    commandFileHint: 'mount_share.sh or /opt/tools/start.sh',
    commandRights: 'with your user rights',
    goodToKnow: [
      'Settings are changed through NetworkManager (nmcli). An adapter '
          'without a cable keeps the new settings and uses them once a cable '
          'is plugged in.',
      'A Wi-Fi adapter needs a saved connection first: connect to a network '
          'once in the system settings.',
      'The app runs with your own rights; NetworkManager may ask for your '
          'password. Commands run with your rights too: use pkexec inside a '
          'script for a step that needs root.',
      'Keep the "plugins" folder when you update the app: your own command '
          'files may be in it.',
      'Profiles and presets are stored in '
          '~/.config/network-adapter-tool/user_data.json.',
    ],
  );

  /// The command file types this platform runs, for help and editor text.
  final String commandFileTypes;

  /// For the file dialog of the command "Browse" button.
  final List<String> commandFileExtensions;
  final String commandFileHint;

  /// How commands run, e.g. in the import warning.
  final String commandRights;
  final List<String> goodToKnow;
}
