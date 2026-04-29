/// Content for an indoor beacon/exhibit, fetched from Firestore `beacons`
/// collection and cached in SQLite with a 24-hour TTL.
///
/// Identification change: since all 15 beacons share the same UUID, the
/// unique identifier is now [macAddress] ("AA:BB:CC:DD:EE:FF").
/// Firestore documents must have a "macAddress" field matching this format.
class BeaconContent {
  /// MAC address — unique identifier for this beacon ("AA:BB:CC:DD:EE:FF").
  final String macAddress;

  /// UUID is the same for all 15 beacons but kept for reference.
  final String uuid;

  final String objectName;
  final String description;
  final String history;
  final String imageUrl;
  final String videoUrl;
  /// Firestore `floors` document ID this beacon belongs to.
  final String floorId;
  /// Pixel X on the floor-plan image where this beacon/exhibit is located.
  final double pixelX;
  /// Pixel Y on the floor-plan image where this beacon/exhibit is located.
  final double pixelY;
  final DateTime cachedAt;

  const BeaconContent({
    required this.macAddress,
    required this.uuid,
    required this.objectName,
    required this.description,
    required this.history,
    required this.imageUrl,
    required this.videoUrl,
    required this.floorId,
    required this.pixelX,
    required this.pixelY,
    required this.cachedAt,
  });

  // ── From Firestore ──────────────────────────────────────────────────────
  factory BeaconContent.fromFirestore(Map<String, dynamic> data) =>
      BeaconContent(
        macAddress:  (data['macAddress'] as String? ?? '').toUpperCase(),
        uuid:        data['uuid']        as String? ?? '',
        objectName:  data['objectName']  as String? ?? '',
        description: data['description'] as String? ?? '',
        history:     data['history']     as String? ?? '',
        imageUrl:    data['imageUrl']    as String? ?? '',
        videoUrl:    data['videoUrl']    as String? ?? '',
        floorId:     data['floorId']     as String? ?? '',
        pixelX:      (data['pixelX']     as num?)?.toDouble() ?? 0.0,
        pixelY:      (data['pixelY']     as num?)?.toDouble() ?? 0.0,
        cachedAt:    DateTime.now(),
      );

  // ── To / from SQLite ────────────────────────────────────────────────────
  Map<String, dynamic> toSqlite() => {
    'mac_address': macAddress,
    'uuid':        uuid,
    'object_name': objectName,
    'description': description,
    'history':     history,
    'image_url':   imageUrl,
    'video_url':   videoUrl,
    'floor_id':    floorId,
    'pixel_x':     pixelX,
    'pixel_y':     pixelY,
    'cached_at':   cachedAt.toIso8601String(),
  };

  factory BeaconContent.fromSqlite(Map<String, dynamic> row) => BeaconContent(
    macAddress:  row['mac_address'] as String? ?? '',
    uuid:        row['uuid']        as String? ?? '',
    objectName:  row['object_name'] as String? ?? '',
    description: row['description'] as String? ?? '',
    history:     row['history']     as String? ?? '',
    imageUrl:    row['image_url']   as String? ?? '',
    videoUrl:    row['video_url']   as String? ?? '',
    floorId:     row['floor_id']    as String? ?? '',
    pixelX:      (row['pixel_x']    as num?)?.toDouble() ?? 0.0,
    pixelY:      (row['pixel_y']    as num?)?.toDouble() ?? 0.0,
    cachedAt:    DateTime.parse(row['cached_at'] as String),
  );

  /// Returns true if this cached record is older than 24 hours.
  bool get isStale => DateTime.now().difference(cachedAt).inHours > 24;
}
