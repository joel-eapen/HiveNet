import 'dart:io';

import 'package:hivenet_core/hivenet_core.dart';
import 'package:path_provider/path_provider.dart';

/// Resolves and creates the FR-10 directory layout.
///
/// Uses the application-support directory, not a cache directory, so the OS
/// does not purge committed replicas (PRD section 10.3).
class AppPaths {
  const AppPaths._(this.layout);

  final StorageLayout layout;

  /// Resolves the platform root and creates every directory.
  static Future<AppPaths> resolve() async {
    final support = await getApplicationSupportDirectory();
    return ensure('${support.path}/HiveNet');
  }

  /// Creates the layout under [rootPath]. Split out so tests can use a
  /// temporary directory without a platform channel.
  static Future<AppPaths> ensure(String rootPath) async {
    final layout = StorageLayout(rootPath);
    for (final dir in layout.allDirectories) {
      await Directory(dir).create(recursive: true);
    }
    return AppPaths._(layout);
  }
}
