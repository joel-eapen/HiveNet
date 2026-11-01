import '../../shared/models/enums.dart';

/// Output encodings. The cross-platform choice is to be confirmed by the
/// Milestone 0 device spike (PRD FR-03, §10.4); do not ship platform-dependent
/// output differences.
enum OutputFormat { jpeg, webp }

/// Initial compression policy (PRD FR-03). Quality values are tuning targets,
/// not guaranteed size ratios.
class CompressionConfig {
  const CompressionConfig({
    this.normalQuality = 80,
    this.importantQuality = 90,
    this.normalMaxDimension = 2048,
    this.importantMaxDimension = 2560,
    this.thumbnailMinDimension = 320,
    this.thumbnailMaxDimension = 480,
    this.thumbnailQuality = 70,
    this.imageFormat = OutputFormat.jpeg,
    this.thumbnailFormat = OutputFormat.webp,
    this.stripGpsMetadata = true,
  });

  final int normalQuality;
  final int importantQuality;
  final int normalMaxDimension;
  final int importantMaxDimension;
  final int thumbnailMinDimension;
  final int thumbnailMaxDimension;

  /// "Tuned separately" in the PRD; placeholder until profiled.
  final int thumbnailQuality;
  final OutputFormat imageFormat;
  final OutputFormat thumbnailFormat;
  final bool stripGpsMetadata;

  int qualityFor(Importance importance) =>
      importance == Importance.important ? importantQuality : normalQuality;

  int maxDimensionFor(Importance importance) =>
      importance == Importance.important
          ? importantMaxDimension
          : normalMaxDimension;
}
