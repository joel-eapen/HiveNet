import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'adapters/app_paths.dart';
import 'adapters/database_connection.dart';
import 'app/app.dart';
import 'app/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restore local state before the UI (and later the peer service) starts.
  final paths = await AppPaths.resolve();
  final database = openAppDatabase(paths);

  runApp(
    ProviderScope(
      overrides: [
        appPathsProvider.overrideWithValue(paths),
        appDatabaseProvider.overrideWithValue(database),
      ],
      child: const HiveNetApp(),
    ),
  );
}
