import 'dart:ui';

/// VenueConfig — ARCHIVED in v5 (floor-plan integration).
///
/// All venue data (beacon positions, room names, floor dimensions) has been
/// moved to Firestore. Floor plan images are served from Firebase Storage.
///
/// This file is kept only to avoid breaking any stray references during
/// migration. It can be deleted once those references are cleaned up.
@Deprecated('Use Firestore-driven FloorConfig and beacon pixelX/pixelY instead.')
class VenueConfig {
  // Physical dimensions retained for reference only.
  static const double venueWidthMetres  = 20.0;
  static const double venueHeightMetres = 12.5;
  static const double svgWidth   = 800.0;
  static const double svgHeight  = 500.0;
  static const double svgMargin  = 20.0;
  static const double pxPerMetreX = (svgWidth  - 2 * svgMargin) / venueWidthMetres;
  static const double pxPerMetreY = (svgHeight - 2 * svgMargin) / venueHeightMetres;

  // Empty maps — data lives in Firestore.
  static const Map<String, Offset>  beaconPositions = {};
  static const Map<String, String>  beaconNames     = {};

  static Offset realToSvg(Offset realPos) => Offset(
        svgMargin + realPos.dx * pxPerMetreX,
        svgHeight - svgMargin - realPos.dy * pxPerMetreY,
      );

  static String? getNearbyBeacon(Offset userRealPos,
          {double proximityThreshold = 4.0}) =>
      null;
}
