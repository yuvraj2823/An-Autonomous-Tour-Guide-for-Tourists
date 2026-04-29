import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/place_content_model.dart';
import '../models/beacon_model.dart';
import '../models/floor_model.dart';
import '../models/place_model.dart';

/// All Firestore read operations for the app.
///
/// The UI never calls Firestore directly — it goes through [ContentService],
/// which calls this class after checking the SQLite cache.
class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  // ── Outdoor places ───────────────────────────────────────────────────────

  /// Fetch all documents from the `places` collection.
  static Future<List<Map<String, dynamic>>> getAllPlaceDocuments() async {
    final snapshot = await _db.collection('places').get();
    return snapshot.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  /// Fetch rich content for a single place by its native document [id].
  static Future<PlaceContent?> getPlaceContent(String id) async {
    final docSnapshot = await _db.collection('places').doc(id).get();
    if (docSnapshot.exists) {
      final data = docSnapshot.data()!;
      return PlaceContent.fromFirestore(docSnapshot.id, data);
    }
    return null;
  }

  // ── Indoor beacons ────────────────────────────────────────────────────────

  /// Fetch content for a single indoor beacon by its [mac] address.
  static Future<BeaconContent?> getBeaconContent(String mac) async {
    final query = await _db
        .collection('beacons')
        .where('macAddress', isEqualTo: mac.toUpperCase())
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    return BeaconContent.fromFirestore(query.docs.first.data());
  }

  /// Fetch ALL beacon documents (used for pre-caching on indoor screen open).
  static Future<List<BeaconContent>> getAllBeacons() async {
    final snapshot = await _db.collection('beacons').get();
    return snapshot.docs
        .map((d) => BeaconContent.fromFirestore(d.data()))
        .toList();
  }

  /// Fetch beacons that belong to a specific floor.
  static Future<List<BeaconContent>> getBeaconsForFloor(
      String floorId) async {
    final query = await _db
        .collection('beacons')
        .where('floorId', isEqualTo: floorId)
        .get();
    return query.docs
        .map((d) => BeaconContent.fromFirestore(d.data()))
        .toList();
  }

  // ── Floor plans ───────────────────────────────────────────────────────────

  /// Fetch all floor config documents, sorted by floorNumber client-side.
  static Future<List<FloorConfig>> getAllFloors() async {
    final snapshot = await _db.collection('floors').get();
    final floors = snapshot.docs
        .map((d) => FloorConfig.fromFirestore(d.id, d.data()))
        .toList();
    floors.sort((a, b) => a.floorNumber.compareTo(b.floorNumber));
    return floors;
  }
}

/// Extension to build a [Place] list from raw Firestore documents.
extension PlaceListBuilder on List<Map<String, dynamic>> {
  List<Place> toPlaceList(double userLat, double userLng) {
    return map((data) =>
        Place.fromFirestore(data['id'] as String, data, userLat, userLng))
        .toList();
  }
}
