import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hivenet_core/hivenet_core.dart';

import 'adapters/app_paths.dart';
import 'adapters/app_settings.dart';
import 'adapters/database_connection.dart';
import 'adapters/secure_key_store.dart';
import 'app/app.dart';
import 'app/providers.dart';
import 'app/runtime/hivenet_runtime.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Restore local state before the UI (and the peer server) starts.
    final paths = await AppPaths.resolve();
    final settings = await AppSettings.load(paths.layout.rootPath);
    final database = openAppDatabase(paths);
    final runtime = await HiveNetRuntime.start(
      paths: paths,
      db: database,
      keys: SecureKeyStore(),
      platform: Platform.isIOS ? DevicePlatform.ios : DevicePlatform.android,
      deviceName: settings.deviceName,
    );

    runApp(
      ProviderScope(
        overrides: [
          appPathsProvider.overrideWithValue(paths),
          appDatabaseProvider.overrideWithValue(database),
          appSettingsProvider.overrideWithValue(settings),
          runtimeProvider.overrideWithValue(runtime),
        ],
        child: const HiveNetApp(),
      ),
    );
  } catch (e) {
    // Never fall back to a fresh identity or an empty database: that would hide
    // the problem and orphan existing pairings. Say what went wrong instead.
    runApp(_StartupError(error: e));
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                Text('HiveNet could not start', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                const Text(
                  'Your device identity or stored data could not be opened. '
                  'HiveNet did not create a new identity, so nothing was lost. '
                  'Close the app and open it again. If this keeps happening, '
                  'check the device lock screen and storage.',
                ),
                const SizedBox(height: 16),
                SelectableText(
                  error is HiveError ? '${(error as HiveError).technicalDetails ?? error}' : '$error',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
