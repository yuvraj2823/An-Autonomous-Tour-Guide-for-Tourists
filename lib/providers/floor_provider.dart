import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/constants.dart';
import '../models/floor_model.dart';
import '../models/beacon_model.dart';
import '../services/content_service.dart';
import '../services/firestore_service.dart';
import '../services/database_service.dart';
import 'ble_provider.dart';

// ── Floor list provider ──────────────────────────────────────────────────────

/// All floor configs available in this venue (for the tab selector).
final floorsProvider = FutureProvider<List<FloorConfig>>((ref) async {
  return ContentService.getFloorConfigs();
});

// ── Beacons-by-floor provider ─────────────────────────────────────────────────

/// All beacon metadata (with pixelX/pixelY) for a given floor.
/// Used by the map painter to draw room markers.
final floorBeaconsProvider =
    FutureProvider.family<List<BeaconContent>, String>((ref, floorId) async {
  return ContentService.getBeaconsForFloor(floorId);
});

// ── Auto-detected current floor ───────────────────────────────────────────────

/// Tracks which floor the user is currently on, using RSSI-weighted scoring
/// with a confirmation buffer to prevent floor-switching noise.
///
/// Algorithm overview:
///  1. Single floor in venue  → auto-select immediately (shortcut, no voting).
///  2. Multiple floors        → every BLE scan event:
///       a. Score each floor = Σ (filteredRssi + 100) for all detected beacons on that floor.
///          This rewards both MORE beacons AND STRONGER RSSI simultaneously.
///       b. The floor with the highest score wins this round.
///       c. If the same floor wins [floorConfirmationThreshold] consecutive rounds
///          → commit the floor switch (prevents noise-driven flickering).
///       d. If a different floor wins even once → reset the streak counter.
///
/// The confirmation buffer mirrors the indoor/outdoor mode transition logic:
/// a momentary signal blip on another floor cannot flip the display.
class CurrentFloorNotifier extends StateNotifier<FloorConfig?> {
  final Ref _ref;

  // Populated once in _init(), then looked up synchronously on every BLE event.
  final Map<String, BeaconContent> _beaconMap = {}; // MAC.toUpperCase() → content
  final List<FloorConfig> _floors = [];
  bool _ready = false;

  // ── Confirmation buffer state ──────────────────────────────────────────────
  FloorConfig? _candidateFloor;        // floor that is currently leading
  int          _candidateWinCount = 0; // consecutive rounds it has won

  CurrentFloorNotifier(this._ref) : super(null) {
    _init();
    _ref.listen<BleState>(bleProvider, (_, next) {
      if (_ready) _onBleUpdate(next);
    });
  }

  // ── Eager data load ────────────────────────────────────────────────────────

  Future<void> _init() async {
    try {
      // 1. Load floor configs.
      final floors = await ContentService.getFloorConfigs();
      _floors
        ..clear()
        ..addAll(floors);
      debugPrint('[FloorDetect] Loaded ${_floors.length} floor(s): '
          '${_floors.map((f) => "${f.displayName}[${f.id}]").join(", ")}');

      // 2. SHORTCUT: Only one floor → select it immediately, no beacon vote needed.
      if (_floors.length == 1) {
        _ready = true;
        state = _floors.first;
        debugPrint('[FloorDetect] Single floor → auto-selected: ${state?.displayName}');
        return;
      }

      // 3. Multiple floors → load beacon content for floorId voting.
      final beacons = await _loadAllBeacons();
      _beaconMap.clear();
      for (final b in beacons) {
        if (b.macAddress.isNotEmpty) {
          _beaconMap[b.macAddress.toUpperCase()] = b;
        }
      }
      debugPrint('[FloorDetect] _beaconMap ready: ${_beaconMap.length} beacons');

      _ready = true;

      // 4. Run a detection pass on the current BLE state immediately.
      _onBleUpdate(_ref.read(bleProvider));
    } catch (e, stack) {
      debugPrint('[FloorDetect] _init error: $e\n$stack');
      _ready = true; // Don't block forever; fallback to manual selection.
    }
  }

  // ── Load all beacon content, SQLite-first ─────────────────────────────────

  Future<List<BeaconContent>> _loadAllBeacons() async {
    // Try SQLite first.
    final db = DatabaseService.instance;
    final database = await db.database;
    final rows = await database.query('beacon_content');
    if (rows.isNotEmpty) {
      final list = rows.map(BeaconContent.fromSqlite).toList();
      debugPrint('[FloorDetect] SQLite has ${list.length} beacon rows');
      return list;
    }

    // SQLite is empty → fetch from Firestore and cache.
    debugPrint('[FloorDetect] SQLite empty, fetching from Firestore…');
    try {
      final beacons = await FirestoreService.getAllBeacons();
      debugPrint('[FloorDetect] Firestore returned ${beacons.length} beacons');
      for (final b in beacons) {
        await db.saveBeaconContent(b);
      }
      return beacons;
    } catch (e) {
      debugPrint('[FloorDetect] Firestore fetch failed: $e');
      return [];
    }
  }

  // ── Floor detection (synchronous) ──────────────────────────────────────────

  void _onBleUpdate(BleState ble) {
    if (!_ready || _floors.isEmpty) return;

    // Single floor — already set in _init(), nothing to do here.
    if (_floors.length == 1) return;

    // Use ALL detected beacons (not just confirmed) for floor discrimination.
    // Floor detection is about which floor you're ON, not which exhibit is within 4m.
    // A wider net of all detected beacons gives a more robust floor vote.
    final allBeacons = ble.detectedBeacons.values.toList();
    if (allBeacons.isEmpty) return;

    // ── RSSI-weighted floor scoring ──────────────────────────────────────────
    //
    // Score per floor = Σ (filteredRssi + 100) for every beacon on that floor.
    //
    //   filteredRssi is always negative (e.g. -60 dBm).
    //   Adding 100 shifts it to a 0-100 positive scale:
    //     -100 dBm  →  0   (weakest signal possible)
    //     -70  dBm  →  30  (distant)
    //     -50  dBm  →  50  (moderate)
    //     -30  dBm  →  70  (very close)
    //
    //   Effect: a floor with MORE beacons AND STRONGER RSSI wins.
    //   A single very-close beacon can outweigh many distant ones.
    // ────────────────────────────────────────────────────────────────────────
    final scores = <String, double>{};
    for (final beacon in allBeacons) {
      final mac     = beacon.macAddress.toUpperCase();
      final content = _beaconMap[mac];
      if (content == null || content.floorId.isEmpty) continue;

      final rssiContribution = (beacon.filteredRssi + 100).clamp(0.0, 100.0);
      scores[content.floorId] = (scores[content.floorId] ?? 0) + rssiContribution;
    }

    if (scores.isEmpty) return;

    // Floor with the highest combined RSSI score wins this round.
    final winnerFloorId =
        scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    // ── Confirmation buffer ──────────────────────────────────────────────────
    //
    //  Mirrors indoor/outdoor mode transition logic:
    //   - The winning floor must win [floorConfirmationThreshold] CONSECUTIVE
    //     rounds before we actually change the displayed floor plan.
    //   - If a different floor wins even once, the counter resets.
    //   - If the current floor is still winning, we never start counting a switch.
    //
    //  This prevents a momentary RSSI spike from another floor's beacons
    //  (e.g., a beacon near a staircase) from flipping the floor plan.
    // ────────────────────────────────────────────────────────────────────────

    if (state?.id == winnerFloorId) {
      // Already on the winning floor — reset candidate and bail.
      _candidateFloor    = null;
      _candidateWinCount = 0;
      return;
    }

    // Resolve the FloorConfig for the winning id.
    final winnerConfig = _floors.cast<FloorConfig?>().firstWhere(
      (f) => f!.id == winnerFloorId,
      orElse: () => null,
    );
    if (winnerConfig == null) return; // unknown floor id — ignore

    if (_candidateFloor?.id != winnerFloorId) {
      // A new floor just took the lead — begin counting from 1.
      _candidateFloor    = winnerConfig;
      _candidateWinCount = 1;
      debugPrint('[FloorDetect] New candidate: ${winnerConfig.displayName} '
          '(score=${scores[winnerFloorId]?.toStringAsFixed(1)}) — '
          'needs ${AppConstants.floorConfirmationThreshold} wins');
    } else {
      // Same candidate won again — increment streak.
      _candidateWinCount++;
      debugPrint('[FloorDetect] Candidate ${winnerConfig.displayName} '
          'streak: $_candidateWinCount/${AppConstants.floorConfirmationThreshold}');
    }

    // Commit floor switch only once threshold is reached.
    if (_candidateWinCount >= AppConstants.floorConfirmationThreshold) {
      state              = winnerConfig;
      _candidateFloor    = null;
      _candidateWinCount = 0;
      debugPrint('[FloorDetect] ✅ Floor CONFIRMED → ${state?.displayName}  '
          'scores: ${scores.map((k, v) => MapEntry(k, v.toStringAsFixed(1)))}');
    }
  }

  /// Manually switch to a floor (user taps floor selector tab).
  void setFloor(FloorConfig floor) {
    // Manual override also resets the confirmation buffer so we don't
    // immediately auto-switch back to the previously detected floor.
    _candidateFloor    = null;
    _candidateWinCount = 0;
    state = floor;
  }

  /// Force refresh all floors from Firestore (for pull-to-refresh / background sync).
  Future<void> refreshFloors() async {
    _ready             = false;
    _candidateFloor    = null;
    _candidateWinCount = 0;
    _floors.clear();
    _beaconMap.clear();
    state = null;
    await _init();
  }
}

final currentFloorProvider =
    StateNotifierProvider<CurrentFloorNotifier, FloorConfig?>(
  (ref) => CurrentFloorNotifier(ref),
);
