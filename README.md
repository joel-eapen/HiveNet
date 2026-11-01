# HiveNet

Peer-to-peer edge storage for Android and iOS. Phones on the same Wi-Fi form a mesh that stores encrypted image replicas, shows a shared gallery, and serves images on demand by content ID. There is no cloud bucket and no central database.

Team MiniMOL: Tushar, Joel.

## Scope

**Android only for now.** iPhone support is deferred: the iOS project config exists but is untested, and no work depends on it.

## Status

No PRD milestone is complete yet.

- **Skeleton:** folder structure, interfaces, data contract, database schema, theme, navigation and placeholder screens.
- **Milestone 0 (Android checks done):** a developer screen, Settings → Feasibility spike, ran the compatibility checks on two real Android phones. mDNS works on a phone hotspot but not on the campus Wi-Fi. iOS checks are out of scope. See [docs/milestone0_device_test_guide.md](docs/milestone0_device_test_guide.md).
- **Milestone 3 foundation (done, in `hivenet_core`):** length-prefixed framing, SHA-256 integrity checker, chunk manager with resume, file store with verified atomic commit, AES-256-GCM encryption. Covered by tests including an end-to-end pipeline test.
- **Milestone 4 foundation (done, in `hivenet_core`):** hard eligibility filter, deterministic node scoring, a placement router that validates any AI ranking and falls back safely, atomic quota reservations, and the upload/replication state machine with persistence and restart recovery. It runs against a `ReplicaTransport` interface, so it is tested with fake peers; no real peer connection exists yet.
- **Not built yet:** image compression and thumbnails, discovery, pairing, the real TCP server and client, replication, the real gallery, access control and key wrapping. Unbuilt services throw `UnimplementedError`, and the UI labels fixture data with a "Demo data" banner.

## Documentation

| Document | Contents |
|---|---|
| [docs/hivenet_prd_v1.2.md](docs/hivenet_prd_v1.2.md) | Main PRD: requirements, protocol, data model, security, milestones |
| [docs/hivenet_frontend_prd_v1.1.md](docs/hivenet_frontend_prd_v1.1.md) | Frontend PRD: screens, view models, navigation |

## Repository layout

```text
HiveNet/
├── docs/                          PRDs
├── hivenet/                       Flutter app (com.minimol.hivenet)
│   ├── lib/
│   │   ├── main.dart              Startup: resolve paths, open database, run app
│   │   ├── app/                   App widget, router, shell, providers, theme/
│   │   ├── features/              One folder per feature (UI only)
│   │   ├── adapters/              Flutter-dependent implementations of core interfaces
│   │   ├── demo/                  Fixture data, shown only in demo mode
│   │   └── shared/widgets/        Reusable widgets (StatusChip, EmptyStateView, ...)
│   └── test/
└── packages/hivenet_core/         Pure Dart: contract, interfaces, protocol, schema
    ├── lib/hivenet_core.dart      Single export file for the package
    ├── lib/src/core/              compression, networking, router_engine, retrieval,
    │                              storage, security, metadata
    ├── lib/src/database/          Drift tables, DAOs, AppDatabase
    ├── lib/src/shared/            models (enums, manifests, jobs, grants), utils
    └── test/
```

### Why two projects

`hivenet_core` has no Flutter dependency, so its tests run with plain `dart test`, with no phone or emulator. Anything that needs a Flutter plugin lives in `hivenet/lib/adapters/` and implements a core interface:

| Core interface | App adapter | Plugin |
|---|---|---|
| `KeyStore` | `SecureKeyStore` | `flutter_secure_storage` (Android Keystore, iOS Keychain) |
| `ImageCompressor` | `FlutterImageCompressor` (stub) | `flutter_image_compress` |
| `PeerDiscovery` | `BonsoirPeerDiscovery` (stub) | `bonsoir` |
| `StorageLayout` paths | `AppPaths` | `path_provider` |
| SQLite connection | `openAppDatabase` | `drift_flutter` |

The UI depends on interfaces and providers (`app/providers.dart`), not on concrete services.

## Setup

Requires Flutter (stable) and, for Android, Android Studio with the Android SDK.

```sh
brew install --cask flutter android-studio
# Open Android Studio once so it installs the Android SDK, then:
flutter doctor --android-licenses
flutter doctor
```

iOS builds additionally need full Xcode and CocoaPods. iOS config is in place but has not been built yet.

### Generate code (required on a fresh clone)

Drift's generated `*.g.dart` files are gitignored.

```sh
cd packages/hivenet_core
dart pub get
dart run build_runner build
```

Re-run this command after changing anything under `lib/src/database/`.

### Run and test

```sh
# Core package
cd packages/hivenet_core
dart analyze && dart test

# App
cd hivenet
flutter pub get
flutter analyze && flutter test
flutter run                   # needs an emulator or a connected device
flutter build apk --debug
```

Dependency versions are pinned exactly in both `pubspec.yaml` files.

## Where each module gets built

Module paths are under `packages/hivenet_core/lib/src/`. Milestones are from PRD section 11.

| Module | Milestone |
|---|---|
| `networking/` (discovery, sockets, heartbeat) | 0 spike, 2 discovery and pairing |
| `security/device_identity`, `security/key_store` | 1 |
| `security/pairing_service` | 2 |
| `compression/` | 3 (not built) |
| `storage/` (file store, chunks, integrity), `networking/length_prefixed_framing`, `security/aes_gcm_encryption_service` | 3 (foundation built) |
| `router_engine/` (router, scorer, quota, replication) | 4 (foundation built; needs a real `ReplicaTransport` from Milestones 2 and 3) |
| `metadata/`, `retrieval/` | 5 |
| `retrieval/access_control`, key wrapping | 6 |
| Replica repair (`repairUnderReplicated`), optional AI ranking via `decision_model_adapter` | 7 |

## Design rules to keep

- Same Wi-Fi, mDNS discovery, pairing or storage placement never grants permission to view an image (PRD FR-09A). `DenyAllAccessControl` is the default.
- `DecisionModelAdapter` can only rank peers. It must never gain methods for grants, keys or authorization.
- Upload success needs verified replicas. `UploadState.completed` is reachable only from `replicating`.
- A request's `senderNodeId` is a claim. Use `PeerConnection.authenticatedNodeId`.
- Enum wire names and `kProtocolVersion` are frozen by `test/models/wire_names_test.dart`. Changing one is a protocol break.
- Demo data lives only in `hivenet/lib/demo/` and is never read by production code.

## Known gaps

- Verified on the Android emulator (API 37): the debug APK builds and the app launches. iOS has not been built.
- Build gotchas: the first build downloads a prebuilt SQLite library from GitHub through the `sqlite3` build hook. A dropped connection fails the build with "Connection reset by peer"; re-running it works.
- `flutter_image_compress_common` prints a Kotlin Gradle Plugin deprecation warning. It does not affect the build today, but check for a plugin update before upgrading Flutter.
- The onboarding-complete flag is in memory only. Persisting it is Milestone 1.
- The output image format (JPEG or WebP) is a placeholder default until the Milestone 0 device spike.
