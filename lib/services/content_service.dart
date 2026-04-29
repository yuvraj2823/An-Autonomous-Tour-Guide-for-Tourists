import '../models/place_content_model.dart';
import '../models/beacon_model.dart';
import '../models/floor_model.dart';
import 'database_service.dart';
import 'firestore_service.dart';

/// Cache-first content orchestrator.
///
/// The rule is always: check SQLite first. If fresh (< 24 hr), return it.
/// If missing or stale, fetch Firestore, save it, return it.
/// If network fails, return stale data rather than nothing.
class ContentService {
  // ── Outdoor place content ────────────────────────────────────────────────

  static Future<PlaceContent?> getPlaceContent(String id) async {
    final db = DatabaseService.instance;

    final cached = await db.getPlaceContent(id);
    if (cached != null && !cached.isStale) return cached;

    try {
      final fresh = await FirestoreService.getPlaceContent(id);
      if (fresh != null) {
        await db.savePlaceContent(fresh);
        return fresh;
      }
    } catch (_) {}

    return cached;
  }

  // ── Indoor beacon content ─────────────────────────────────────────────────

  static Future<BeaconContent?> getBeaconContent(String mac) async {
    final db = DatabaseService.instance;

    final cached = await db.getBeaconContent(mac.toUpperCase());
    if (cached != null && !cached.isStale) return cached;

    try {
      final fresh = await FirestoreService.getBeaconContent(mac);
      if (fresh != null) {
        await db.saveBeaconContent(fresh);
        return fresh;
      }
    } catch (_) {}

    return cached;
  }

  /// Pre-fetches ALL beacon content from Firestore and stores in SQLite.
  /// Called when the indoor screen opens.
  static Future<void> preCacheVenueBeacons() async {
    try {
      final beacons = await FirestoreService.getAllBeacons();
      final db = DatabaseService.instance;
      for (final beacon in beacons) {
        await db.saveBeaconContent(beacon);
      }
    } catch (_) {}
  }

  // ── Floor plan configs ────────────────────────────────────────────────────

  /// Returns all floors, preferring the SQLite cache.
  static Future<List<FloorConfig>> getFloorConfigs() async {
    final db = DatabaseService.instance;

    // 1. Check SQLite cache.
    final cached = await db.getAllFloors();
    if (cached.isNotEmpty) return cached;

    // 2. Fetch from Firestore and cache.
    try {
      final floors = await FirestoreService.getAllFloors();
      for (final floor in floors) {
        await db.saveFloor(floor);
      }
      return floors;
    } catch (_) {
      return cached; // stale is better than nothing
    }
  }

  /// Returns all beacons belonging to [floorId].
  ///
  /// Strategy: always fetch ALL beacons (comprehensive) then filter in Dart.
  /// This is more reliable than a Firestore `.where('floorId', ...)` query
  /// which may miss documents if floorId was added inconsistently.
  static Future<List<BeaconContent>> getBeaconsForFloor(
      String floorId) async {
    final db = DatabaseService.instance;
    final database = await db.database;

    // 1. Try full SQLite beacon cache first (populated by preCacheVenueBeacons).
    final allRows = await database.query('beacon_content');
    if (allRows.isNotEmpty) {
      final all      = allRows.map(BeaconContent.fromSqlite).toList();
      final filtered = all.where((b) => b.floorId == floorId).toList();
      // Only return if we found at least one beacon for this floor.
      if (filtered.isNotEmpty) return filtered;
    }

    // 2. SQLite is empty or has no match → fetch ALL beacons from Firestore,
    //    cache them, then filter.
    try {
      final beacons = await FirestoreService.getAllBeacons();
      for (final b in beacons) {
        await db.saveBeaconContent(b);
      }
      return beacons.where((b) => b.floorId == floorId).toList();
    } catch (_) {
      // Last resort: filtered SQLite query (might have partial data).
      return db.getBeaconsForFloor(floorId);
    }
  }


  /// Force-refresh floors from Firestore (ignores SQLite cache).
  static Future<List<FloorConfig>> refreshFloorConfigs() async {
    try {
      final floors = await FirestoreService.getAllFloors();
      final db = DatabaseService.instance;
      for (final floor in floors) {
        await db.saveFloor(floor);
      }
      return floors;
    } catch (_) {
      return DatabaseService.instance.getAllFloors();
    }
  }

  /// Force-fetches ALL beacons from Firestore and overwrites the SQLite cache.
  /// Used by the background sync timer to keep beacon positions/names current.
  static Future<void> forceRefreshBeacons() async {
    try {
      final beacons = await FirestoreService.getAllBeacons();
      final db = DatabaseService.instance;
      for (final b in beacons) {
        await db.saveBeaconContent(b);
      }
    } catch (_) {}
  }
}
