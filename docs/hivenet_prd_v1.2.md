# HiveNet --- Product Requirements Document (PRD)

**Version:** 1.2\
**Status:** Hackathon MVP specification\
**Platforms:** Android and iOS\
**Primary implementation:** Flutter + Dart

------------------------------------------------------------------------

## 1. Product overview

HiveNet is a peer-to-peer (P2P), distributed edge-storage application.
Participating Android and iOS phones form a local mesh
over the same Wi-Fi network. Each participating device can upload,
store, replicate, discover and serve images.

HiveNet presents a unified shared gallery, while the original image
files remain physically stored on participating devices' local
filesystems. Images are retrieved on demand from an available authorized
peer using their content identifiers.

HiveNet must not depend on a centralized cloud bucket or centralized
database to store image files.

### 1.1 Product vision

Make storage contributed by nearby devices behave like one resilient,
shared storage pool while keeping file ownership, access control and
physical storage distributed across the mesh.

### 1.2 Core principles

-   **Local-first:** image compression and processing happen on the
    sender's device.
-   **Peer-to-peer:** image bytes move directly between participating
    devices.
-   **Distributed storage:** original image files live on peer
    filesystems.
-   **Content-addressable:** an image is identified and retrieved by its
    content ID, not only by its filename or uploader.
-   **Request-based access:** seeing a gallery entry does not
    automatically authorize downloading the original.
-   **Resilient replication:** each image has multiple verified copies
    on distinct devices.
-   **No false success:** an upload is successful only after the
    required replicas are durably committed and verified.

------------------------------------------------------------------------

## 2. Goals and non-goals

### 2.1 MVP goals

1.  Build standalone Android and iOS applications using Flutter.
2.  Discover HiveNet peers on the same local Wi-Fi network.
3.  Pair and authenticate participating devices.
4.  Compress images on the sender before transfer.
5.  Generate a content ID for each processed image.
6.  Select storage peers using deterministic local placement, with optional AI-assisted ranking.
7.  Store encrypted image objects on peer filesystems.
8.  Maintain a shared, synchronized image manifest/gallery.
9.  Allow a user to request and retrieve an image on demand by content
    ID.
10. Enforce image visibility and access permissions.
11. Maintain two verified replicas for normal images; support an optional third replica for important images when three eligible devices are available.
12. Recover interrupted transfers and provide basic under-replication repair when peers return.

### 2.2 Non-goals for the hackathon MVP

-   Internet-wide peer connectivity and NAT traversal.
-   Cloud object storage or a central image-storage server.
-   A centralized backend database as the source of truth.
-   Erasure coding or distributed block-level striping.
-   Automatic synchronization of every photo on a user's phone.
-   Public anonymous access to images.
-   Production-grade multi-user identity federation.
-   Full conflict-free replicated data types (CRDTs) or a production
    DHT.
-   Guaranteed background availability after Android/iOS suspension, force-stop, or operating-system process termination.

The initial network scope is a trusted, paired group of devices on the
same Wi-Fi network. Internet-wide connectivity can be considered after
the local-network MVP works.

------------------------------------------------------------------------

## 3. Users and primary use cases

### 3.1 Participants

-   **Uploader:** selects an image, chooses its importance and
    visibility, and uploads it to HiveNet.
-   **Storage peer:** contributes disk space and stores verified image
    replicas.
-   **Viewer/requester:** browses the shared gallery and requests an
    image.
-   **Device owner:** pairs devices, manages trusted peers, storage
    contribution and local settings.

A single device may perform all four roles.

### 3.2 Key use cases

1.  A user pairs two phones.
2.  A phone discovers other online HiveNet devices.
3.  A user selects an image and compresses it locally.
4.  HiveNet selects storage peers and creates the required replicas.
5.  Paired users see the permitted image entry in their shared gallery.
6.  A viewer taps a thumbnail and requests the original image.
7.  HiveNet locates an available authorized replica and transfers the
    image.
8.  A peer disconnects; another verified replica continues serving
    requests.
9.  A peer reconnects; HiveNet reconciles metadata and repairs missing
    replicas.
10. An owner revokes a peer's access so future requests are denied.

------------------------------------------------------------------------

## 4. Functional requirements

### FR-01: Device onboarding and pairing

-   The app shall create a persistent unique `nodeId` for each
    installation.
-   Devices shall discover peers using mDNS service discovery.
-   The MVP shall support QR-based pairing and a manual IP/port
    fallback.
-   Pairing shall establish a trusted device identity and authenticated
    communication credentials.
-   A device shall be able to revoke a previously paired peer.
-   Being connected to the same Wi-Fi network shall not, by itself,
    grant access to stored images.

**Acceptance criteria** - Two or more devices on the same Wi-Fi network
discover each other. - An unpaired device cannot retrieve protected
image data. - A revoked device is denied subsequent protected requests.

### FR-02: Peer telemetry

Each peer shall advertise or provide authenticated telemetry containing:

-   `nodeId`
-   `deviceName`
-   `protocolVersion`
-   `ipAddresses`
-   `port`
-   `availableStorageBytes`
-   `totalStorageBytes`
-   `reservedStorageBytes`
-   `activeTransfers`
-   `lastSeen`
-   `status`
-   `measuredLatencyMs`
-   `bandwidthEstimate`
-   `reliabilityScore`

Telemetry is time-sensitive and must be treated as an estimate. The
receiving storage peer must independently validate available capacity
before accepting a write.

**Acceptance criteria** - The device list displays current peers and
their approximate available storage. - A peer that misses heartbeats is
marked offline after a configurable timeout. - Stale telemetry is not
used as proof that a peer can accept a file.

### FR-03: Client-side image compression

The sender must process the selected image before any image bytes are
sent to another device.

**Selected library:** `flutter_image_compress` (confirm the exact
package identifier and current Android/iOS support during
implementation; the project decision is to use the Flutter
image-compression package rather than the pure-Dart `image` package).

The implementation must verify that the selected package/version
supports both mobile platforms and the required output format. If either mobile platform cannot produce the agreed output format reliably, use a compatible encoder or platform-specific adapter before the MVP is considered complete. Do not silently ship
platform-dependent output differences.

Initial compression policy:

  Image category       Target quality   Maximum dimension
  ---------------- ------------------ -------------------
  Normal                           80             2048 px
  Important                        90             2560 px
  Thumbnail          Tuned separately         320--480 px

Quality values are initial tuning targets, not guaranteed file-size
ratios. Preserve aspect ratio. Normalize orientation before encoding.
Strip GPS metadata by default. Support JPEG, PNG and WebP inputs for the
MVP; HEIC/HEIF support is out of scope unless the chosen
package/platform decoder is verified.

Compression pipeline:

1.  Read the selected image and inspect its dimensions and format.
2.  Normalize orientation.
3.  Resize to the category's maximum dimension without upscaling.
4.  Encode the compressed image in the agreed cross-platform format.
5.  Generate a thumbnail.
6.  Compute `contentId = SHA-256(compressedPlaintextBytes)`.
7.  Encrypt the compressed object.
8.  Compute `ciphertextHash = SHA-256(encryptedObjectBytes)`.
9.  Pass the encrypted object and manifest metadata to the storage
    router.

CPU-heavy image work must not block Flutter's UI thread. Profile memory
use for large images.

**Acceptance criteria** - No original image bytes are sent before
compression completes. - The compressed output can be decoded on both
Android and iOS. - The same content produces the same content ID
when the exact compressed bytes are identical. - Compression failure
prevents upload and is reported to the user. - Platform-specific
encoding differences are covered by tests.

### FR-04: Image importance and replication policy

The uploader shall classify each image as:

-   `normal`: desired replication factor 2 (MVP requirement).
-   `important`: desired replication factor 3 when the optional important-image policy is enabled and three eligible devices are available. If not, the item remains visibly under-replicated; the third copy is not a release blocker for the MVP.

Replicas must be stored on distinct physical devices. A replica counts
only after the destination has written the complete object, verified its
hash and committed it to durable storage.

The uploader's own device counts as a replica only if it explicitly
stores a durable local copy and advertises that copy as a storage
replica.

If enough eligible peers are unavailable, the upload shall remain
`pending` or `under_replicated`. The UI must not report full success
until the requested number of replicas is verified.

### FR-05: Smart storage routing and decision model

HiveNet shall use a hybrid decision architecture:

1.  A deterministic Dart eligibility filter removes peers that are
    offline, untrusted, incompatible, overloaded or lack sufficient
    storage.
2.  A decision model (preferred evaluation candidate: Laya; alternative:
    Jev) may recommend a placement strategy or rank eligible candidates
    using current telemetry and upload requirements.
3.  A deterministic Dart validator checks the recommendation.
4.  The replication manager reserves capacity and coordinates commits.

The AI model must never bypass hard safety constraints or directly
authorize access.

Candidate scoring for the deterministic fallback:

`Score(n) = 0.35*C + 0.30*L + 0.20*U + 0.15*B`

Where each normalized value is between 0 and 100:

-   `C`: storage capacity suitability.
-   `L`: latency suitability (higher score means lower latency).
-   `U`: reliability/uptime.
-   `B`: bandwidth suitability.

The exact normalization and score weights are configurable and must be
benchmarked. The score is a fallback/ranking aid, not a substitute for
hard eligibility checks.

**AI availability and fallback** - The network must continue to upload
and retrieve images if the AI endpoint is unavailable. - The
deterministic router is always available locally. - Do not send private
image content to the decision model. Send only necessary peer telemetry
and upload metadata. - Record the model recommendation, input snapshot,
selected peers and final validator result for debugging. - Evaluate Laya
and Jev against the same representative placement scenarios before
selecting the production integration.

### FR-06: Storage reservation and durable commit

Before transfer, the sender/router shall ask each target peer to reserve
sufficient space.

Suggested flow:

1.  `STORAGE_RESERVE`
2.  `STORAGE_ACCEPT` or `STORAGE_REJECT`
3.  `UPLOAD_BEGIN`
4.  `CHUNK_DATA` / `CHUNK_ACK`
5.  `UPLOAD_COMMIT`
6.  Destination verifies complete object and hash.
7.  Destination atomically moves the temporary object into its final
    content-addressed path.
8.  Destination returns `REPLICA_COMMITTED`.

A peer must reserve capacity atomically to prevent concurrent uploads
from over-allocating disk space.

Temporary or incomplete files must not appear as valid replicas.

### FR-07: Shared gallery and metadata synchronization

HiveNet shall distinguish the shared gallery metadata from the actual
image objects.

The shared gallery shall display entries permitted by the applicable metadata visibility policy. Original image bytes are not synchronized as part of ordinary gallery browsing. Thumbnail bytes are also protected image content and must follow the image's access policy; do not publish plaintext thumbnails to all discovered peers.

The shared gallery shall display entries permitted by the applicable
visibility policy. An entry may include:

-   `contentId`
-   display filename
-   MIME type
-   compressed size
-   dimensions
-   thumbnail reference or thumbnail bytes
-   owner/uploader node ID
-   creation timestamp
-   importance
-   visibility
-   desired replication factor
-   known replica status
-   availability state

The gallery shall synchronize manifests and thumbnails, not
automatically download every original image.

Metadata is stored locally in SQLite on each device and synchronized
between peers. The MVP shall use owner-authoritative signed manifest events, monotonic per-owner versions, tombstones and deterministic reconciliation. A
single device's SQLite database must not be treated as the network-wide
authoritative database.

The UI must distinguish: - `available`: at least one known verified
online replica. - `temporarily_unavailable`: metadata exists but no
known replica is reachable. - `under_replicated`: fewer verified
replicas than desired. - `pending`: upload or synchronization is
incomplete. - `deleted`: a valid deletion/tombstone has been observed.

Gallery metadata visibility and image-view permission are separate. A user may be allowed to see a limited manifest entry without being allowed to retrieve or decrypt the image. Thumbnail delivery must follow the image's view policy; do not treat thumbnails as harmless metadata.

### FR-08: Content-addressable on-demand retrieval

This is a core requirement.

**Gallery visibility does not automatically grant permission to retrieve
an original image.** The app must apply the image's access policy before
returning image bytes.

Retrieval flow:

1.  Viewer taps a gallery item.
2.  Client sends `GET_IMAGE` with the `contentId`, requester identity
    and request ID.
3.  The content locator looks up known replica locations.
4.  The replica selector filters for online, trusted, authorized peers
    with a verified copy.
5.  The selector chooses the best eligible host using latency, bandwidth
    and reliability.
6.  The selected host validates the requester's identity and image
    permission.
7.  If permitted, the host sends the encrypted object in chunks.
8.  The requester acknowledges chunks and supports retry/resume.
9.  The requester verifies `ciphertextHash`, decrypts the object and
    verifies `contentId` against the plaintext compressed bytes.
10. The image is displayed and may be cached locally.

If the first host fails, the client shall try another known verified
replica. The original uploader is not required to be online if another
replica is available.

Suggested protocol messages:

  Message             Purpose
  ------------------- --------------------------------------
  `GET_IMAGE`         Request image by content ID
  `IMAGE_LOCATE`      Find peers holding the content
  `IMAGE_AVAILABLE`   Peer reports a verified copy
  `ACCESS_CHECK`      Check requester permissions
  `ACCESS_GRANTED`    Authorize retrieval
  `ACCESS_DENIED`     Deny retrieval
  `IMAGE_BEGIN`       Begin image transfer
  `CHUNK_DATA`        Send a chunk
  `CHUNK_ACK`         Acknowledge a chunk
  `IMAGE_COMPLETE`    Mark transfer complete
  `IMAGE_VERIFY`      Exchange or confirm integrity result
  `IMAGE_NOT_FOUND`   Peer does not hold the content
  `TRANSFER_RESUME`   Resume an interrupted transfer

The protocol shall use framed messages over TCP. It must not assume that
one socket read equals one complete JSON message.

### FR-09: Access control and security

Initial visibility modes:

-   `private`: only the owner/uploader device or explicitly authorized
    owner identity can retrieve the image.
-   `network_shared`: approved members of the HiveNet group can retrieve it.
-   `selected_devices`: only explicitly permitted paired device identities can retrieve it.

Security requirements:

-   Pair devices using an authenticated pairing process.
-   Authenticate every peer-to-peer request.
-   Encrypt image objects using AES-256-GCM.
-   Protect key material; do not store raw encryption keys in ordinary
    metadata.
-   Use authenticated transport, preferably TLS with
    certificate/public-key pinning after the pairing design is
    established.
-   Verify hashes after transfer.
-   Reject malformed, oversized or unauthorized requests.
-   Apply request and transfer limits to reduce abuse.
-   Do not treat Wi-Fi membership or mDNS discovery as authentication.

For encrypted storage, maintain: - `contentId`: SHA-256 of compressed
plaintext. - `ciphertextHash`: SHA-256 of the encrypted object.

The same encrypted object should be replicated rather than independently
encrypted at each destination. Key distribution must ensure authorized
requesters can decrypt the object without exposing keys to untrusted
storage peers. This key-sharing design is a required security design
task before protected sharing is considered complete.


### FR-09A: Separate ownership, storage and viewing permissions

HiveNet shall enforce four separate concepts for every image:

1. **Ownership:** the user/device identity that controls the image manifest and its access policy.
2. **Storage authorization:** permission for a peer to hold an encrypted replica. This does not grant permission to view or decrypt it.
3. **View authorization:** permission for a device identity to obtain the image's decryption key and view the image.
4. **Retrieval authorization:** permission to request and receive the encrypted image object. Retrieval authorization must be checked independently of whether a peer stores a replica.

**Mandatory rule:** being on the same Wi-Fi network, discovering a peer through mDNS, being paired, or being selected by the AI placement model must never by itself grant image-view permission.

Example: Joel uploads an image and the router selects Tushar's and Kesav's devices as storage peers. Those devices may store and serve the encrypted object, but neither Tushar nor Kesav can decrypt or view it unless Joel explicitly grants their device identities view permission.

The AI decision model is limited to storage placement recommendations. It must never create, modify, approve or revoke access grants, distribute keys, or make authorization decisions.


#### Permission matrix

| Participant state | Store encrypted replica | Serve ciphertext | Receive decryption key | View image |
|---|---:|---:|---:|---:|
| Unpaired Wi-Fi device | No | No | No | No |
| Paired storage-only peer | Yes, if selected | Yes, after authenticated retrieval check | No | No |
| Explicitly authorized viewer | Only if separately selected | Only if separately selected | Yes, after access check | Yes |
| Owner | Yes, if local copy retained | Yes, if hosting a replica | Yes | Yes |

A device may have more than one role. Permissions are evaluated per image and per action; no role implies another permission.

#### Visibility modes

Each image must have one explicit visibility policy:

- `private`: only the owner-authorized device identity or identities can view the image.
- `selected_devices`: only explicitly selected, paired device identities can view the image.
- `network_shared`: members of an explicitly approved HiveNet group can view the image. This does not mean every device on the Wi-Fi network.

The UI must explain who can view an image before upload. The owner must be able to inspect and change the image's access list.

#### Authorization and retrieval flow

1. A requester discovers a gallery manifest only if its metadata visibility policy permits it.
2. The requester selects an image. The app sends an authenticated `ACCESS_CHECK` for the requested action and `contentId`.
3. The storage peer validates an owner-signed, device-bound grant and its expiry against the latest revocation state it possesses. It must not invent or broaden permissions. The owner does not need to be online for a still-valid cached grant; see Section 13.3 for the bounded offline-revocation trade-off.
4. If denied, return `ACCESS_DENIED`; do not deliver a decryption key or protected thumbnail.
5. If allowed, deliver a key wrapped for the requester's paired device public key, or use an equivalent authenticated secure key-delivery mechanism.
6. The requester locates an online verified replica and requests the encrypted object.
7. The storage peer authenticates the requester and checks retrieval authorization before serving ciphertext.
8. The requester verifies `ciphertextHash`, decrypts locally, verifies the plaintext `contentId`, and then displays the image.

The storage peer does not need the plaintext image key to store or serve ciphertext. A storage peer must not receive a plaintext key merely because it stores a replica.

#### Encryption and key handling

- Encrypt each compressed image with a random per-image data-encryption key using an authenticated encryption scheme such as AES-256-GCM.
- Store only encrypted image bytes on storage peers.
- Wrap the per-image key separately for each authorized device (or use a vetted group-key design); never put a plaintext key in a manifest, mDNS record, log, or ordinary transfer message.
- Bind key delivery to an authenticated paired device identity.
- Use authenticated transport for peer control and data connections. The implementation must select and document a suitable TLS/certificate-pinning or equivalent authenticated channel design.
- Keep key material out of logs and crash reports. Use platform-appropriate secure key storage where available.
- Encrypt thumbnails or apply the same visibility policy to them. A thumbnail is image content and must not be exposed merely because a manifest is visible. The MVP should prefer encrypted thumbnails with authorized key access, or omit the preview for requesters who are not authorized.

#### Revocation limitations

Revocation must prevent future authorization checks and future key deliveries. However, HiveNet cannot make a recipient forget plaintext or a decryption key that was already obtained, nor can it claw back screenshots or copied files.

For stronger future revocation, the design may use short-lived wrapped keys or rotate the image key and re-encrypt/update replicas. This can protect future access but cannot revoke plaintext already copied by a recipient. The UI and documentation must not promise retroactive deletion from another device.

**Acceptance criteria**
- A storage-only peer can hold and serve ciphertext but cannot decrypt the image.
- A paired device without a view grant receives `ACCESS_DENIED` and no decryption key.
- A device on the same Wi-Fi but not paired/authorized cannot retrieve protected image data.
- Revoking a grant blocks subsequent access checks and key deliveries.
- A thumbnail is not visible to a requester who is not authorized to view it.
- Tampered ciphertext or plaintext fails integrity verification and is not displayed.
- The AI placement component has no code path or permission to grant access or deliver keys.

### FR-09B: Access-control protocol messages

The peer protocol shall support the following logical messages (exact wire schema may evolve):

- `ACCESS_REQUEST`: request permission for an action on a `contentId`.
- `ACCESS_CHECK`: authenticated policy check for a requester and action.
- `ACCESS_GRANT`: owner-authorized grant or grant update.
- `ACCESS_REVOKE`: owner-authorized revocation.
- `ACCESS_GRANTED`: response confirming the requested action is allowed.
- `ACCESS_DENIED`: response denying the requested action.
- `KEY_REQUEST`: request a wrapped image key after authorization.
- `KEY_DELIVERY`: deliver a key wrapped for the authorized recipient device.

Every message must include the protocol version, request/operation ID, authenticated sender identity and relevant content ID. Access changes must be attributable to the owner identity and synchronized as versioned manifest/access-policy events. Do not trust a requester-supplied `nodeId` without binding it to the authenticated paired connection.

### FR-10: Local storage layout

Image objects are stored on each peer's local filesystem. SQLite stores
metadata and local state only.

Suggested layout:

``` text
HiveNet/
├── objects/
│   ├── ab/
│   │   └── <contentId>.enc
│   └── 3f/
│       └── <contentId>.enc
├── thumbnails/
│   └── <contentId>.webp
├── cache/
│   └── retrieved/
├── temporary/
│   └── incomplete-transfers/
└── database/
    └── hivenet.sqlite
```

Use the platform's application-support directory via `path_provider`.
Use atomic writes/renames where supported. Do not use user-visible
gallery folders as the authoritative object store.

### FR-11: Offline handling and replica repair

-   Peers send periodic heartbeats.
-   A peer that misses the configured heartbeat threshold is marked
    offline.
-   Retrieval shall try another verified replica when a host is offline.
-   If no replica is online, show the image metadata but mark the image
    temporarily unavailable.
-   When peers reconnect, reconcile manifests and replica status.
-   The replication manager shall identify under-replicated objects and
    schedule repairs when eligible peers become available.
-   Replica repair must use the same verification and commit process as
    a normal upload.

### FR-12: User interface

MVP screens:

1.  **Onboarding:** create device identity and explain local-network
    permissions.
2.  **Pair devices:** QR pairing and manual connection fallback.
3.  **Network dashboard:** discovered peers, online state, storage
    contribution and health.
4.  **Shared gallery:** thumbnails, metadata, availability and
    importance.
5.  **Image details:** owner, content ID, visibility, replicas and
    retrieval action.
6.  **Upload flow:** choose image, importance, visibility and upload
    progress.
7.  **Access management:** visibility mode, authorized viewers, storage-only peers, grant/revoke controls and a clear explanation of revocation limits.
8.  **Transfer activity:** uploads, downloads, retries and failures.
9.  **Storage dashboard:** local storage used, contributed capacity and
    stored replicas.
10. **Settings:** device identity, storage limit, trusted peers and
    security controls.

Provide clear status labels for pending uploads, under-replicated files,
unavailable content and failed transfers.

------------------------------------------------------------------------

## 5. System architecture

### 5.1 Logical components

``` text
Flutter UI
   |
   +-- Gallery feature
   +-- Upload feature
   +-- Device/network dashboard
   +-- Transfer activity
   |
Application services
   |
   +-- Image compression service
   +-- Manifest/gallery service
   +-- Content retrieval manager
   +-- Access-control service
   |
Core infrastructure
   |
   +-- AI-assisted decision adapter
   +-- Deterministic storage router
   +-- Replication manager
   +-- Peer discovery (mDNS)
   +-- TCP client/server and message framing
   +-- Chunk transfer manager
   +-- Encryption and hashing
   +-- Filesystem object store
   +-- Drift/SQLite metadata store
```

### 5.2 Per-device responsibilities

Every participating device runs the same application architecture and
may act as: - an uploader, - a requester, - a storage peer, - a
content-serving host, - a metadata synchronization peer.

The uploader coordinates an upload, but the network must not depend on
one permanent coordinator. The MVP may use the uploader as the temporary
coordinator for a single upload transaction, while durable object
storage and metadata remain distributed.

### 5.3 Network topology

-   Discovery: mDNS using a HiveNet TCP service type, for example
    `_hivenet._tcp.local`.
-   Data transport: direct TCP connections between peers.
-   Initial scope: same Wi-Fi/local network.
-   Fallback: manual IP and port entry.
-   Internet-wide NAT traversal, relay services and cross-network
    routing are deferred.

### 5.4 Suggested mDNS advertisement

``` json
{
  "nodeId": "node-123",
  "deviceName": "HiveNet device",
  "port": 45678,
  "protocolVersion": 1
}
```

Do not put secrets, access tokens or encryption keys in mDNS records.

------------------------------------------------------------------------

## 6. Data model

The following is a logical schema. Exact Drift table definitions may
evolve during implementation.

### 6.1 `nodes`

-   `nodeId` (primary key)
-   `deviceName`
-   `platform`
-   `ipAddresses`
-   `port`
-   `protocolVersion`
-   `totalStorageBytes`
-   `availableStorageBytes`
-   `reservedStorageBytes`
-   `lastSeen`
-   `status`
-   `latencyMs`
-   `bandwidthEstimate`
-   `reliabilityScore`

### 6.2 `files`

-   `contentId` (primary key)
-   `ownerNodeId`
-   `fileName`
-   `mimeType`
-   `fileSizeBytes`
-   `width`
-   `height`
-   `thumbnailReference`
-   `importance`
-   `visibility`
-   `desiredReplicationFactor`
-   `createdAt`
-   `manifestVersion`
-   `availabilityStatus`
-   `encryptionMetadata`

### 6.3 `replicas`

-   `contentId`
-   `nodeId`
-   `status`
-   `verified`
-   `ciphertextHash`
-   `storedAt`
-   `lastVerifiedAt`
-   `lastSeenAt`

A replica record is evidence of a believed location, not proof that the
peer is currently online. Revalidate before retrieval.

### 6.4 `upload_jobs`

-   `jobId`
-   `contentId`
-   `status`
-   `requestedReplicationFactor`
-   `createdAt`
-   `completedAt`
-   `failureReason`

### 6.5 `transfers`

-   `transferId`
-   `contentId`
-   `sourceNodeId`
-   `destinationNodeId`
-   `direction`
-   `status`
-   `bytesTransferred`
-   `totalBytes`
-   `startedAt`
-   `updatedAt`

### 6.6 `trusted_devices`

-   `nodeId`
-   `publicKey`
-   `fingerprint`
-   `displayName`
-   `pairedAt`
-   `revokedAt`
-   `trustStatus`

### 6.7 `access_grants`

-   `contentId`
-   `granteeNodeId` or group identifier
-   `permission` (for example: `view`, `retrieve`, or `store_encrypted`)
-   `grantedBy`
-   `grantVersion`
-   `keyVersion` (when applicable)
-   `createdAt`
-   `revokedAt`

### 6.8 `device_keys`

- `nodeId`
- `publicKey`
- `keyAlgorithm`
- `fingerprint`
- `createdAt`
- `rotatedAt`
- `revokedAt`

Public keys must be bound to authenticated paired device identities. Private keys are never stored in the shared manifest or transmitted to peers.

### 6.9 `wrapped_image_keys`

- `contentId`
- `recipientNodeId`
- `wrappedKey`
- `keyVersion`
- `createdAt`
- `expiresAt` (optional, for short-lived grants)
- `revokedAt`

The wrapped key must be usable only by the intended recipient identity. Never store plaintext image keys in this table.

### 6.10 `manifest_events`

-   `eventId`
-   `contentId`
-   `originNodeId`
-   `manifestVersion`
-   `eventType`
-   `payload`
-   `createdAt`

Use versioned manifests and tombstones for deletion. Avoid assuming
wall-clock timestamps alone provide a reliable conflict-resolution
order.

------------------------------------------------------------------------

## 7. Proposed Flutter project structure

``` text
hivenet/
├── lib/
│   ├── main.dart
│   ├── app/
│   │   ├── app.dart
│   │   ├── router.dart
│   │   └── theme/
│   ├── features/
│   │   ├── gallery/
│   │   ├── uploads/
│   │   ├── retrieval/
│   │   ├── devices/
│   │   ├── transfers/
│   │   ├── storage_dashboard/
│   │   └── settings/
│   ├── core/
│   │   ├── compression/
│   │   │   ├── image_compressor.dart
│   │   │   ├── thumbnail_generator.dart
│   │   │   └── compression_config.dart
│   │   ├── networking/
│   │   │   ├── peer_discovery.dart
│   │   │   ├── socket_server.dart
│   │   │   ├── socket_client.dart
│   │   │   ├── message_protocol.dart
│   │   │   ├── message_framing.dart
│   │   │   └── heartbeat_service.dart
│   │   ├── router_engine/
│   │   │   ├── storage_router.dart
│   │   │   ├── node_scorer.dart
│   │   │   ├── decision_model_adapter.dart
│   │   │   ├── quota_manager.dart
│   │   │   └── replication_manager.dart
│   │   ├── retrieval/
│   │   │   ├── image_request_manager.dart
│   │   │   ├── content_locator.dart
│   │   │   ├── replica_selector.dart
│   │   │   ├── access_control.dart
│   │   │   └── download_manager.dart
│   │   ├── storage/
│   │   │   ├── file_store.dart
│   │   │   ├── chunk_manager.dart
│   │   │   └── integrity_checker.dart
│   │   ├── security/
│   │   │   ├── encryption_service.dart
│   │   │   ├── device_identity.dart
│   │   │   └── pairing_service.dart
│   │   └── metadata/
│   │       ├── manifest.dart
│   │       ├── metadata_sync.dart
│   │       └── reconciliation.dart
│   ├── database/
│   │   ├── app_database.dart
│   │   ├── tables/
│   │   └── daos/
│   └── shared/
│       ├── models/
│       ├── widgets/
│       └── utils/
├── test/
├── integration_test/
├── android/
├── ios/
└── pubspec.yaml
```

------------------------------------------------------------------------

## 8. Technology stack

  -----------------------------------------------------------------------
  Layer                               Selected technology
  ----------------------------------- -----------------------------------
  Application                         Flutter

  Language                            Dart

  State management                    `flutter_riverpod`

  Navigation                          `go_router`

  Image compression                   `flutter_image_compress` (verify
                                      package identifier/platform
                                      support)

  Peer discovery                      `bonsoir`

  Peer networking                     Dart `dart:io` TCP sockets

  Local database                      Drift + SQLite

  Filesystem                          `path_provider` + `dart:io`

  File picker                         `file_picker`

  Hashing                             `crypto`

  Encryption                          `cryptography`

  Identifiers                         `uuid`

  Logging                             `logger`

  Code generation                     `drift_dev`, `build_runner`

  Decision model                      Laya preferred; Jev alternative;
                                      benchmark before final selection
  -----------------------------------------------------------------------

No conventional application backend is required for the local-network
MVP. No cloud image bucket or central database is used.

------------------------------------------------------------------------

## 9. Performance and reliability requirements

Initial engineering targets; validate them on actual Android and iOS
hardware.

-   Discover peers within 5--10 seconds on a typical local Wi-Fi
    network.
-   Heartbeat interval: approximately 5 seconds.
-   Initial transfer chunk size: 1 MiB.
-   Start with no more than two concurrent uploads per peer.
-   Support per-chunk acknowledgements and resumable transfers.
-   Verify the complete object before marking a replica committed.
-   Avoid loading multiple full-size image copies into memory
    unnecessarily.
-   Keep image processing and network operations off the UI thread.
-   The app shall remain usable if the AI decision endpoint is
    unavailable.
-   The app shall attempt alternate replicas when a serving peer becomes
    unreachable.
-   The gallery shall show metadata for temporarily unavailable images.

These are starting values, not guaranteed performance claims. Tune them
through profiling and network tests.

------------------------------------------------------------------------

## 10. Android and iOS platform considerations

HiveNet is a mobile-only application. Android and iOS have different
network discovery, app lifecycle, permission and storage rules. The
product must expose a truthful peer availability state rather than
assuming that a phone can serve files continuously.

### 10.1 Foreground-first peer availability (locked decision)

- The MVP peer server is supported while HiveNet is active in the
  foreground. Android may optionally use a user-visible foreground
  service after a separate lifecycle and policy test, but this is not a
  cross-platform MVP requirement.
- iOS background execution is not a reliable way to keep a general
  purpose TCP peer server continuously available. HiveNet must not
  promise that an iPhone will serve replicas while suspended or
  terminated.
- When the app moves to the background, loses its network, or is
  suspended, the device must transition to `temporarily_unavailable`
  after its lease/heartbeat expires. Its replica remains stored but is
  not counted as currently online/servable.
- The UI must distinguish `stored`, `online_and_servable`,
  `temporarily_unavailable`, `missing` and `corrupted` replica states.
- Uploads and downloads are foreground operations in the MVP. Interrupted
  work is persisted and resumed when the app is active again.
- The hackathon demo must keep the serving peer's app open. Do not rely
  on background execution to prove retrieval resilience.

### 10.2 Local network permissions and discovery

- On iOS, provide a clear `NSLocalNetworkUsageDescription` and declare
  the Bonjour service type in `NSBonjourServices` for the selected
  mDNS service. Request permission through a user-understandable
  onboarding action and handle denial gracefully.
- On Android, declare the network permissions required by the minimum
  and target SDKs, and validate multicast discovery on real devices.
  Acquire/release a Wi-Fi multicast lock only if the selected discovery
  implementation requires it.
- The discovery adapter must handle permission denial, Wi-Fi changes,
  multicast filtering and networks with client isolation.
- Manual IP/port entry is a diagnostic fallback only; it is not a
  substitute for authenticated pairing.
- Test on at least two physical Android devices and two physical iOS
  devices where possible. Simulator-only success is insufficient.

### 10.3 Mobile filesystem and storage durability

- Store durable replicas in the app's application-support/documents
  area, not in a temporary or cache directory that the OS may purge.
- Keep temporary transfer chunks separate from committed objects. Use
  atomic commit/rename where supported and verify the final hash.
- Treat app uninstall, app data clearing, device restore and OS storage
  pressure as possible loss of a replica. A replica is not permanent
  backup storage.
- Exclude the distributed object store and transient transfer data from
  automatic cloud-device backups unless a later product decision
  explicitly changes this privacy/storage model.
- Enforce a user-configurable storage quota and leave a safety margin
  for the operating system and other apps. Recheck capacity immediately
  before committing a replica.
- Never use a cache directory as the only copy of an acknowledged
  replica.

### 10.4 Image import and compression compatibility

- Validate JPEG, PNG and WebP input on both platforms. Because iPhones
  commonly produce HEIC/HEIF photos, the MVP must either support HEIC
  import through a tested native decoder/conversion path or clearly
  reject it with an actionable message; silently failing is not
  acceptable.
- Run a proof of concept using the actual image picker and compression
  plugin on physical Android and iOS devices. Verify orientation,
  color, alpha behavior where relevant, output format, dimensions,
  memory use and large-image behavior.
- Keep compression behind a Dart interface so a platform-specific
  Android/iOS implementation can be substituted without changing upload
  logic.
- Strip GPS metadata by default. Do not upload the original image if
  compression or metadata sanitization fails.

### 10.5 Secure key storage and app lifecycle

- Store device private keys and locally held key-encryption material in
  platform-backed secure storage (Android Keystore and iOS Keychain via
  a maintained Flutter integration). Do not store private keys in
  SQLite, preferences, logs or ordinary files.
- Test behavior after app restart, device reboot, biometric/passcode
  changes and secure-storage access failures. Define recovery behavior;
  do not silently generate a replacement identity that cannot access
  existing grants.
- Network listeners must stop cleanly when the app lifecycle or OS
  requires it. Restarting HiveNet must restore local metadata and
  committed replicas before advertising the device as ready.

### 10.6 Mobile compatibility gate

Before full implementation, build a small Android+iOS spike that proves:

1. Local-network permission can be requested and handled on both
   platforms.
2. Two physical devices discover one another using mDNS.
3. A foreground TCP connection can transfer a framed file in chunks.
4. A network interruption is detected and the transfer can resume.
5. JPEG and HEIC import behavior is known and tested.
6. Compression output can be decoded and hash-verified on the other
   platform.
7. A device identity/private key survives app restart using secure
   platform storage.
8. A peer is correctly marked unavailable when its app is backgrounded
   or suspended.

Do not proceed to the full gallery and replication implementation until
these checks pass or an explicit workaround is documented.

------------------------------------------------------------------------

## 11. MVP milestones

The milestones are ordered to retire the highest-risk mobile platform
unknowns before building higher-level product features.

### Milestone 0 — Android/iOS feasibility spike

- Create minimal Flutter apps for Android and iOS.
- Verify mDNS discovery and local-network permission flows on physical
  devices.
- Verify foreground TCP listener/client, framing and chunk transfer.
- Verify app lifecycle transitions and peer availability reporting.
- Verify image import/compression, including an iPhone HEIC sample.
- Verify secure device-key persistence on both platforms.

**Exit criteria:** the team can transfer and verify a file between an
Android phone and an iPhone while both apps are active, and accurately
show unavailable state when a peer is backgrounded or disconnected.

### Milestone 1 — Mobile foundation and local persistence

- Create the production Flutter Android/iOS app structure.
- Add Riverpod, GoRouter, Drift/SQLite and app-support filesystem paths.
- Implement device identity and secure key storage.
- Implement persisted transfer jobs and replica state models.

**Exit criteria:** both mobile builds launch, create stable device
identities, and restore local metadata/committed objects after restart.

### Milestone 2 — Discovery, pairing and authenticated connections

- Implement mDNS discovery with platform permission handling.
- Add QR-based pairing and a manual diagnostic connection fallback.
- Bind public keys to paired device identities.
- Establish authenticated foreground TCP connections.

**Exit criteria:** Android and iOS devices discover, pair and reject
unpaired protected requests on a local Wi-Fi network.

### Milestone 3 — Image processing and reliable direct transfer

- Implement the image import/compression adapter.
- Handle supported JPEG/PNG/WebP inputs and the agreed HEIC behavior.
- Normalize orientation, strip GPS metadata, create thumbnails and
  compute content IDs.
- Implement length-prefixed framing, chunk ACKs, resume and hash checks.

**Exit criteria:** an image transfers between Android and iOS, is
committed atomically, and passes ciphertext/plaintext integrity checks.

### Milestone 4 — Two-device distributed storage

- Implement destination-side atomic storage reservation.
- Implement deterministic peer eligibility and scoring.
- Replicate encrypted objects to two distinct devices.
- Persist upload state and recover interrupted jobs.
- Keep AI placement out of the upload critical path.

**Exit criteria:** a normal image reaches two verified device replicas,
or remains visibly `pending`/`under_replicated` if a second device is
not available. No false success is shown.

### Milestone 5 — Shared manifest, gallery and retrieval

- Implement versioned manifests, tombstones and deterministic
  reconciliation.
- Display gallery metadata independently from original image bytes.
- Implement content-addressed replica lookup and foreground retrieval.
- Retry another online replica after a host failure.

**Exit criteria:** an authorized viewer retrieves an image from a
replica while the uploader is offline, provided the serving peer is
active and the viewer has a valid authorization grant/key.

### Milestone 6 — Access control and security hardening

- Implement owner-signed, device-bound access grants.
- Implement wrapped per-image keys and authenticated key delivery.
- Ensure storage-only peers cannot decrypt stored objects.
- Implement grant revocation and clearly document offline revocation
  limitations.
- Test tampering, unauthorized access, key-storage failures and
  sensitive-data leakage.

**Exit criteria:** unauthorized devices cannot retrieve/decrypt
protected content; authorized devices can; storage-only peers cannot
view the image.

### Milestone 7 — Resilience, optional intelligence and demo polish

- Implement reconnect reconciliation and basic under-replication
  repair.
- Add clear stored/online/unavailable replica indicators.
- Benchmark deterministic placement; optionally evaluate an LLM ranker
  behind a feature flag with deterministic fallback.
- Add the optional third replica policy for important images only when
  three eligible devices are available.
- Profile memory, battery, transfer speed and large-image behavior.

**Exit criteria:** the complete foreground-first demo works reliably on
Android and iOS, with clear behavior for unavailable peers and
under-replicated images.

------------------------------------------------------------------------

## 12. Hackathon demonstration scenario

Use three physical phones if available:

-   Android Phone A --- uploader.
-   Android Phone B --- storage peer and viewer.
-   iOS Phone C --- storage peer and viewer.

Demonstration:

1.  Keep HiveNet open on all three devices and pair them on the same Wi-Fi network.
2.  Upload a normal image from Phone A.
3.  Show that it is compressed locally before transfer.
4.  Show the router selecting two distinct storage devices.
5.  Confirm that both replicas are committed and verified as encrypted objects.
6.  Demonstrate that the storage-only peers cannot decrypt or view the image without an explicit view grant.
7.  Grant Phone B view permission from Phone A, then open the permitted gallery entry on Phone B.
8.  Select the image; show the access check, wrapped-key delivery and content-addressed request.
9.  Retrieve the encrypted image from a storage peer, verify its hashes, decrypt locally and display it.
10. Close or disconnect Phone A.
11. Keep the selected replica host active in the foreground; request the image from another authorized phone and demonstrate retrieval from that remaining verified replica.
12. Revoke Phone B's grant and show that a subsequent request is denied (explain that previously downloaded copies cannot be remotely erased).
13. If three eligible devices are available, upload an important image and demonstrate the optional three-replica policy. Otherwise show it as under-replicated.
14. Attempt access from an unpaired device and show that access is denied.

------------------------------------------------------------------------

## 13. Risk register and locked decisions

The following decisions are part of the MVP scope. They are not open
recommendations. Any change should be made deliberately because it can
affect availability, security or the demo promise.

| Risk | Priority | Decision / mitigation | MVP consequence |
|---|---|---|---|
| iOS suspends the app and stops peer serving | Critical | Foreground-first peer service on both platforms. A backgrounded/suspended peer becomes unavailable after its heartbeat lease expires. | No promise of always-on storage; demo peers stay active. |
| Android background execution varies by OS/vendor | High | Do not make Android background service a requirement for cross-platform success. A user-visible foreground service may be evaluated separately. | Foreground operation is the guaranteed mode. |
| mDNS/local-network permission denied or filtered | High | Implement clear permission onboarding, permission-denied states, network diagnostics and manual IP/port fallback. | Discovery can be retried; pairing/authentication is still mandatory. |
| Wi-Fi client isolation or different subnets | High | Require same reachable LAN for MVP; detect failed peer reachability and explain network isolation. | No internet relay/NAT traversal in MVP. |
| Compression plugin or HEIC decoder differs by platform | Critical | Run physical-device compatibility spike first; hide implementation behind a Dart adapter; support tested HEIC conversion or actionable rejection. | No full upload work until Android+iOS import passes. |
| iOS app sandbox, OS cleanup or uninstall removes replicas | High | Store committed replicas in durable app-support storage, not cache; quota and integrity checks; communicate that app uninstall/data clearing removes contributed storage. | Replicas are best-effort edge storage, not permanent backup. |
| Key loss or insecure key storage | Critical | Use Android Keystore/iOS Keychain through maintained libraries; no custom cryptography; test restore/restart and identity recovery. | Secure sharing is blocked until key lifecycle tests pass. |
| Owner is offline during access validation | High | Owner issues signed, device-bound grants; peers validate cached grants locally. Use bounded grant validity and sync revocations when owner reconnects. | Revocation may not take effect on an isolated/offline peer until grant expiry or revocation sync. |
| Revocation after recipient already decrypted/copied image | High | Explain irreversible plaintext-copy limitation; revocation blocks future compliant access, not copies already obtained. | Never promise remote erasure. |
| Distributed metadata conflicts or stale replica records | High | Owner-authoritative signed manifest events, monotonic per-owner versions, tombstones and deterministic reconciliation. | No CRDT/consensus in MVP. |
| Concurrent uploads exhaust storage | High | Atomic destination reservations, quota, safety margin and destination-side capacity recheck before commit. | Reject or defer uploads safely. |
| Partial/corrupt replica counted as valid | Critical | Temporary files, chunk ACKs, final ciphertext hash verification and atomic commit; only committed+verified objects count. | Upload success requires verified replica count. |
| All replicas offline | High | Preserve manifest metadata and show `temporarily_unavailable`; retry when peers return. | Availability is conditional on at least one online replica. |
| LLM placement is slow, unavailable or unsafe | Medium | Deterministic eligibility and scoring are the default; LLM only ranks eligible peers behind a feature flag. | LLM is optional and cannot block upload. |
| Too few devices for replication factor | High | MVP targets two copies; third copy is optional for important images when three eligible devices exist. | Show `under_replicated`, never false success. |
| Content ID leaks image equality | Medium | Do not broadcast content IDs in unauthenticated discovery; IDs are not access tokens; require authenticated requests and permission checks. | Content IDs identify content, not authorization. |
| Battery, heat and memory pressure during processing/transfers | Medium | Foreground operations, bounded concurrency, streaming/chunked I/O, image dimension limits and profiling on mid-range phones. | Pause/cancel safely; avoid large in-memory copies. |
| Frontend and peer protocol drift | High | Freeze protocol version, message schemas, enums, error codes and state transitions before parallel feature work; maintain shared contract fixtures. | Contract tests are required at each milestone. |

### 13.1 Upload and replica state machine

Persist upload state so app suspension, process death or network loss
cannot create false success:

`CREATED → RESERVING → TRANSFERRING → VERIFYING → COMMITTING → REPLICATING → COMPLETED`

Failure or interruption transitions to `RETRY_PENDING`, `FAILED` or
`UNDER_REPLICATED`. A destination replica counts only after atomic
commit and successful integrity verification. Retry operations must be
idempotent by `jobId`/`transferId` and `contentId`.

### 13.2 Replica state model

Use separate durable and reachability states:

- `stored_verified`: committed object exists and last integrity check
  passed.
- `online_servable`: peer is currently reachable and its peer service
  is active.
- `temporarily_unavailable`: object is believed stored, but peer is
  offline, suspended or unreachable.
- `missing`: peer confirms object is absent or a repair check detects
  loss.
- `corrupted`: integrity verification failed.

Do not collapse “stored” and “online” into one status. A device can
hold a valid replica while being unavailable to serve it.

### 13.3 Authorization while the owner is offline

The owner is authoritative for grants. To support retrieval from a
replica while the uploader is offline, the owner issues a signed grant
bound to the recipient device identity, content ID, permitted actions,
key version and validity window. Storage peers validate the signature
and expiry using the owner's public key and the latest revocation state
they possess. Revocation updates propagate as signed manifest events.

If a storage peer is disconnected from the owner and has not received a
revocation, it may accept a still-valid cached grant until its expiry.
This bounded stale-authorization window is an explicit MVP trade-off;
shorter validity improves revocation responsiveness but increases the
need to refresh grants. The UI must not claim instantaneous revocation
on disconnected peers.

### 13.4 Scope cuts if the schedule slips

Cut features in this order; do not cut security or integrity checks:

1. Remove LLM placement and use deterministic scoring only.
2. Defer three-replica/important-image behavior; retain two verified
   copies as the MVP target.
3. Defer automatic replica repair; retain manual retry/reconnect repair.
4. Defer background serving experiments; keep foreground-first behavior.
5. Defer advanced conflict resolution; retain owner-authoritative
   versioned manifests and tombstones.

Never cut authenticated pairing, per-image encryption, authorization
checks, hash verification, atomic commit or truthful availability
states.

------------------------------------------------------------------------

## 14. Implementation decisions and remaining validation

The following product decisions are locked for the MVP:

1. **Platforms:** Flutter Android and iOS only. No Windows or desktop
   target.
2. **Network scope:** same reachable local Wi-Fi/LAN only; no internet
   relay, NAT traversal or cloud image storage.
3. **Availability:** foreground-first on both platforms. A backgrounded
   or suspended peer is not considered online/servable.
4. **Replication:** two verified copies are the normal MVP target.
   Three copies are an optional policy for important images when three
   eligible devices are online.
5. **Routing:** deterministic local eligibility/scoring is mandatory;
   LLM ranking is optional and cannot block uploads.
6. **Security:** authenticated pairing, per-image encryption,
   device-bound wrapped keys and signed access grants are required
   before protected sharing is enabled.
7. **Metadata:** owner-authoritative versioned manifests and tombstones;
   no CRDT or consensus protocol in the MVP.
8. **Storage:** durable app-support storage with quota and integrity
   verification; app uninstall/data clearing can remove a replica.
9. **Transfer:** framed TCP, chunk acknowledgements, resumable jobs,
   ciphertext hash verification and atomic commit.

The following are engineering validation tasks, not product-scope
questions:

- Confirm the exact `flutter_image_compress` version and Android/iOS
  codec support. If it cannot satisfy both platforms, implement a
  platform-specific adapter or select a tested alternative.
- Prove HEIC import/conversion from iOS Photos on physical devices; if
  the selected path cannot support it in the MVP, reject HEIC with a
  clear user-facing explanation.
- Verify `bonsoir` (or the chosen mDNS package) against iOS Bonjour
  declarations and Android multicast behavior on physical devices.
- Select maintained cryptographic/key-storage packages and document
  their algorithms, formats and lifecycle behavior. Do not implement
  cryptographic primitives manually.
- Tune heartbeat/lease duration, chunk size, concurrency and storage
  quota using real Android/iOS devices and Wi-Fi conditions.
- Define the grant validity window and test the offline-revocation
  trade-off described in Section 13.3.

------------------------------------------------------------------------

## 15. Definition of done

The HiveNet MVP is complete when:

-   Android and iOS builds run.
-   Android and iOS devices discover and pair over the same reachable Wi-Fi network.
-   Images are compressed on the sender before transfer.
-   The image is identified by a content ID.
-   The deterministic router selects eligible peers and stores verified replicas; optional AI ranking never blocks the operation.
-   Normal images reach two verified replicas or are clearly marked
    under-replicated. Important-image three-copy replication is an
    optional enhancement when three eligible devices are available.
-   Gallery metadata is synchronized independently of original image
    bytes.
-   A user can request an image by content ID and retrieve it from an
    authorized peer.
-   Retrieval can use another replica when the uploader is offline.
-   Same-Wi-Fi membership and storage placement do not grant view permission.
-   Storage-only peers cannot decrypt images they store.
-   Unauthorized peers cannot retrieve protected image content or thumbnails.
-   Authorized key delivery is bound to paired device identities, and future requests are denied after revocation.
-   Interrupted transfers can resume or fail safely without creating
    false replicas. A peer is marked unavailable when its app is suspended,
    backgrounded beyond the supported lease, disconnected or terminated.
-   The application does not rely on a cloud bucket or centralized image
    database.

**Platform principle:** HiveNet is foreground-first on Android and iOS; a stored replica is not necessarily an online replica.

**Product principle:** HiveNet's gallery is a shared index, not a public
file dump. An image is discovered through its manifest, requested by its
content ID, authorized by its access policy and served by an available
peer holding a verified replica.
