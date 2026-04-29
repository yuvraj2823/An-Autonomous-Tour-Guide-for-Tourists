import 'package:geolocator/geolocator.dart';

/// A place of interest fetched from the Firestore `places` collection.
///
/// Since we no longer use the Google Places API, the [placeId] is a
/// custom unique string set by the admin (e.g. "jama_masjid_01"),
/// not a Google ChIJ... ID.
class Place {
  final String id;
  final String name;
  final String category;   // e.g. "Museum", "Mosque", "Park"
  final String vicinity;   // short address / area description
  final double lat;
  final double lng;
  final double? rating;
  final double distanceMetres;

  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.vicinity,
    required this.lat,
    required this.lng,
    this.rating,
    required this.distanceMetres,
  });

  /// Build a [Place] from a Firestore document map, computing distance from
  /// the user's current GPS coordinates.
  factory Place.fromFirestore(
    String id,
    Map<String, dynamic> data,
    double userLat,
    double userLng,
  ) {
    final double placeLat = (data['lat'] as num).toDouble();
    final double placeLng = (data['lng'] as num).toDouble();
    final double distance = Geolocator.distanceBetween(
      userLat, userLng, placeLat, placeLng,
    );
    return Place(
      id:              id,
      name:            data['name']     as String? ?? 'Unknown Place',
      category:        data['category'] as String? ?? 'Point of Interest',
      vicinity:        data['vicinity'] as String? ?? '',
      lat:             placeLat,
      lng:             placeLng,
      rating:          (data['rating']  as num?)?.toDouble(),
      distanceMetres:  distance,
    );
  }

  /// Human-readable distance string ("450m" or "1.2km").
  String get formattedDistance {
    if (distanceMetres < 1000) return '${distanceMetres.round()}m';
    return '${(distanceMetres / 1000).toStringAsFixed(1)}km';
  }

  /// Deep-link URL that opens Google Maps turn-by-turn directions to this place.
  String get directionsUrl =>
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
}
