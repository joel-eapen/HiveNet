# HiveNet — Frontend Product Requirements Document

**Version:** 1.1  
**Status:** Hackathon MVP implementation specification  
**Platforms:** Android and iOS  
**Framework:** Flutter + Dart  
**State management:** Riverpod  
**Navigation:** GoRouter  
**Design direction:** Premium, modern, clean, technical but approachable  
**Backend integration:** Local per-device HiveNet backend with peer-to-peer networking

---

## 1. Purpose and scope

This document defines the frontend architecture, screens, reusable widgets, UI state models, navigation, interaction flows, loading/error states, and milestone-wise implementation plan for HiveNet.

HiveNet is a peer-to-peer distributed image-storage application. Users contribute storage from their Android and iOS phones. Images are compressed on the uploader's device, encrypted, replicated to other devices, and retrieved on demand from an available replica.

The frontend must make this distributed system understandable. Users should be able to answer these questions without understanding the underlying networking implementation:

- Which devices are currently connected?
- Where is my image stored?
- Has the requested replication factor been achieved?
- Who can view this image?
- Is this device only storing an encrypted copy, or can it also view the image?
- Where will an image be retrieved from?
- Why is an image temporarily unavailable?
- What happens if a peer disconnects?

The UI must never imply that an image is safely replicated when the backend has not verified the required replicas.

### 1.1 Frontend principles

1. **Clarity over technical complexity:** expose useful status and explanations, not raw protocol details.
2. **Local-first:** the app remains useful even when no other peers are online.
3. **Honest status:** distinguish queued, uploading, under-replicated, replicated, unavailable and failed.
4. **Permission-aware:** gallery visibility, retrieval permission and decryption permission are distinct.
5. **Progressive disclosure:** show simple summaries first; expose technical details in an image/device details view.
6. **Mobile-first layouts:** use bottom navigation, compact cards, safe-area-aware layouts and touch-friendly controls on both platforms.
7. **Honest mobile availability:** show a replica as stored separately from whether its phone is currently online and able to serve it. HiveNet is foreground-first; do not imply continuous background serving, especially on iOS.
8. **Accessible interaction:** clear labels, adequate contrast, screen-reader semantics, sensible touch targets and platform-native permission explanations.
9. **No fake live data:** all peer, storage and transfer states must come from backend streams or explicit demo fixtures.

---

## 2. Target users and roles

A single installation can perform multiple roles.

### 2.1 Uploader

Selects an image, chooses importance and visibility, reviews compression, and starts an upload.

### 2.2 Viewer

Browses image entries permitted by the metadata policy and requests images they are authorized to view.

### 2.3 Storage contributor

Allows HiveNet to use a configured amount of local disk space for encrypted replicas.

### 2.4 Device administrator

Pairs and revokes devices, configures storage contribution, reviews trusted devices and manages security settings.

### 2.5 Permission states shown in the UI

The frontend must distinguish these states:

- **Owner:** controls an image's access policy.
- **Storage-only peer:** stores encrypted bytes; cannot decrypt or view the image unless separately granted permission.
- **Authorized viewer:** has an active view grant and can obtain a wrapped decryption key.
- **Unpaired device:** is not trusted and cannot access protected content.
- **Revoked device:** was previously paired or authorized but has been revoked.

Being on the same Wi-Fi network, appearing in discovery results, or being selected as a storage peer must never be presented as permission to view an image.

---

## 3. Application information architecture

### 3.1 Primary navigation

Mobile bottom navigation:

1. **Gallery** — permitted image library.
2. **Activity** — uploads, downloads, replication and repair activity.
3. **Devices** — discovered, paired and connected peers.
4. **Storage** — local contribution and replica usage.
5. **Settings** — identity, pairing, privacy and app configuration.

Android and iOS use the same bottom-navigation destinations. Adapt density and layout to phone size, orientation, safe areas and system text scaling; do not create a desktop navigation mode.

### 3.2 Global application shell

The shell must include:

- App name/logo and current device name.
- Network status indicator: `Offline`, `Discovering`, `Connected` or `Degraded`.
- A visible action to add/upload an image.
- A notification/activity entry point.
- A global error banner for critical backend/network failures.
- Responsive layout based on available width.

The global network indicator describes the peer network, not internet connectivity.

---

## 4. Design system and visual direction

### 4.1 Visual language

Use a premium storage/network utility aesthetic:

- Neutral light or dark surfaces with a restrained accent color.
- Strong typography hierarchy and readable metadata.
- Rounded cards used consistently, not excessively.
- Subtle borders and elevation.
- Clear iconography for image, device, network, security, storage and transfer states.
- Status colors must be consistent and accompanied by text/icons; never rely on color alone.

Suggested palette direction:

- Primary accent: deep teal/green or another single confident brand accent.
- Background: warm near-white in light mode; deep charcoal in dark mode.
- Surface: slightly elevated neutral cards.
- Success: green.
- Warning/under-replicated: amber.
- Error/offline: red or muted danger tone.
- Informational: blue.

The exact color tokens can be finalized in the design implementation, but they must be centralized in the theme.

### 4.2 Typography

Define reusable text styles:

- Display/hero: page headline and major storage number.
- Title large/medium/small: screen and card headings.
- Body large/medium/small: explanatory and supporting content.
- Label: chips, metadata labels and compact controls.
- Monospaced metadata: content IDs, node IDs, hashes and technical identifiers.

Do not display full hashes by default. Use shortened values with copy action and full value in details.

### 4.3 Reusable design tokens

Create a centralized theme containing:

- Color tokens.
- Text styles.
- Spacing scale.
- Corner radii.
- Elevation/shadow.
- Icon sizes.
- Button heights.
- Responsive breakpoints.
- Status color mapping.

### 4.4 Shared component library

Build these components before duplicating them across screens:

- `HiveNetScaffold`
- `ResponsiveNavigation`
- `NetworkStatusIndicator`
- `StatusChip`
- `EmptyStateView`
- `ErrorStateView`
- `LoadingSkeleton`
- `ConfirmDialog`
- `SectionHeader`
- `InfoTooltip`
- `CopyableIdentifier`
- `StorageUsageBar`
- `PeerAvatar`
- `DeviceStatusCard`
- `ImageThumbnail`
- `ReplicationStatus`
- `VisibilityBadge`
- `TransferProgressCard`
- `PermissionSummary`
- `PrimaryActionButton`
- `InlineNotice`
- `RetryButton`

Components must accept typed model/view-model data. Avoid passing unstructured maps throughout the widget tree.

---

## 5. Frontend architecture

Use a feature-first Flutter structure with separation between UI, presentation state and backend integration.

```text
lib/
├── main.dart
├── app/
│   ├── app.dart
│   ├── router.dart
│   ├── app_shell.dart
│   └── theme/
│       ├── app_theme.dart
│       ├── color_tokens.dart
│       ├── spacing_tokens.dart
│       └── typography.dart
├── core/
│   ├── api/
│   │   ├── local_backend_client.dart
│   │   ├── peer_api_client.dart
│   │   ├── api_result.dart
│   │   └── api_error.dart
│   ├── realtime/
│   │   ├── event_stream_client.dart
│   │   └── event_models.dart
│   ├── models/
│   │   ├── app_device.dart
│   │   ├── peer.dart
│   │   ├── hive_image.dart
│   │   ├── replica.dart
│   │   └── transfer.dart
│   ├── providers/
│   ├── widgets/
│   └── utils/
├── features/
│   ├── onboarding/
│   ├── dashboard/
│   ├── gallery/
│   ├── image_details/
│   ├── upload/
│   ├── activity/
│   ├── devices/
│   ├── pairing/
│   ├── storage/
│   ├── access_management/
│   └── settings/
└── test/
    ├── models/
    ├── widgets/
    └── features/
```

Each feature should generally contain:

```text
feature_name/
├── data/
│   ├── feature_repository.dart
│   └── feature_dto.dart
├── domain/
│   ├── feature_model.dart
│   └── feature_service.dart
└── presentation/
    ├── providers/
    ├── controllers/
    ├── screens/
    └── widgets/
```

Do not create unnecessary layers for every tiny feature. Keep the separation consistent and pragmatic.

### 5.1 State management

Use Riverpod for:

- Current device identity.
- Network status and peer list.
- Gallery filters and image list.
- Image details and replica status.
- Upload and download jobs.
- Storage metrics.
- Pairing workflow.
- Access grants and permission state.
- Settings.

Use `AsyncValue` or equivalent typed states for loading/data/error. Do not use nullable fields to represent every possible state.

### 5.2 Backend integration contract

The frontend talks to the local backend running within the same HiveNet application. The exact transport may be an in-process Dart service, platform channel or loopback API depending on the backend implementation. Keep the frontend behind repository interfaces so the transport can change without rewriting screens.

Repositories should expose typed methods and streams, for example:

```dart
abstract interface class GalleryRepository {
  Future<List<ImageSummary>> getImages(GalleryQuery query);
  Stream<List<ImageSummary>> watchImages(GalleryQuery query);
  Future<ImageDetails> getImageDetails(String contentId);
}

abstract interface class DeviceRepository {
  Stream<List<PeerSummary>> watchPeers();
  Future<void> pairDevice(PairingRequest request);
  Future<void> revokeDevice(String nodeId);
}

abstract interface class UploadRepository {
  Future<UploadJob> createUpload(CreateUploadRequest request);
  Stream<UploadJob> watchUpload(String jobId);
  Future<void> cancelUpload(String jobId);
}

abstract interface class AccessRepository {
  Future<List<AccessGrant>> getGrants(String contentId);
  Future<void> grantViewAccess(GrantAccessRequest request);
  Future<void> revokeAccess(String contentId, String granteeNodeId);
}
```

These are frontend-facing interfaces, not a mandate to expose a public HTTP server. Adapt them to the selected local backend transport.

---

## 6. Frontend domain models and view models

Use immutable typed models. Prefer generated serialization (`freezed`/`json_serializable`) if the team is comfortable with it; otherwise use explicit constructors and serializers.

### 6.1 `AppDevice`

Represents the device running the current application.

| Field | Type | Purpose |
|---|---|---|
| `nodeId` | `String` | Stable local device identifier |
| `displayName` | `String` | User-visible device name |
| `platform` | enum | `android` or `ios` |
| `isPaired` | `bool` | Whether this installation has completed trusted setup |
| `networkState` | enum | Current local network state |
| `createdAt` | `DateTime` | Device registration time |

Do not expose private keys or secrets to UI models.

### 6.2 `PeerSummary`

Represents a discovered or paired peer in list views.

| Field | Type | Purpose |
|---|---|---|
| `nodeId` | `String` | Stable peer identity |
| `displayName` | `String` | User-visible name |
| `platform` | enum | Android/iOS |
| `connectionState` | enum | `discovered`, `connecting`, `online`, `offline`, `revoked` |
| `availableBytes` | `int` | Estimated available storage |
| `contributedBytes` | `int` | Storage contribution limit |
| `storedReplicaCount` | `int` | Number of replicas held by this peer |
| `lastSeenAt` | `DateTime?` | Last heartbeat |
| `latencyMs` | `int?` | Approximate latency |
| `trustState` | enum | `unpaired`, `paired`, `revoked` |

Do not display IP addresses in ordinary cards. Show them only in advanced device details.

### 6.3 `ImageSummary`

Represents a gallery item without loading the original bytes.

| Field | Type | Purpose |
|---|---|---|
| `contentId` | `String` | Content-addressed image identifier |
| `ownerNodeId` | `String` | Owner identity |
| `ownerDisplayName` | `String` | Owner label |
| `fileName` | `String` | Original/display filename |
| `mimeType` | `String` | Encoded image type |
| `fileSizeBytes` | `int` | Compressed plaintext size |
| `width` | `int` | Image width |
| `height` | `int` | Image height |
| `thumbnailState` | enum | `available`, `locked`, `loading`, `missing` |
| `importance` | enum | `normal`, `important` |
| `visibility` | enum | `private`, `selectedDevices`, `networkShared` |
| `replication` | `ReplicationSummary` | Desired and verified replica counts |
| `availability` | enum | `available`, `partial`, `offline`, `unknown` |
| `permission` | enum | `owner`, `canView`, `metadataOnly`, `denied` |
| `createdAt` | `DateTime` | Upload time |

A gallery entry may be visible while the image itself is not viewable. In that case show a locked state and do not load a plaintext thumbnail.

### 6.4 `ImageDetails`

Extends the summary with detailed metadata:

- Full content ID.
- Ciphertext hash.
- Compression format and dimensions.
- Owner details.
- Visibility and access policy.
- Replica locations and status.
- Current retrieval state.
- Creation and update times.
- Integrity verification state.

### 6.5 `ReplicationSummary`

| Field | Type | Purpose |
|---|---|---|
| `desiredCount` | `int` | 2 for normal, 3 for important |
| `verifiedCount` | `int` | Confirmed committed replicas |
| `pendingCount` | `int` | Targets not yet committed |
| `failedCount` | `int` | Failed replica targets |
| `state` | enum | `pending`, `underReplicated`, `complete`, `repairing`, `degraded` |

Only verified durable replicas count toward completion.

### 6.6 `ReplicaSummary`

- `nodeId`
- `peerDisplayName`
- `state`: `reserving`, `transferring`, `verifying`, `committed`, `offline`, `failed`
- `verified`
- `ciphertextHash`
- `storedAt`
- `lastSeenAt`

### 6.7 `UploadJob`

| Field | Type | Purpose |
|---|---|---|
| `jobId` | `String` | Upload transaction ID |
| `fileName` | `String` | Selected file name |
| `contentId` | `String?` | Available after compression/hash |
| `state` | enum | Upload lifecycle state |
| `progress` | `double` | Overall progress 0–1 |
| `bytesProcessed` | `int` | Compression/transfer progress |
| `totalBytes` | `int?` | Known transfer size |
| `importance` | enum | Normal/important |
| `visibility` | enum | Selected visibility |
| `replication` | `ReplicationSummary?` | Replica progress |
| `error` | `UiError?` | Recoverable/fatal error |
| `createdAt` | `DateTime` | Start time |

Suggested upload states:

`selected → compressing → encrypting → planning → reserving → uploading → verifying → completed`

Alternative states:

`queued`, `underReplicated`, `paused`, `cancelled`, `failed`.

Do not collapse `completed` and `underReplicated`.

### 6.8 `TransferJob`

- `transferId`
- `contentId`
- `direction`: `upload` or `download`
- `sourceNodeId`
- `destinationNodeId`
- `state`: `queued`, `connecting`, `transferring`, `verifying`, `completed`, `paused`, `failed`
- `progress`
- `bytesTransferred`
- `totalBytes`
- `startedAt`
- `updatedAt`

### 6.9 `AccessGrant`

- `contentId`
- `granteeNodeId`
- `granteeDisplayName`
- `permission`: `view`, `retrieve`, `storeEncrypted`
- `status`: `active`, `revoked`, `expired`, `pending`
- `grantedBy`
- `createdAt`
- `revokedAt`
- `keyDeliveryState`: `notRequired`, `pending`, `delivered`, `failed`

A storage-only grant must never be rendered as a view grant.

### 6.10 `StorageOverview`

- `totalBytes`
- `usedBytes`
- `availableBytes`
- `contributionLimitBytes`
- `replicaBytes`
- `cacheBytes`
- `temporaryBytes`
- `localOwnedImageBytes`
- `usageUpdatedAt`

### 6.11 `UiError`

- `code`
- `title`
- `message`
- `isRetryable`
- `actionLabel`
- `technicalDetails` (advanced details only)

Do not show raw stack traces in the main UI.

---

## 7. Screen specifications

## 7.1 Onboarding

**Purpose:** explain HiveNet and initialize this device.

Content:
- HiveNet logo and short value proposition.
- Explain that devices share encrypted storage over the local network.
- Explain that storage contribution is configurable.
- Explain that same Wi-Fi does not automatically grant image access.
- Device display-name field.
- Storage contribution setup.
- Local-network permission explanation and permission request.
- Continue action.

States:
- First launch.
- Permission denied.
- Initialization in progress.
- Initialization failed with retry.

Acceptance:
- User understands this device can store encrypted replicas.
- User can choose not to contribute storage and still use HiveNet as a viewer/uploader where network policy permits.

## 7.2 Dashboard

**Purpose:** provide a quick health overview.

Components:
- Greeting/device name.
- Network status card.
- Online peer count.
- Storage contributed/used.
- Recent uploads/downloads.
- Replication health summary.
- Quick upload action.
- Recent images (only entries permitted by metadata visibility).

Example summary cards:
- `3 peers online`
- `12.4 GB contributed`
- `8 images fully replicated`
- `2 images need replicas`

Do not show invented or hard-coded values outside a clearly labeled demo mode.

States:
- No peers discovered.
- Peers available but not paired.
- Network healthy.
- Network degraded.
- No images yet.
- Backend unavailable.

## 7.3 Gallery

**Purpose:** browse permitted image entries.

Layout:
- Responsive grid of image cards.
- Search by filename/owner.
- Filters: All, Owned by me, Shared with me, Normal, Important, Needs attention.
- Sort: newest, oldest, filename, size.
- Availability and permission indicators.
- Upload button.

Each card:
- Thumbnail only if requester is authorized to view it.
- Filename.
- Owner.
- Date.
- Importance badge.
- Replication state.
- Availability/lock state.

States:
- Loading skeleton.
- Empty gallery.
- No results.
- Metadata visible but image locked.
- Image unavailable because no replica is online.
- Thumbnail loading/missing.
- Error with retry.

Acceptance:
- Browsing the gallery does not download original image bytes.
- Locked entries never show plaintext thumbnails.
- Selecting a card opens image details.

## 7.4 Image details

**Purpose:** show the image's storage, availability and access information.

Sections:
1. Preview or locked placeholder.
2. Filename, dimensions, size and owner.
3. Content ID with copy action.
4. Importance and visibility.
5. Replication progress (`2/2` or `2/3`).
6. Replica list with peer state.
7. Access list and permission summary (owner only).
8. Retrieve/view action (only if authorized).
9. Owner actions: change visibility, grant access, revoke access, delete metadata/object according to supported backend semantics.

Retrieval interaction:
- User taps View.
- Show authorization check state.
- If authorized, show source selection/connecting state.
- Download progress.
- Integrity verification.
- Decryption/loading.
- Display image.
- If all replicas are offline, explain that the image is temporarily unavailable and keep metadata visible.

Do not reveal decryption keys or sensitive crypto metadata.

## 7.5 Upload flow

Use a guided, multi-step flow.

**Step 1 — Select image**
- File picker.
- Preview selected image locally.
- Show filename, dimensions and original size.
- Validate supported format and file size.

**Step 2 — Choose upload settings**
- Importance: Normal (2 replicas) or Important (3 replicas).
- Visibility: Private, Selected devices, Network shared.
- If Selected devices: select paired viewer identities separately from storage targets.
- Explain that storage peers do not automatically gain view permission.
- Show a short privacy explanation.

**Step 3 — Compression preview**
- Show original size and estimated/completed compressed size.
- Show output format and dimensions.
- Explain that compression occurs on this device.
- Allow cancel; avoid exposing technical tuning unless in advanced settings.

**Step 4 — Placement preview**
- Show eligible storage peers and requested replica count.
- Clearly label each target as a storage peer.
- Do not imply the AI decision model grants access.
- If insufficient peers are online, explain that the upload may remain under-replicated.

**Step 5 — Upload progress**
- Compression progress.
- Encryption progress.
- Peer reservation.
- Transfer progress per peer.
- Verification and replica commit.
- Final status.

Success screen must say `Replicated` only after all required replicas are verified. Otherwise say `Uploaded — replication incomplete` or `Pending`.

## 7.6 Activity

Tabs/filters:
- All.
- Uploads.
- Downloads.
- Repairs.
- Failed.

Activity row:
- File name.
- Direction/action.
- Status.
- Progress.
- Peer/source.
- Time.
- Retry/cancel action where supported.

Show individual replica transfer progress within an upload detail page.

## 7.7 Devices

Tabs:
- Nearby.
- Paired.
- Offline.
- Revoked (optional advanced view).

Device card:
- Device name and platform.
- Online/offline state.
- Storage contribution.
- Last seen.
- Trust status.
- Pair/connect action.

Device details:
- Node ID.
- Fingerprint.
- Platform/protocol version.
- Available/contributed storage.
- Replicas hosted.
- Pairing date.
- Permissions/role summary.
- Revoke device action.

A nearby unpaired peer must not be shown as trusted.

## 7.8 Pairing

Pairing workflow:
1. Choose Add device.
2. Display QR code on one device or scan another device's QR.
3. Show device name and identity fingerprint on both ends.
4. Require explicit confirmation on both devices.
5. Establish authenticated peer relationship.
6. Show success and return to device list.

Fallback:
- Manual IP/port connection may be available in advanced mode.
- Manual connection must still perform identity verification and pairing.

States:
- Waiting for scan.
- Connecting.
- Identity mismatch.
- Confirmation required.
- Pairing failed.
- Paired successfully.

## 7.9 Access management

Owner-only controls for an image:
- Visibility selector.
- List of authorized viewers.
- Add paired device.
- Remove/revoke device.
- Permission type.
- Grant status.
- Last grant update.

The UI must clearly distinguish:
- `Can store encrypted copy`
- `Can retrieve ciphertext`
- `Can view/decrypt`

A user may have more than one permission, but one must not imply another.

Revocation confirmation must explain:
- Future requests and key deliveries will be denied.
- Content already downloaded or copied by a recipient cannot be remotely erased.
- Stronger future protection may require key rotation/re-encryption.

## 7.10 Storage

Show:
- Total disk available to the OS (where supported).
- HiveNet storage contribution limit.
- HiveNet replica usage.
- Cache usage.
- Temporary transfer usage.
- Local owned objects, if retained.
- Storage contribution toggle/limit.

Explain that contributing storage means storing encrypted replicas, not granting the storage peer permission to view them.

## 7.11 Settings

Sections:
- Device name and identity.
- Network discovery.
- Storage contribution and quota.
- Privacy defaults.
- Compression preferences (advanced).
- Theme.
- Diagnostics/log export.
- About/version.

Do not expose private keys, tokens or secrets.

---

## 8. Navigation and route model

Suggested GoRouter routes:

```text
/onboarding
/dashboard
/gallery
/gallery/:contentId
/upload
/activity
/activity/:jobId
/devices
/devices/:nodeId
/pair
/storage
/settings
/settings/privacy
/gallery/:contentId/access
```

Navigation rules:
- Deep links must not bypass authorization.
- Opening an image route must fetch current metadata and permission state.
- If access is denied, show a locked/denied screen, not a blank page.
- On Android, use bottom navigation.
- On iOS, use sidebar/navigation rail and optionally split-pane details.

---

## 9. Frontend-to-backend interaction contracts

The frontend must not implement peer networking, replication decisions or cryptographic authorization itself. It calls typed application services/repositories.

Suggested repository interfaces:

```dart
abstract interface class DeviceRepository {
  Stream<List<PeerSummary>> watchPeers();
  Future<List<PeerSummary>> discoverPeers();
  Future<PairingSession> startPairing(String nodeId);
  Future<void> confirmPairing(String sessionId);
  Future<void> revokeDevice(String nodeId);
}

abstract interface class GalleryRepository {
  Stream<List<ImageSummary>> watchGallery(GalleryQuery query);
  Future<ImageDetails> getDetails(String contentId);
  Future<void> refresh();
}

abstract interface class UploadRepository {
  Future<UploadJob> createUpload(CreateUploadRequest request);
  Stream<UploadJob> watchJob(String jobId);
  Future<void> cancelJob(String jobId);
  Future<void> retryJob(String jobId);
}

abstract interface class RetrievalRepository {
  Future<RetrievalSession> requestImage(String contentId);
  Stream<RetrievalSession> watchRetrieval(String requestId);
  Future<void> cancelRetrieval(String requestId);
}

abstract interface class AccessRepository {
  Future<List<AccessGrant>> getGrants(String contentId);
  Future<void> grantAccess(GrantAccessRequest request);
  Future<void> revokeAccess(String contentId, String nodeId);
}

abstract interface class StorageRepository {
  Stream<StorageOverview> watchStorage();
  Future<void> updateContributionLimit(int bytes);
}
```

Example request models:

```dart
class CreateUploadRequest {
  final String localFilePath;
  final Importance importance;
  final Visibility visibility;
  final List<String> authorizedViewerNodeIds;
}

class GrantAccessRequest {
  final String contentId;
  final String granteeNodeId;
  final Set<PermissionType> permissions;
}
```

The actual local backend may expose these operations through in-process Dart services, a local API, or platform channels. The UI must depend on repository interfaces, not on the chosen transport.

### 9.1 Realtime updates

Use backend event streams for:
- Peer discovered/online/offline.
- Pairing state changes.
- Upload stage/progress.
- Replica committed/failed.
- Download progress.
- Access grant/revocation changes.
- Storage usage changes.
- Repair events.

If the backend stream disconnects:
- Preserve the last known state with a stale indicator.
- Attempt reconnection.
- Refresh authoritative state after reconnect.
- Do not reset a completed upload to in-progress because a stream reconnects.

### 9.2 Error mapping

Map backend errors to user-readable messages:

| Backend condition | Frontend message/action |
|---|---|
| No peers available | No storage peers are online. Keep the upload pending or try again later. |
| Insufficient replica targets | Not enough devices are available to complete replication. |
| Peer disconnected | Device disconnected. HiveNet will try another replica/peer. |
| Access denied | You do not have permission to view this image. |
| Key unavailable | Access was approved, but secure key delivery failed. Retry or contact the owner. |
| Integrity mismatch | The downloaded data failed verification and was not opened. |
| Unsupported image | This image format is not supported on this device. |
| Compression failed | HiveNet could not prepare this image. The original file was not uploaded. |
| Storage full | The selected peer does not have enough available storage. |
| Backend unavailable | HiveNet's local service is unavailable. Retry after it starts. |

---

## 10. Milestone-wise frontend implementation plan

Each milestone includes UI work, model work, backend integration, tests and exit criteria. Complete the milestones in order so that screens are not built against unstable data contracts.

### Milestone 0 — Design foundation and clickable shell

**Goal:** establish the visual system and app navigation before implementing complex features.

Frontend tasks:
- Set up Flutter Android and iOS targets.
- Add Riverpod and GoRouter.
- Create responsive app shell.
- Create theme tokens, typography and spacing.
- Build shared buttons, cards, status chips, dialogs and empty states.
- Implement mobile bottom navigation and safe-area-aware layouts.
- Create placeholder screens for all primary destinations.
- Define light/dark theme behavior.

Models:
- `AppDevice`
- `NetworkState`
- `UiError`

Backend integration:
- Mock repository interfaces only for initial layout work.
- Clearly isolate fake data behind a `DemoRepository`; never mix demo data with production repositories.

Tests:
- App launches on Android and iOS.
- Navigation works consistently on Android and iOS phone layouts.
- Theme and responsive layouts render correctly.
- VoiceOver and TalkBack can identify and operate primary actions.

Exit criteria:
- A user can navigate all main sections.
- All screens share consistent design tokens and shell.
- No production feature depends on hard-coded demo data.

### Milestone 1 — Device onboarding and network dashboard

**Goal:** make the current device and local network state visible.

Frontend tasks:
- Build onboarding flow.
- Device name setup.
- Explain local network and storage contribution.
- Permission request UX.
- Dashboard network status card.
- Peer count and empty states.
- Peer list preview.
- Backend unavailable and permission-denied states.

Models:
- `AppDevice`
- `PeerSummary`
- `NetworkState`
- `StorageOverview`

Backend integration:
- Read current device identity.
- Subscribe to network status.
- Subscribe to peer discovery.
- Request peer discovery refresh.
- Read local storage contribution configuration.

Tests:
- No peers.
- One discovered peer.
- Peer online/offline transitions.
- Local network permission denied.
- Backend initialization failure.

Exit criteria:
- Dashboard shows real device and peer state.
- UI does not claim a discovered device is paired.
- Network status updates without restarting the app.

### Milestone 2 — Pairing and trusted devices

**Goal:** let users pair devices and manage trust.

Frontend tasks:
- Nearby and paired device tabs.
- QR display and scanner screens.
- Identity confirmation screen.
- Fingerprint comparison UI.
- Manual IP/port fallback under advanced options.
- Pairing progress and failure states.
- Device detail page.
- Revoke-device confirmation.

Models:
- `PairingSession`
- `PeerSummary`
- `DeviceIdentitySummary`
- `TrustState`

Backend integration:
- Start/continue/confirm pairing.
- Observe pairing session state.
- Read paired-device list.
- Revoke a paired device.
- Refresh trust state.

Tests:
- Successful QR pairing.
- Cancel pairing.
- Fingerprint mismatch.
- Device disappears during pairing.
- Revoke paired device.
- Revoked peer remains visible as revoked, not trusted.

Exit criteria:
- Two devices can be paired through the UI.
- A user can inspect and revoke a trusted device.
- Discovery and pairing are visually and logically separate.

### Milestone 3 — Gallery and metadata browsing

**Goal:** build the shared gallery without downloading original image objects.

Frontend tasks:
- Gallery grid/list responsive layout.
- Search, filters and sorting.
- Image cards with owner, date, importance and replication state.
- Locked/metadata-only card state.
- Missing thumbnail state.
- Image details screen.
- Content ID copy action.
- Replica list and availability display.
- Empty, loading, stale and error states.

Models:
- `ImageSummary`
- `ImageDetails`
- `ReplicationSummary`
- `ReplicaSummary`
- `GalleryQuery`
- `ThumbnailState`
- `ImagePermissionState`

Backend integration:
- Subscribe to permitted gallery manifest updates.
- Query gallery using filters.
- Fetch image details.
- Refresh metadata.
- Fetch thumbnails only after the backend confirms thumbnail access.

Tests:
- Gallery with many images.
- Empty gallery.
- Metadata-only locked image.
- Offline image with no available replicas.
- Image with complete and incomplete replication.
- Search/filter/sort behavior.
- Ensure original image bytes are not requested during gallery browsing.

Exit criteria:
- Gallery renders synchronized metadata.
- A user can understand whether an image is viewable and available.
- Unauthorized thumbnails are never displayed.

### Milestone 4 — Upload flow and progress experience

**Goal:** provide a complete image-upload experience.

Frontend tasks:
- File picker and local preview.
- Supported-format validation.
- Importance selector.
- Visibility selector.
- Selected viewer picker for `selected_devices`.
- Storage peer placement preview.
- Compression progress.
- Encryption/planning/reservation/transfer progress.
- Per-peer transfer progress.
- Completion, pending, under-replicated and failure screens.
- Cancel/retry controls where supported.

Models:
- `CreateUploadRequest`
- `UploadJob`
- `UploadStage`
- `Importance`
- `Visibility`
- `ReplicationSummary`
- `ReplicaSummary`

Backend integration:
- Create upload job.
- Subscribe to job updates.
- Cancel/retry jobs.
- Read selected placement targets.
- Read compression and replica verification outcomes.

Tests:
- Supported image.
- Unsupported image.
- Compression error.
- No eligible peers.
- Insufficient peers for replication factor.
- One replica succeeds and another fails.
- Upload cancellation.
- App restart while a job is pending.

Exit criteria:
- User can complete an upload and see truthful progress.
- The UI only says fully replicated when the backend reports all required verified replicas.
- The UI distinguishes an upload that has bytes stored from one that has achieved its desired replication factor.

### Milestone 5 — Access management and secure image viewing

**Goal:** make permissions understandable and integrate authorized retrieval.

Frontend tasks:
- Access-management section on image details.
- Visibility controls.
- Authorized viewer list.
- Add/revoke viewer actions.
- Separate storage-only and view permissions.
- Access-check loading state.
- Secure key-delivery pending/failure state.
- Retrieval progress.
- Integrity verification state.
- Image viewer.
- Revocation warning and confirmation.

Models:
- `AccessGrant`
- `PermissionType`
- `ImagePermissionState`
- `RetrievalSession`
- `IntegrityState`
- `KeyDeliveryState`

Backend integration:
- Read access grants.
- Grant/revoke view permission.
- Request image retrieval.
- Subscribe to retrieval state.
- Backend performs access check and secure key delivery.
- Receive verified decrypted image through a safe local file/cache handle; do not pass raw keys to widgets.

Tests:
- Owner views own image.
- Authorized viewer retrieves image.
- Paired but unauthorized device is denied.
- Storage-only peer cannot view its stored replica.
- Revoked viewer is denied on subsequent requests.
- Key delivery failure.
- Ciphertext/plaintext integrity failure.
- Thumbnail access denial.

Exit criteria:
- A permitted viewer can retrieve and display an image.
- An unauthorized device cannot retrieve or preview it.
- Storage permission is never shown as view permission.
- Revocation messaging does not promise deletion of previously copied content.

### Milestone 6 — Activity, storage and operational visibility

**Goal:** give users clear visibility into background operations and disk contribution.

Frontend tasks:
- Activity feed with uploads/downloads/repairs.
- Transfer detail screen.
- Per-peer transfer progress.
- Retry/cancel actions.
- Storage dashboard.
- Contribution quota editor.
- Replica usage and cache breakdown.
- Offline and repair status.
- Notification/toast system for important events.

Models:
- `TransferJob`
- `ActivityItem`
- `StorageOverview`
- `RepairJob`
- `PeerSummary`

Backend integration:
- Subscribe to transfer and repair events.
- Query transfer history.
- Read storage metrics.
- Update storage contribution limit.
- Refresh after reconnect.

Tests:
- Interrupted transfer.
- Resumed transfer.
- Failed transfer and retry.
- Storage limit reached.
- Replica repair scheduled/completed.
- Stale activity stream and reconnection.

Exit criteria:
- User can identify what HiveNet is doing and why.
- Storage use is broken down clearly.
- Transfer and repair states remain consistent after app restart.

### Milestone 7 — Polish, accessibility and hackathon readiness

**Goal:** harden the complete frontend and prepare the demo.

Frontend tasks:
- Responsive polish across supported phone sizes and orientations.
- Dark/light theme review.
- Accessibility semantics and contrast.
- Keyboard navigation and shortcuts on iOS.
- Loading skeleton and animation performance.
- Offline banners and stale-data indicators.
- Empty/error state consistency.
- Confirmation dialogs for destructive/security actions.
- Demo mode with clearly labeled seeded data, if needed.
- Diagnostics screen for non-secret technical information.

Tests:
- Full Android end-to-end flow.
- Full iOS end-to-end flow.
- Mixed Android/iOS pairing.
- Upload and replication flow.
- Authorized retrieval from a replica after uploader disconnects.
- Unauthorized access denial.
- Revocation flow.
- Small-screen and large-screen layout.
- Backend restart and app restart recovery.

Exit criteria:
- No critical frontend crashes.
- No false success states.
- No unauthorized preview or retrieval.
- All core flows work on the target platforms.
- Demo data is never confused with real peer/network data.

---

## 11. Frontend acceptance criteria

The frontend is accepted when:

1. A user can onboard and identify the current device.
2. A user can discover peers and distinguish discovered from paired devices.
3. A user can pair and revoke a device.
4. A user can browse permitted gallery metadata without downloading originals.
5. A user can distinguish metadata-only access from view permission.
6. A user can select an image and configure importance and visibility.
7. A user can see compression, encryption, transfer and replication progress.
8. The app never reports full replication before required replicas are verified.
9. A user can inspect where replicas are stored.
10. A storage-only peer is not represented as an authorized viewer.
11. An authorized user can retrieve and view an image.
12. An unauthorized user receives a clear access-denied state.
13. A user can manage grants and understand revocation limitations.
14. A user can inspect transfer history and storage usage.
15. The UI recovers from peer disconnects and backend stream interruptions.
16. Android and iOS layouts are usable and consistent on supported phone sizes.

---

## 12. Non-functional frontend requirements

### Android and iOS lifecycle UX
- Onboarding must explain why HiveNet requests local-network access and how to enable it if denied.
- On iOS, handle the Local Network permission prompt and denial state; do not repeatedly prompt or imply discovery is working when permission is denied.
- On Android, handle required nearby/local-network permission states for the selected SDK and discovery implementation.
- Show a clear `App active — serving peers` state only while the peer service is actually running.
- When the app is backgrounded, suspended or disconnected, transition the local peer to unavailable after the backend's heartbeat lease expires.
- Do not promise that uploads, downloads or peer serving continue after the user leaves the app. Persist interrupted jobs and resume them when possible.
- Keep platform-specific permission explanations and settings links behind a shared UI abstraction.


### Performance
- Gallery scrolling must remain smooth with a large metadata list.
- Use lazy image loading and virtualized grids/lists.
- Do not load original images into gallery cards.
- Avoid rebuilding the entire app on every transfer event; scope Riverpod providers carefully.
- Keep expensive image preview work off the UI isolate where applicable.

### Reliability
- Preserve last known state with a stale marker when realtime updates disconnect.
- Re-fetch authoritative state after reconnect.
- Refresh peer availability whenever the app resumes; do not treat a previously online peer as currently servable without a fresh heartbeat/lease.
- Show distinct replica states: `stored_verified`, `online_servable`, `temporarily_unavailable`, `missing` and `corrupted`.
- Explain that a phone may retain an encrypted replica while its app is backgrounded or suspended and unable to serve it.
- Persist upload/transfer UI state and offer resume/retry when the app returns to the foreground.
- Do not assume that a UI event was committed until the backend confirms it.

### Security
- Do not store private keys in widget state or ordinary preferences.
- Do not log tokens, keys, wrapped key payloads or sensitive file contents.
- Do not treat route visibility as authorization.
- Always request current permission state before protected retrieval.
- Do not display plaintext thumbnails without permission.
- Avoid exposing local filesystem paths in ordinary UI.

### Accessibility
- Provide semantic labels for icon-only controls.
- Support VoiceOver and TalkBack semantics and platform accessibility conventions.
- Use text plus color/icon for statuses.
- Respect text scaling.
- Maintain adequate contrast and touch target sizes.

---

## 13. Suggested Flutter dependencies

Confirm current versions and platform support before implementation.

```bash
flutter pub add flutter_riverpod go_router
flutter pub add freezed_annotation json_annotation
flutter pub add collection intl
flutter pub add cached_network_image
flutter pub add file_picker
flutter pub add permission_handler
flutter pub add mobile_scanner qr_flutter
flutter pub add flutter_svg
flutter pub add logger

flutter pub add --dev build_runner freezed json_serializable
flutter pub add --dev flutter_test
```

Notes:
- `cached_network_image` is primarily designed around network image providers; use it only if its provider model fits the local backend. A custom local thumbnail provider may be more appropriate.
- `mobile_scanner` and `qr_flutter` need platform verification for Android/iOS. QR display and scanning can use different platform implementations.
- Do not add a dependency just because it appears in this list; verify Android and iOS support.
- The frontend should not depend directly on the compression package. It should observe compression progress and results from the upload/compression service.

---

## 14. Hackathon demo flow

Use three devices:

- Phone A: uploader and image owner.
- Phone B: authorized viewer and storage peer.
- iOS Phone C (iOS): storage-only peer initially.

Demo:

1. Launch HiveNet and show each device identity.
2. Discover and pair the three devices.
3. Configure Phone B and Phone C as storage contributors.
4. Upload an image from Phone A.
5. Select normal importance and `selected_devices` visibility.
6. Select Phone B as an authorized viewer.
7. Let the placement engine choose two storage peers, potentially Phone B and Phone C.
8. Show that both store encrypted replicas.
9. Show that Phone C is storage-only and cannot view the image.
10. Open the gallery on Phone B and retrieve the image after authorization.
11. Disconnect Phone A and retrieve from the remaining replica.
12. Revoke Phone B's grant and show future access denied.
13. Explain that revocation cannot erase a copy already downloaded by a recipient.

---

## 15. Implementation rules for the frontend team

- Build screens against typed repository interfaces, not directly against socket or protocol code.
- Keep demo fixtures separate from production repositories.
- Use enums for lifecycle and permission states.
- Every async action must have loading, success and failure behavior.
- Every list screen must have loading, empty, error and populated states.
- Never use a generic green “Success” label for under-replicated uploads.
- Never expose plaintext encryption keys to the UI.
- Never assume a paired device can view every image.
- Never infer permission from Wi-Fi membership, discovery, or replica placement.
- Do not block the UI while compressing, encrypting, hashing, transferring or verifying.
- Keep the same domain model semantics on Android and iOS, even if platform-specific widgets differ.

**Product principle:** the frontend is the control and observability layer for HiveNet. It must make a distributed storage system feel simple without hiding important facts about replication, availability, ownership, privacy or authorization.
