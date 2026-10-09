import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'app/view_models/main_view_model.dart';
import 'app/views/main_view.dart';
import 'core/adapters/explorer_folder_opener.dart';
import 'core/adapters/netsh_network_adapter_configurator.dart';
import 'core/adapters/ping_exe_host_pinger.dart';
import 'core/adapters/powershell_network_adapter_reader.dart';
import 'core/adapters/process_command_runner.dart';
import 'core/adapters/process_program_launcher.dart';
import 'core/commands/plugin_path_resolver.dart';
import 'core/commands/profile_command_runner.dart';
import 'core/network_preset_applier.dart';
import 'core/network_profile_applier.dart';
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
  const commandRunner = ProcessCommandRunner();
  const reader = PowerShellNetworkAdapterReader(commandRunner);
  const applier = NetworkProfileApplier(
    validator: NetworkProfileValidator(),
    configurator: NetshNetworkAdapterConfigurator(commandRunner),
    reader: reader,
  );
  return MainViewModel(
    reader: reader,
    repository: JsonNetworkProfileRepository.inRoamingAppData(),
    applier: applier,
    presetApplier: const NetworkPresetApplier(applier),
    pingTargetsChecker: const PingTargetsChecker(
      PingExeHostPinger(commandRunner),
    ),
    libraryTransfer: const JsonNetworkProfileLibraryTransfer(),
    profileCommandRunner: ProfileCommandRunner(
      launcher: const ProcessProgramLauncher(),
      pathResolver: PluginPathResolver(_pluginFolderPath()),
    ),
    folderOpener: const ExplorerFolderOpener(commandRunner),
  );
}

// Next to the exe rather than in %APPDATA%: plugins ship inside the release
// zip and travel with the app folder. Whoever can write there can already
// replace the exe itself, so this adds no new way to run code as admin.
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
