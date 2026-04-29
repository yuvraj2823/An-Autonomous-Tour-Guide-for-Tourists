/// Rich content for a single outdoor place, stored in Firestore `places`
/// collection and cached locally in SQLite with a 24-hour TTL.
class PlaceContent {
  final String id;
  final String name;
  final String description;
  final String history;
  final String significance;
  final String imageUrl;
  final String videoUrl;
  final String language;
  final DateTime cachedAt;

  const PlaceContent({
    required this.id,
    required this.name,
    required this.description,
    required this.history,
    required this.significance,
    required this.imageUrl,
    required this.videoUrl,
    required this.language,
    required this.cachedAt,
  });

  // ── From Firestore ───────────────────────────────────────────────────────
  factory PlaceContent.fromFirestore(String id, Map<String, dynamic> data) => PlaceContent(
    id:           id,
    name:         data['name']         as String? ?? '',
    description:  data['description']  as String? ?? '',
    history:      data['history']      as String? ?? '',
    significance: data['significance'] as String? ?? '',
    imageUrl:     data['imageUrl']     as String? ?? '',
    videoUrl:     data['videoUrl']     as String? ?? '',
    language:     data['language']     as String? ?? 'en',
    cachedAt:     DateTime.now(),
  );

  // ── To / from SQLite ────────────────────────────────────────────────────
  Map<String, dynamic> toSqlite() => {
    'id':          id,
    'name':        name,
    'description': description,
    'history':     history,
    'significance': significance,
    'image_url':   imageUrl,
    'video_url':   videoUrl,
    'language':    language,
    'cached_at':   cachedAt.toIso8601String(),
  };

  factory PlaceContent.fromSqlite(Map<String, dynamic> row) => PlaceContent(
    id:           row['id']          as String? ?? '',
    name:         row['name']        as String? ?? '',
    description:  row['description'] as String? ?? '',
    history:      row['history']     as String? ?? '',
    significance: row['significance'] as String? ?? '',
    imageUrl:     row['image_url']   as String? ?? '',
    videoUrl:     row['video_url']   as String? ?? '',
    language:     row['language']    as String? ?? 'en',
    cachedAt:     DateTime.parse(row['cached_at'] as String),
  );

  /// Returns true if this cached record is older than 24 hours.
  bool get isStale => DateTime.now().difference(cachedAt).inHours > 24;
}
