import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/place_content_model.dart';
import '../models/beacon_model.dart';
import '../models/floor_model.dart';

/// SQLite singleton — the app's local offline cache.
///
/// DB version history:
///   v1 — initial schema (beacon keyed by UUID)
///   v2 — beacon keyed by MAC address (all 15 beacons share same UUID)
///   v3 — forced cache flush for imageUrl/videoUrl updates
///   v4 — refactored place_id to id
///   v5 — beacon: x/y → floor_id/pixel_x/pixel_y; new floors table
class DatabaseService {
  static DatabaseService? _instance;
  static Database? _database;

  DatabaseService._();

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'tour_guide_cache.db');
    return openDatabase(
      path,
      version: 5, // v5: floor_plan integration
      onCreate:  _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Outdoor place rich content
    await db.execute('''
      CREATE TABLE place_content (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL,
        description TEXT NOT NULL,
        history     TEXT NOT NULL,
        significance TEXT NOT NULL,
        image_url   TEXT NOT NULL,
        video_url   TEXT NOT NULL,
        language    TEXT NOT NULL,
        cached_at   TEXT NOT NULL
      )
    ''');

    // Indoor beacon content — keyed by MAC address.
    // v5: replaced x/y (metres) with floor_id + pixel_x/pixel_y.
    await db.execute('''
      CREATE TABLE beacon_content (
        mac_address TEXT PRIMARY KEY,
        uuid        TEXT NOT NULL,
        object_name TEXT NOT NULL,
        description TEXT NOT NULL,
        history     TEXT NOT NULL,
        image_url   TEXT NOT NULL,
        video_url   TEXT NOT NULL,
        floor_id    TEXT NOT NULL DEFAULT '',
        pixel_x     REAL NOT NULL DEFAULT 0.0,
        pixel_y     REAL NOT NULL DEFAULT 0.0,
        cached_at   TEXT NOT NULL
      )
    ''');

    // Floor plan metadata — keyed by Firestore document ID.
    await db.execute('''
      CREATE TABLE floors (
        id                  TEXT PRIMARY KEY,
        floor_number        INTEGER NOT NULL,
        display_name        TEXT NOT NULL,
        image_url           TEXT NOT NULL,
        image_width_pixels  REAL NOT NULL,
        image_height_pixels REAL NOT NULL,
        cached_at           TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 5) {
      // Drop and recreate all — simplest safe migration path.
      await db.execute('DROP TABLE IF EXISTS place_content');
      await db.execute('DROP TABLE IF EXISTS beacon_content');
      await db.execute('DROP TABLE IF EXISTS floors');
      await _onCreate(db, newVersion);
    }
  }

  // ── Place content CRUD ────────────────────────────────────────────────────

  Future<PlaceContent?> getPlaceContent(String id) async {
    final db = await database;
    final rows = await db.query('place_content',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return PlaceContent.fromSqlite(rows.first);
  }

  Future<void> savePlaceContent(PlaceContent content) async {
    final db = await database;
    await db.insert('place_content', content.toSqlite(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Beacon content CRUD ───────────────────────────────────────────────────

  Future<BeaconContent?> getBeaconContent(String macAddress) async {
    final db = await database;
    final rows = await db.query('beacon_content',
        where: 'mac_address = ?',
        whereArgs: [macAddress.toUpperCase()],
        limit: 1);
    if (rows.isEmpty) return null;
    return BeaconContent.fromSqlite(rows.first);
  }

  Future<void> saveBeaconContent(BeaconContent content) async {
    final db = await database;
    await db.insert('beacon_content', content.toSqlite(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Floor config CRUD ─────────────────────────────────────────────────────

  Future<List<FloorConfig>> getAllFloors() async {
    final db = await database;
    final rows = await db.query('floors', orderBy: 'floor_number ASC');
    return rows.map(FloorConfig.fromSqlite).toList();
  }

  Future<void> saveFloor(FloorConfig floor) async {
    final db = await database;
    await db.insert('floors', floor.toSqlite(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Returns all beacons belonging to the given floorId from the local cache.
  Future<List<BeaconContent>> getBeaconsForFloor(String floorId) async {
    final db = await database;
    final rows = await db.query('beacon_content',
        where: 'floor_id = ?', whereArgs: [floorId]);
    return rows.map(BeaconContent.fromSqlite).toList();
  }

  // ── Cache management ──────────────────────────────────────────────────────

  Future<void> clearAllCache() async {
    final db = await database;
    await db.delete('place_content');
    await db.delete('beacon_content');
    await db.delete('floors');
  }
}
