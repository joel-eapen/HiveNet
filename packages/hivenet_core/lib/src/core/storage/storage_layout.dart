/// On-disk layout from PRD FR-10, rooted at the platform's
/// application-support directory (never a cache directory).
///
/// ```text
/// HiveNet/
///   objects/<first 2 chars>/<contentId>.enc
///   thumbnails/<contentId>.webp
///   cache/retrieved/
///   temporary/incomplete-transfers/
///   database/hivenet.sqlite
/// ```
class StorageLayout {
  const StorageLayout(this.rootPath);

  /// Absolute path of the `HiveNet` directory.
  final String rootPath;

  static const objectsDirName = 'objects';
  static const thumbnailsDirName = 'thumbnails';
  static const cacheDirName = 'cache';
  static const retrievedCacheDirName = 'retrieved';
  static const temporaryDirName = 'temporary';
  static const incompleteTransfersDirName = 'incomplete-transfers';
  static const outgoingDirName = 'outgoing';
  static const databaseDirName = 'database';
  static const databaseFileName = 'hivenet.sqlite';

  String get objectsDir => '$rootPath/$objectsDirName';
  String get thumbnailsDir => '$rootPath/$thumbnailsDirName';
  String get retrievedCacheDir =>
      '$rootPath/$cacheDirName/$retrievedCacheDirName';
  String get incompleteTransfersDir =>
      '$rootPath/$temporaryDirName/$incompleteTransfersDirName';
  /// Encrypted objects this device is uploading or has uploaded.
  String get outgoingDir => '$rootPath/$temporaryDirName/$outgoingDirName';
  String get databaseDir => '$rootPath/$databaseDirName';
  String get databasePath => '$databaseDir/$databaseFileName';

  /// Every directory that must exist before the node is advertised as ready.
  List<String> get allDirectories => [
        objectsDir,
        thumbnailsDir,
        retrievedCacheDir,
        incompleteTransfersDir,
        outgoingDir,
        databaseDir,
      ];

  /// Committed encrypted object. Fan-out uses the first two characters.
  String objectPath(String contentId) {
    _checkContentId(contentId);
    return '$objectsDir/${contentId.substring(0, 2)}/$contentId.enc';
  }

  String thumbnailPath(String contentId) {
    _checkContentId(contentId);
    return '$thumbnailsDir/$contentId.webp';
  }

  /// The encrypted object being uploaded for [contentId].
  String outgoingPath(String contentId) {
    _checkContentId(contentId);
    return '$outgoingDir/$contentId.enc';
  }

  /// Partial transfer data. Never counted as a valid replica.
  String incompleteTransferPath(String transferId) {
    _checkSafeSegment(transferId);
    return '$incompleteTransfersDir/$transferId.part';
  }

  // IDs come from untrusted peers; reject anything that could escape the
  // storage root.
  void _checkContentId(String id) {
    if (id.length < 2) throw ArgumentError.value(id, 'contentId', 'too short');
    _checkSafeSegment(id);
  }

  void _checkSafeSegment(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, 'id', 'contains unsafe characters');
    }
  }
}
