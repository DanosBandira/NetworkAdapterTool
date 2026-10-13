import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'app/view_models/main_view_model.dart';
import 'app/views/main_view.dart';
import 'core/adapters/explorer_folder_opener.dart';
import 'core/adapters/linux_ping_host_pinger.dart';
import 'core/adapters/netsh_network_adapter_configurator.dart';
import 'core/adapters/nmcli_client.dart';
import 'core/adapters/nmcli_network_adapter_configurator.dart';
import 'core/adapters/nmcli_network_adapter_reader.dart';
import 'core/adapters/ping_exe_host_pinger.dart';
import 'core/adapters/powershell_network_adapter_reader.dart';
import 'core/adapters/process_command_runner.dart';
import 'core/adapters/process_program_launcher.dart';
import 'core/adapters/xdg_folder_opener.dart';
import 'core/commands/plugin_path_resolver.dart';
import 'core/commands/profile_command_runner.dart';
import 'core/contracts/command_runner.dart';
import 'core/contracts/folder_opener.dart';
import 'core/contracts/host_pinger.dart';
import 'core/contracts/network_adapter_configurator.dart';
import 'core/contracts/network_adapter_reader.dart';
import 'core/network_preset_applier.dart';
import 'core/network_profile_applier.dart';
import 'core/platform/host_platform.dart';
import 'core/profiles/json_network_profile_library_transfer.dart';
import 'core/profiles/json_network_profile_repository.dart';
import 'core/profiles/network_profile_validator.dart';
import 'core/reachability/ping_targets_checker.dart';

/// Composition root: the only place that picks concrete implementations.
void main() {
  final mainViewModel = _composeMainViewModel();
  runApp(NetworkAdapterToolApp(mainViewModel: mainViewModel));
  // Not awaited: the window shows immediately with a loading indicator
  // while adapters are read, which takes a few seconds.
  unawaited(mainViewModel.initialize());
}

MainViewModel _composeMainViewModel() {
  final platform = HostPlatform.current;
  const commandRunner = ProcessCommandRunner();
  final system = _SystemTools.of(platform, commandRunner);
  final applier = NetworkProfileApplier(
    validator: const NetworkProfileValidator(),
    configurator: system.configurator,
    reader: system.reader,
    platform: platform,
  );
  return MainViewModel(
    reader: system.reader,
    repository: JsonNetworkProfileRepository.inUserSettingsFolder(platform),
    applier: applier,
    presetApplier: NetworkPresetApplier(applier),
    pingTargetsChecker: PingTargetsChecker(system.pinger),
    libraryTransfer: const JsonNetworkProfileLibraryTransfer(),
    profileCommandRunner: ProfileCommandRunner(
      launcher: ProcessProgramLauncher(platform: platform),
      pathResolver: PluginPathResolver(_pluginFolderPath()),
      platform: platform,
    ),
    folderOpener: system.folderOpener,
    platform: platform,
  );
}

/// The implementations that talk to the operating system: netsh, PowerShell,
/// ping.exe and Explorer on Windows; nmcli, ping and xdg-open on Linux.
class _SystemTools {
  const _SystemTools({
    required this.reader,
    required this.configurator,
    required this.pinger,
    required this.folderOpener,
  });

  factory _SystemTools.of(HostPlatform platform, CommandRunner commandRunner) {
    return switch (platform) {
      HostPlatform.windows => _SystemTools(
        reader: PowerShellNetworkAdapterReader(commandRunner),
        configurator: NetshNetworkAdapterConfigurator(commandRunner),
        pinger: PingExeHostPinger(commandRunner),
        folderOpener: ExplorerFolderOpener(commandRunner),
      ),
      HostPlatform.linux => _SystemTools(
        reader: NmcliNetworkAdapterReader(NmcliClient(commandRunner)),
        configurator: NmcliNetworkAdapterConfigurator(
          NmcliClient(commandRunner),
        ),
        pinger: LinuxPingHostPinger(commandRunner),
        folderOpener: XdgFolderOpener(commandRunner),
      ),
    };
  }

  final NetworkAdapterReader reader;
  final NetworkAdapterConfigurator configurator;
  final HostPinger pinger;
  final FolderOpener folderOpener;
}

// Next to the executable rather than in the user's settings folder: plugins
// ship inside the release package and travel with the app folder. Whoever
// can write there can already replace the executable itself, so this adds
// no new way to run code with the app's rights.
String _pluginFolderPath() =>
    path.join(path.dirname(Platform.resolvedExecutable), 'plugins');

class NetworkAdapterToolApp extends StatelessWidget {
  const NetworkAdapterToolApp({super.key, required this.mainViewModel});

  final MainViewModel mainViewModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: mainViewModel,
      child: MaterialApp(
        title: 'Network Adapter Tool',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        home: const MainView(),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      colorScheme: _withNeutralSurfaces(
        ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness),
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  // Material 3 tints every surface with the seed color, which turned the
  // background mint green. Teal stays for buttons and accents; the background
  // is white and dialogs and fields use very light neutral greys, so the
  // colored cards stand out.
  ColorScheme _withNeutralSurfaces(ColorScheme seeded) {
    final isDark = seeded.brightness == Brightness.dark;
    return seeded.copyWith(
      surface: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF),
      surfaceContainerLowest: isDark
          ? const Color(0xFF141414)
          : const Color(0xFFFFFFFF),
      surfaceContainerLow: isDark
          ? const Color(0xFF222222)
          : const Color(0xFFFAFAFA),
      surfaceContainer: isDark
          ? const Color(0xFF262626)
          : const Color(0xFFF5F5F5),
      surfaceContainerHigh: isDark
          ? const Color(0xFF2C2C2C)
          : const Color(0xFFF0F0F0),
      surfaceContainerHighest: isDark
          ? const Color(0xFF333333)
          : const Color(0xFFEBEBEB),
      surfaceTint: Colors.transparent,
    );
  }
}
