import 'dart:math' show pow;
import '../app/constants.dart';

/// Represents a **live-detected** BLE beacon during a scan session.
///
/// Since all 15 beacons share UUID = E4CCDBE2-..., we use [macAddress]
/// (Android device.remoteId) as the unique identifier for each beacon.
class BleBeacon {
  /// UUID string — uppercase, dashed. Same for all beacons.
  final String uuid;

  /// MAC address string — e.g. "0E:A5:26:34:00:04".
  /// UNIQUE identifier for each beacon (UUID is shared across all 15).
  final String macAddress;

  /// Advertised device name — e.g. "ER26C00004".
  /// Use this as the tile label; it's more human-readable than MAC.
  final String deviceName;

  final int major;
  final int minor;

  /// Raw RSSI from the last advertisement packet (dBm).
  final double rawRssi;

  /// Kalman-filtered RSSI — stabilised version of rawRssi.
  final double filteredRssi;

  /// Computed distance in metres using the log-distance path-loss model.
  final double distanceMetres;

  /// Number of consecutive hits where distance <= 4m.
  final int consecutiveInRangeCount;

  /// Timestamp of the most recent advertisement packet seen.
  final DateTime lastSeen;

  const BleBeacon({
    required this.uuid,
    required this.macAddress,
    required this.deviceName,
    required this.major,
    required this.minor,
    required this.rawRssi,
    required this.filteredRssi,
    required this.distanceMetres,
    required this.consecutiveInRangeCount,
    required this.lastSeen,
  });

  // ── Unique key ────────────────────────────────────────────────────────────
  /// MAC address — used as map key for deduplication since all beacons share UUID.
  String get key => macAddress.toUpperCase();

  /// Short MAC suffix for labels when device name is empty.
  String get shortMac => macAddress.length >= 5
      ? macAddress.substring(macAddress.length - 5).toUpperCase()
      : macAddress.toUpperCase();

  // ── Proximity helpers ─────────────────────────────────────────────────────
  bool get isNear => distanceMetres <= AppConstants.proximityTriggerMetres;

  /// Only true if we've seen this beacon within 4m for several consecutive packets.
  /// Prevents transient spikes/noise from triggering content display.
  bool get isConfirmedInRange =>
      consecutiveInRangeCount >= AppConstants.beaconConfirmationThreshold;

  bool get isTimedOut =>
      DateTime.now().difference(lastSeen).inSeconds >
      AppConstants.beaconTimeoutSeconds;

  // ── Distance calculation ──────────────────────────────────────────────────
  /// Log-distance path-loss model: d = 10^((txPower - rssi) / (10 * n))
  static double rssiToDistance(double rssi, {int? txPower}) {
    final double tx = (txPower ?? AppConstants.beaconTxPower).toDouble();
    const double n  = AppConstants.pathLossExponent;
    return pow(10.0, (tx - rssi) / (10.0 * n)).toDouble();
  }

  BleBeacon copyWith({
    double?   rawRssi,
    double?   filteredRssi,
    double?   distanceMetres,
    int?      consecutiveInRangeCount,
    DateTime? lastSeen,
  }) =>
      BleBeacon(
        uuid:           uuid,
        macAddress:     macAddress,
        deviceName:     deviceName,
        major:          major,
        minor:          minor,
        rawRssi:        rawRssi         ?? this.rawRssi,
        filteredRssi:   filteredRssi    ?? this.filteredRssi,
        distanceMetres: distanceMetres  ?? this.distanceMetres,
        consecutiveInRangeCount: consecutiveInRangeCount ?? this.consecutiveInRangeCount,
        lastSeen:       lastSeen        ?? this.lastSeen,
      );
}
