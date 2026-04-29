import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../app/constants.dart';
import 'ble_provider.dart';
import '../services/content_service.dart';

/// Which positioning mode the app is currently in.
enum LocationMode { outdoor, transitioning, indoor }

extension LocationModeX on LocationMode {
  bool get isOutdoor      => this == LocationMode.outdoor;
  bool get isTransitioning => this == LocationMode.transitioning;
  bool get isIndoor       => this == LocationMode.indoor;
}

// ── State ─────────────────────────────────────────────────────────────────

class LocationModeState {
  final LocationMode mode;
  final String       reason;          // human-readable for debug / banner
  final double       evidenceScore;   // 0.0 → maxEvidence
  final double       gpsAccuracy;     // rolling-average metres
  final int          transitionSecs;  // seconds spent in TRANSITIONING
  final int          beaconLostSecs;  // seconds beacons have been absent (INDOOR)
  final String?      statusMessage;   // shown in the top banner (auto-clears)

  const LocationModeState({
    this.mode           = LocationMode.outdoor,
    this.reason         = 'Initial state',
    this.evidenceScore  = 0.0,
    this.gpsAccuracy    = 0.0,
    this.transitionSecs = 0,
    this.beaconLostSecs = 0,
    this.statusMessage,
  });

  LocationModeState copyWith({
    LocationMode? mode,
    String?       reason,
    double?       evidenceScore,
    double?       gpsAccuracy,
    int?          transitionSecs,
    int?          beaconLostSecs,
    String?       statusMessage,
    bool          clearMessage = false,
  }) =>
      LocationModeState(
        mode:           mode           ?? this.mode,
        reason:         reason         ?? this.reason,
        evidenceScore:  evidenceScore  ?? this.evidenceScore,
        gpsAccuracy:    gpsAccuracy    ?? this.gpsAccuracy,
        transitionSecs: transitionSecs ?? this.transitionSecs,
        beaconLostSecs: beaconLostSecs ?? this.beaconLostSecs,
        statusMessage:  clearMessage ? null : (statusMessage ?? this.statusMessage),
      );
}

// ── Notifier ───────────────────────────────────────────────────────────────

class LocationModeNotifier extends StateNotifier<LocationModeState> {
  final Ref _ref;

  // Timers
  StreamSubscription<Position>? _gpsStreamSub; // streams GPS continuously
  Timer? _evidenceTimer;     // updates evidence score every 500ms (real-time)
  Timer? _transitionTimer;   // counts seconds in TRANSITIONING state
  Timer? _beaconLossTimer;   // counts seconds beacons have been absent (INDOOR)
  Timer? _timeoutTimer;      // forces revert if TRANSITIONING too long
  Timer? _messageClearTimer; // auto-clears banner messages

  // Rolling GPS accuracy average
  final List<double> _recentAccuracies = [];

  LocationModeNotifier(this._ref)
      : super(const LocationModeState()) {
    // BLE updates drive the engine too — fast path for immediate reaction.
    _ref.listen<BleState>(bleProvider, (_, next) => _onBleUpdate(next));
  }

  // ── Engine lifecycle ──────────────────────────────────────────────────────

  /// Call once from the app shell after providers are wired.
  void startEngine() {
    debugPrint('[TransitionEngine] ▶ Engine started');
    _startGpsPolling();
    _startEvidenceTimer();
  }

  void stopEngine() {
    _gpsStreamSub?.cancel();
    _evidenceTimer?.cancel();
    _transitionTimer?.cancel();
    _beaconLossTimer?.cancel();
    _timeoutTimer?.cancel();
    _messageClearTimer?.cancel();
  }

  // ── GPS polling (every 1s — real-time accuracy tracking) ─────────────────

  void _startGpsPolling() {
    // Instead of turning the GPS hardware on and off every second (which causes the location
    // icon to flicker and drains battery), we use a continuous stream.
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0, // get updates as frequently as possible
    );
    
    _gpsStreamSub = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen(
      (Position pos) {
        _recordAccuracy(pos.accuracy);
      },
      onError: (error) {
        // GPS unavailable — treat as very poor (strong indoor signal)
        _recordAccuracy(AppConstants.gpsVeryPoorThreshold + 20);
      },
    );
  }

  void _recordAccuracy(double acc) {
    _recentAccuracies.add(acc);
    if (_recentAccuracies.length > AppConstants.gpsRollingAverageCount) {
      _recentAccuracies.removeAt(0);
    }
    final avg = _recentAccuracies.isEmpty
        ? 999.0
        : _recentAccuracies.reduce((a, b) => a + b) / _recentAccuracies.length;
    state = state.copyWith(gpsAccuracy: avg);
    _evaluate();
  }

  // ── BLE fast-path (immediate reaction on scan event) ─────────────────────

  void _onBleUpdate(BleState ble) {
    // React immediately to BLE changes — don't wait for the evidence timer.
    _evaluate();
    // If indoors and valid beacons suddenly appear again, cancel the loss timer.
    final hasValidBeacons = ble.detectedBeacons.values.any((b) => b.filteredRssi > AppConstants.bleEntryRssi);
    if (state.mode.isIndoor && hasValidBeacons) {
      if (_beaconLossTimer != null) {
        _beaconLossTimer?.cancel();
        _beaconLossTimer = null;
        if (state.beaconLostSecs > 0) {
          state = state.copyWith(beaconLostSecs: 0);
        }
      }
    }
  }

  // ── Evidence accumulator (every 500ms — fast scoring) ────────────────────

  void _startEvidenceTimer() {
    _evidenceTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _updateEvidence(),
    );
  }

  void _updateEvidence() {
    // Only run when not in stable OUTDOOR with no signals.
    if (state.mode.isOutdoor && !_anyEntrySignal()) return;

    final ble   = _ref.read(bleProvider);
    double score = state.evidenceScore;

    // Score from BLE beacons
    for (final beacon in ble.detectedBeacons.values) {
      if (beacon.filteredRssi > AppConstants.bleStrongRssi) {
        score += AppConstants.strongBeaconWeight * 0.5; // per 500ms tick
      } else if (beacon.filteredRssi > AppConstants.bleEntryRssi) {
        score += AppConstants.weakBeaconWeight * 0.5;
      }
    }

    // Score from GPS degradation
    if (state.gpsAccuracy > AppConstants.gpsVeryPoorThreshold) {
      score += AppConstants.gpsDegradedWeight * 1.5 * 0.5; // extra weight very poor GPS
    } else if (state.gpsAccuracy > AppConstants.gpsAccuracyThreshold) {
      score += AppConstants.gpsDegradedWeight * 0.5;
    } else if (state.gpsAccuracy < AppConstants.gpsGoodThreshold &&
               state.gpsAccuracy > 0) {
      score -= AppConstants.gpsGoodPenalty * 0.5; // GPS good → evidence drains
    }

    score = score.clamp(0.0, AppConstants.maxEvidence);
    state = state.copyWith(evidenceScore: score);
    _evaluate();
  }

  // ── Core evaluator — called from GPS, BLE, and evidence updates ───────────

  void _evaluate() {
    switch (state.mode) {
      case LocationMode.outdoor:
        if (_anyEntrySignal()) _enterTransitioning();
        break;
      case LocationMode.transitioning:
        if (_shouldConfirmIndoor()) {
          _enterIndoor();
        } else if (_shouldRevertOutdoor()) {
          _revertToOutdoor('Evidence depleted + GPS good');
        }
        break;
      case LocationMode.indoor:
        _checkIndoorExit();
        break;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _anyEntrySignal() {
    final ble        = _ref.read(bleProvider);
    final gpsDegrade = state.gpsAccuracy > AppConstants.gpsAccuracyThreshold;
    final blePresent = ble.detectedBeacons.values.any(
        (b) => b.filteredRssi > AppConstants.bleEntryRssi);
    return gpsDegrade || blePresent;
  }

  bool _shouldConfirmIndoor() {
    final ble          = _ref.read(bleProvider);
    final enoughBeacon = ble.detectedBeacons.length >= AppConstants.minBeaconsForIndoor;
    final strongSignal = ble.detectedBeacons.values.any(
        (b) => b.filteredRssi > AppConstants.bleStrongRssi);
    final enoughEvidence = state.evidenceScore >= AppConstants.indoorEvidenceThreshold;
    final enoughTime     = state.transitionSecs >= AppConstants.minTransitionDuration;
    return enoughBeacon && strongSignal && enoughEvidence && enoughTime;
  }

  bool _shouldRevertOutdoor() {
    final gpsGood = state.gpsAccuracy < AppConstants.gpsGoodThreshold &&
                    state.gpsAccuracy > 0;
    return gpsGood && state.evidenceScore <= 0;
  }

  // ── State transitions ─────────────────────────────────────────────────────

  void _enterTransitioning() {
    if (state.mode == LocationMode.transitioning) return; // already there
    debugPrint('[TransitionEngine] OUTDOOR → TRANSITIONING '
        '(GPS=${state.gpsAccuracy.toStringAsFixed(1)}m '
        'ev=${state.evidenceScore.toStringAsFixed(1)})');

    _transitionTimer?.cancel();
    _timeoutTimer?.cancel();

    state = state.copyWith(
      mode:           LocationMode.transitioning,
      reason:         'Approaching venue',
      transitionSecs: 0,
      clearMessage:   true,
    );

    // Count how long we've been in TRANSITIONING
    _transitionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(transitionSecs: state.transitionSecs + 1);
    });

    // Watchdog — if no confirm in N seconds, give up
    _timeoutTimer = Timer(
      Duration(seconds: AppConstants.transitionTimeoutSecs),
      () {
        if (state.mode.isTransitioning) {
          debugPrint('[TransitionEngine] ⏱ Transition timeout → OUTDOOR');
          _revertToOutdoor('Transition timed out');
        }
      },
    );
  }

  Future<void> _enterIndoor() async {
    if (state.mode == LocationMode.indoor) return;
    debugPrint('[TransitionEngine] TRANSITIONING → INDOOR ✅');

    _transitionTimer?.cancel();
    _timeoutTimer?.cancel();

    state = state.copyWith(
      mode:           LocationMode.indoor,
      reason:         'BLE confirmed + GPS degraded',
      transitionSecs: 0,
      beaconLostSecs: 0,
      statusMessage:  'Welcome — Indoor Mode active',
    );

    // Pre-cache all beacon content for offline use inside the venue
    ContentService.preCacheVenueBeacons().ignore();

    _setMessageTimer();
  }

  void _revertToOutdoor(String reason) {
    if (state.mode == LocationMode.outdoor) return;
    debugPrint('[TransitionEngine] → OUTDOOR ($reason)');

    _transitionTimer?.cancel();
    _timeoutTimer?.cancel();
    _beaconLossTimer?.cancel();
    _beaconLossTimer = null;

    state = state.copyWith(
      mode:           LocationMode.outdoor,
      reason:         reason,
      evidenceScore:  0.0,
      transitionSecs: 0,
      beaconLostSecs: 0,
      clearMessage:   true,
    );
    _recentAccuracies.clear();
  }

  // ── INDOOR exit logic ─────────────────────────────────────────────────────

  void _checkIndoorExit() {
    final ble         = _ref.read(bleProvider);
    final beaconsGone = ble.detectedBeacons.isEmpty || 
        !ble.detectedBeacons.values.any((b) => b.filteredRssi > AppConstants.bleEntryRssi);
    final gpsGood    = state.gpsAccuracy < AppConstants.gpsGoodThreshold &&
                       state.gpsAccuracy > 0;

    if (beaconsGone && gpsGood) {
      if (_beaconLossTimer == null || !_beaconLossTimer!.isActive) {
        debugPrint('[TransitionEngine] Beacon loss detected — counting…');
        _beaconLossTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          final newCount = state.beaconLostSecs + 1;
          state = state.copyWith(beaconLostSecs: newCount);

          if (newCount >= AppConstants.beaconLossDuration) {
            _beaconLossTimer?.cancel();
            _beaconLossTimer = null;
            // Confirmation delay — one last check
            Timer(Duration(seconds: AppConstants.exitConfirmationDelay), _confirmExit);
          }
        });
      }
    } else {
      // Conditions not met → reset the loss counter
      if (_beaconLossTimer != null) {
        _beaconLossTimer?.cancel();
        _beaconLossTimer = null;
        if (state.beaconLostSecs > 0) {
          state = state.copyWith(beaconLostSecs: 0);
        }
      }
    }
  }

  void _confirmExit() {
    final ble       = _ref.read(bleProvider);
    final stillGone = ble.detectedBeacons.isEmpty || 
        !ble.detectedBeacons.values.any((b) => b.filteredRssi > AppConstants.bleEntryRssi);
    final gpsGood   = state.gpsAccuracy < AppConstants.gpsGoodThreshold &&
                      state.gpsAccuracy > 0;

    if (!stillGone || !gpsGood) {
      // Conditions changed — abort exit, stay indoor
      debugPrint('[TransitionEngine] Exit aborted — conditions changed');
      state = state.copyWith(beaconLostSecs: 0);
      return;
    }
    _revertToOutdoor('Beacons lost + GPS recovered');
  }

  // ── Message auto-clear ────────────────────────────────────────────────────

  void _setMessageTimer() {
    _messageClearTimer?.cancel();
    _messageClearTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) state = state.copyWith(clearMessage: true);
    });
  }

  // ── Manual override (for debug / testing) ────────────────────────────────

  /// Force the engine into a specific mode — for field testing only.
  void setMode(LocationMode mode) {
    debugPrint('[TransitionEngine] ⚙ Manual override → $mode');
    switch (mode) {
      case LocationMode.outdoor:
        _revertToOutdoor('Manual override');
        break;
      case LocationMode.indoor:
        _enterIndoor();
        break;
      case LocationMode.transitioning:
        _enterTransitioning();
        break;
    }
  }

  @override
  void dispose() {
    stopEngine();
    super.dispose();
  }
}

// ── Provider ───────────────────────────────────────────────────────────────

final locationModeProvider =
    StateNotifierProvider<LocationModeNotifier, LocationModeState>(
  (ref) => LocationModeNotifier(ref),
);
