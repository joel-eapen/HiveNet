import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:hivenet_core/hivenet_core.dart';

import 'app_paths.dart';

/// Opens the on-device SQLite file at `database/hivenet.sqlite` (FR-10).
AppDatabase openAppDatabase(AppPaths paths) {
  final QueryExecutor executor = driftDatabase(
    name: 'hivenet',
    native: DriftNativeOptions(
      databasePath: () async => paths.layout.databasePath,
    ),
  );
  return AppDatabase(executor);
}
