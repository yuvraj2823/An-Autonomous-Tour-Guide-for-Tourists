import 'package:flutter_dotenv/flutter_dotenv.dart';

/// All compile-time configuration values.
/// Google Places API removed — Firebase is the sole outdoor data source.
class AppConstants {
  // ── Groq LLM (sole generation engine) ───────────────────────────────────
  /// Get your key from: https://console.groq.com/keys
  static String get groqApiKey => dotenv.env['GROQ_API_KEY'] ?? '';
  static const String groqModelFast = 'llama-3.1-8b-instant';
  static const String groqModelFull = 'llama-3.3-70b-versatile';

  /// Queue spacing tuned for real-time feel while keeping free-tier stable.
  static const Duration llmMinIntervalBetweenRequests =
      Duration(milliseconds: 450);
  static const int llmMaxHttpRetries = 6;

  // ── BLE scanning ────────────────────────────────────────────────────────
  /// The shared iBeacon UUID. NOTE: These beacons do NOT put this UUID in their
  /// advertisement packets — it is a GATT service UUID visible only after connecting.
  /// We keep it for Firestore/SQLite lookup (content is keyed by UUID).
  static const Set<String> knownBeaconUuids = {
    'E4CCDBE2-2A2A-2FA3-E911-F3CDF8B4DDCC',
  };

  /// EasyReach beacon advertised device-name prefix.
  /// All 15 beacons advertise a name like "ER26C00004".
  /// Match by this prefix at scan time — no UUID parsing needed.
  static const String knownBeaconNamePrefix = 'ER26C';

  /// MAC address prefix shared by all 15 beacons.
  /// Used as a secondary match if the device name is empty.
  static const String knownMacPrefix = '0E:A5:26:34:00:';

  /// TX Power at 1 metre. -59 dBm is the iBeacon default.
  /// Update this if your beacon broadcasts a different TX Power byte.
  static const int beaconTxPower = -59;

  /// Path-loss exponent for indoor environment (walls, furniture).
  static const double pathLossExponent = 2.0;

  /// Proximity trigger distance in metres — content triggers when user is this close.
  static const double proximityTriggerMetres = 5;

  /// Number of consecutive in-range detections (<= 4m) required to confirm a beacon.
  /// 2 hits = ~1-2 seconds at typical beacon advertising intervals.
  static const int beaconConfirmationThreshold = 1;

  /// Ignore beacons below this RSSI — too far / unreliable.
  /// -85 dBm cuts out phantom packets from the parking lot.
  static const int minUsableRssi = -90;

  /// Beacon advertising interval. 8s timeout = ~2-3x typical beacon interval.
  static const int beaconTimeoutSeconds = 10;

  /// Consecutive BLE rounds the same floor must WIN before the floor plan switches.
  /// Prevents flickering when walking between floors (mirrors indoor/outdoor debounce).
  static const int floorConfirmationThreshold = 2;

  // ── Kalman filter (Stage 1 — RSSI smoothing) ────────────────────────────
  static const double kalmanQ = 0.12; // process noise
  static const double kalmanR = 0.8; // measurement noise (higher = smoother RSSI)

  // ── Outdoor search ──────────────────────────────────────────────────────
  static const double defaultSearchRadius = 1000.0; // metres
  static const double maxSearchRadius = 10000.0;
  static const double minSearchRadius = 100.0;
  static const double thresholdDistanceMetres = 10000.0; // max distance to show a place

  // ── Seamless Transition Engine ───────────────────────────────────────────
  // GPS accuracy thresholds (metres)
  // Below gpsGoodThreshold:      GPS is reliable  → evidence against indoor
  // Above gpsAccuracyThreshold:  GPS degrading    → evidence for indoor
  // Above gpsVeryPoorThreshold:  GPS almost gone  → very strong indoor evidence
  static const double gpsGoodThreshold = 10.0;
  static const double gpsAccuracyThreshold = 15.0;
  static const double gpsVeryPoorThreshold = 25.0;

  // BLE RSSI thresholds (dBm)
  static const double bleEntryRssi = -90.0; // minimum to count as "present"
  static const double bleStrongRssi = -72.0; // strong enough to confirm indoor

  // Evidence accumulator (score 0.0 → maxEvidence)
  static const double indoorEvidenceThreshold = 4.0; // lowered for faster entry
  static const double maxEvidence = 10.0;
  static const double strongBeaconWeight =
      2.0; // boosted for real-time response
  static const double weakBeaconWeight = 0.8;
  static const double gpsDegradedWeight = 0.5;
  static const double gpsGoodPenalty = 0.8; // penalty not too aggressive

  // Timing — tuned for real-time responsiveness without false positives
  static const int minBeaconsForIndoor = 1;
  static const int minTransitionDuration =
      2; // 2s sustained presence before confirming
  static const int transitionTimeoutSecs =
      15; // give up transitioning after 15s
  static const int beaconLossDuration =
      4; // beacons gone s before exiting indoor
  static const int exitConfirmationDelay = 3; // extra 3s before confirming exit

  // Rolling average window for GPS accuracy readings
  static const int gpsRollingAverageCount = 3;
}
