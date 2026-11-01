import 'package:drift/drift.dart';

import 'daos/access_grants_dao.dart';
import 'daos/files_dao.dart';
import 'daos/manifest_events_dao.dart';
import 'daos/nodes_dao.dart';
import 'daos/replicas_dao.dart';
import 'daos/transfers_dao.dart';
import 'daos/trusted_devices_dao.dart';
import 'daos/upload_jobs_dao.dart';
import 'tables/access_grants.dart';
import 'tables/device_keys.dart';
import 'tables/image_files.dart';
import 'tables/manifest_events.dart';
import 'tables/nodes.dart';
import 'tables/replicas.dart';
import 'tables/transfers.dart';
import 'tables/trusted_devices.dart';
import 'tables/upload_jobs.dart';
import 'tables/wrapped_image_keys.dart';

part 'app_database.g.dart';

/// Local metadata and state only (PRD FR-10). Image objects live on the
/// filesystem. This database is not the network-wide source of truth; it is
/// one device's view of owner-authoritative manifests.
///
/// The connection is supplied by the caller so this package stays pure Dart:
/// the app passes a file-backed executor, tests pass an in-memory one.
@DriftDatabase(
  tables: [
    Nodes,
    ImageFiles,
    Replicas,
    UploadJobs,
    Transfers,
    TrustedDevices,
    AccessGrants,
    DeviceKeys,
    WrappedImageKeys,
    ManifestEvents,
  ],
  daos: [
    NodesDao,
    FilesDao,
    ReplicasDao,
    UploadJobsDao,
    TransfersDao,
    TrustedDevicesDao,
    AccessGrantsDao,
    ManifestEventsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
