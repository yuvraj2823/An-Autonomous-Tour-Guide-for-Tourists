import 'dart:ui' show Size;

/// Represents a single physical floor fetched from the Firestore `floors`
/// collection and cached in SQLite.
///
/// Firestore document fields:
///   floorNumber         — int   (ordering, e.g. 3)
///   displayName         — String (e.g. "3rd Floor")
///   imageUrl            — String (Firebase Storage download URL for the PNG)
///   imageWidthPixels    — double (natural pixel width  of the PNG, e.g. 1280)
///   imageHeightPixels   — double (natural pixel height of the PNG, e.g. 1707)
class FloorConfig {
  /// Native Firestore document ID — used as the primary key everywhere.
  final String id;

  /// Floor level number (1 = ground floor).  Used for ordering and display.
  final int floorNumber;

  /// Human-readable name shown in the floor selector tab, e.g. "3rd Floor".
  final String displayName;

  /// Firebase Storage HTTPS download URL for the floor-plan PNG.
  final String imageUrl;

  /// Natural pixel width  of the floor-plan PNG file.
  final double imageWidthPixels;

  /// Natural pixel height of the floor-plan PNG file.
  final double imageHeightPixels;

  const FloorConfig({
    required this.id,
    required this.floorNumber,
    required this.displayName,
    required this.imageUrl,
    required this.imageWidthPixels,
    required this.imageHeightPixels,
  });

  // ── From Firestore ─────────────────────────────────────────────────────────

  factory FloorConfig.fromFirestore(String docId, Map<String, dynamic> data) =>
      FloorConfig(
        id:                docId,
        floorNumber:       (data['floorNumber']       as num?)?.toInt()    ?? 0,
        displayName:       data['displayName']        as String? ?? 'Floor',
        imageUrl:          data['imageUrl']           as String? ?? '',
        imageWidthPixels:  (data['imageWidthPixels']  as num?)?.toDouble() ?? 1280,
        imageHeightPixels: (data['imageHeightPixels'] as num?)?.toDouble() ?? 1707,
      );

  // ── To / from SQLite ───────────────────────────────────────────────────────

  Map<String, dynamic> toSqlite() => {
        'id':                  id,
        'floor_number':        floorNumber,
        'display_name':        displayName,
        'image_url':           imageUrl,
        'image_width_pixels':  imageWidthPixels,
        'image_height_pixels': imageHeightPixels,
        'cached_at':           DateTime.now().toIso8601String(),
      };

  factory FloorConfig.fromSqlite(Map<String, dynamic> row) => FloorConfig(
        id:                row['id']                 as String,
        floorNumber:       row['floor_number']        as int,
        displayName:       row['display_name']        as String,
        imageUrl:          row['image_url']           as String,
        imageWidthPixels:  (row['image_width_pixels'] as num).toDouble(),
        imageHeightPixels: (row['image_height_pixels'] as num).toDouble(),
      );

  // ── Coordinate helpers ─────────────────────────────────────────────────────

  /// Convert a beacon's stored (pixelX, pixelY) — relative to the natural image
  /// size — into on-screen coordinates given the widget's rendered [displaySize].
  ///
  /// Usage inside CustomPainter.paint():
  ///   final screenPos = floorConfig.pixelToScreen(px, py, renderedSize);
  (double, double) pixelToScreen(
      double px, double py, Size displaySize) {
    return (
      px / imageWidthPixels  * displaySize.width,
      py / imageHeightPixels * displaySize.height,
    );
  }

  bool get isStale => false; // floors rarely change — no TTL for now
}
