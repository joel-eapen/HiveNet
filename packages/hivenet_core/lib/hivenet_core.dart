/// HiveNet core: pure-Dart contract, interfaces, protocol and schema.
///
/// Anything needing Flutter plugins (image compression, mDNS, secure storage,
/// file paths) is implemented in the app's `adapters/` against these
/// interfaces.
library;

// Shared contract
export 'src/shared/models/enums.dart';
export 'src/shared/models/hive_error.dart';
export 'src/shared/models/image_manifest.dart';
export 'src/shared/models/jobs.dart';
export 'src/shared/models/manifest_event.dart';
export 'src/shared/models/peer_telemetry.dart';
export 'src/shared/models/protocol_constants.dart';
export 'src/shared/models/replica_record.dart';
export 'src/shared/models/security_models.dart';
export 'src/shared/utils/json_helpers.dart';

// Compression
export 'src/core/compression/compression_config.dart';
export 'src/core/compression/image_compressor.dart';
export 'src/core/compression/thumbnail_generator.dart';

// Networking
export 'src/core/networking/heartbeat_service.dart';
export 'src/core/networking/length_prefixed_framing.dart';
export 'src/core/networking/message_framing.dart';
export 'src/core/networking/message_protocol.dart';
export 'src/core/networking/network_config.dart';
export 'src/core/networking/peer_discovery.dart';
export 'src/core/networking/socket_client.dart';
export 'src/core/networking/socket_server.dart';

// Router engine
export 'src/core/router_engine/decision_model_adapter.dart';
export 'src/core/router_engine/default_replication_manager.dart';
export 'src/core/router_engine/deterministic_storage_router.dart';
export 'src/core/router_engine/local_quota_manager.dart';
export 'src/core/router_engine/placement_audit.dart';
export 'src/core/router_engine/placement_eligibility.dart';
export 'src/core/router_engine/replica_transport.dart';
export 'src/core/router_engine/replication_store.dart';
export 'src/core/router_engine/node_scorer.dart';
export 'src/core/router_engine/quota_manager.dart';
export 'src/core/router_engine/replication_manager.dart';
export 'src/core/router_engine/storage_router.dart';

// Retrieval
export 'src/core/retrieval/access_control.dart';
export 'src/core/retrieval/content_locator.dart';
export 'src/core/retrieval/download_manager.dart';
export 'src/core/retrieval/image_request_manager.dart';
export 'src/core/retrieval/replica_selector.dart';

// Storage
export 'src/core/storage/chunk_manager.dart';
export 'src/core/storage/file_chunk_manager.dart';
export 'src/core/storage/file_store.dart';
export 'src/core/storage/local_file_store.dart';
export 'src/core/storage/sha256_integrity_checker.dart';
export 'src/core/storage/integrity_checker.dart';
export 'src/core/storage/storage_layout.dart';

// Security
export 'src/core/security/aes_gcm_encryption_service.dart';
export 'src/core/security/device_identity.dart';
export 'src/core/security/encryption_service.dart';
export 'src/core/security/key_store.dart';
export 'src/core/security/pairing_service.dart';

// Metadata
export 'src/core/metadata/manifest.dart';
export 'src/core/metadata/metadata_sync.dart';
export 'src/core/metadata/reconciliation.dart';

// Database
export 'src/database/app_database.dart';
export 'src/database/drift_replication_store.dart';
export 'src/database/daos/access_grants_dao.dart';
export 'src/database/daos/files_dao.dart';
export 'src/database/daos/manifest_events_dao.dart';
export 'src/database/daos/nodes_dao.dart';
export 'src/database/daos/replicas_dao.dart';
export 'src/database/daos/transfers_dao.dart';
export 'src/database/daos/trusted_devices_dao.dart';
export 'src/database/daos/upload_jobs_dao.dart';
