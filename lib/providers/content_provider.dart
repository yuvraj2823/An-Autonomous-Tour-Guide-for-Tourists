import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/place_content_model.dart';
import '../models/beacon_model.dart';
import '../models/place_model.dart';
import '../models/ble_beacon_model.dart';
import '../services/content_service.dart';
import '../services/ai_service.dart';
import 'language_provider.dart';

// ── Raw Firestore/SQLite content ───────────────────────────────────────────

/// Firestore/SQLite content for an outdoor place (cache-first).
final placeContentProvider =
    FutureProvider.family<PlaceContent?, String>((ref, id) async {
  return ContentService.getPlaceContent(id);
});

/// Firestore/SQLite content for an indoor beacon (cache-first, keyed by MAC).
final beaconContentProvider =
    FutureProvider.family<BeaconContent?, String>((ref, mac) async {
  return ContentService.getBeaconContent(mac);
});

// ── Groq LLM narratives ────────────────────────────────────────────────────

/// LLM-generated narrative for an outdoor place.
///
/// Re-generates when [languageProvider] changes — let the user switch
/// language and instantly get a new narrative in that language.
final llmPlaceProvider =
    FutureProvider.family<String, Place>((ref, place) async {
  final content  = await ref.watch(placeContentProvider(place.id).future);
  final language = ref.watch(languageProvider).language;
  
  return AiService.generatePlaceNarrative(
    content?.name.isNotEmpty == true ? content!.name : place.name,
    content?.description ?? '',
    content?.history ?? '',
    content?.significance ?? '',
    language: language,
    isDeepDive: false,
  );
});

/// LLM-generated deep-dive narrative for an outdoor place (Know More mode).
final llmPlaceDeepDiveProvider =
    FutureProvider.family<String, Place>((ref, place) async {
  final content  = await ref.watch(placeContentProvider(place.id).future);
  final language = ref.watch(languageProvider).language;
  
  return AiService.generatePlaceNarrative(
    content?.name.isNotEmpty == true ? content!.name : place.name,
    content?.description ?? '',
    content?.history ?? '',
    content?.significance ?? '',
    language: language,
    isDeepDive: true,
  );
});

/// LLM-generated explanation for an indoor beacon/exhibit (keyed by MAC).
final llmBeaconProvider =
    FutureProvider.family<String, BleBeacon>((ref, beacon) async {
  final content  = await ref.watch(beaconContentProvider(beacon.macAddress).future);
  final language = ref.watch(languageProvider).language;
  
  return AiService.generateBeaconNarrative(
    content?.objectName.isNotEmpty == true ? content!.objectName : beacon.deviceName,
    content?.description ?? '',
    content?.history ?? '',
    language: language,
    isDeepDive: false,
  );
});

/// LLM-generated deep dive explanation for an indoor beacon (Know More mode).
final llmBeaconDeepDiveProvider =
    FutureProvider.family<String, BleBeacon>((ref, beacon) async {
  final content  = await ref.watch(beaconContentProvider(beacon.macAddress).future);
  final language = ref.watch(languageProvider).language;
  
  return AiService.generateBeaconNarrative(
    content?.objectName.isNotEmpty == true ? content!.objectName : beacon.deviceName,
    content?.description ?? '',
    content?.history ?? '',
    language: language,
    isDeepDive: true,
  );
});
