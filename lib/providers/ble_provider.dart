import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/constants.dart';
import '../models/ble_beacon_model.dart';
import '../services/kalman_filter.dart';

/// Immutable BLE scan state.
class BleState {
  /// All currently visible beacons keyed by MAC address.
  final Map<String, BleBeacon> detectedBeacons;
  final bool isScanning;
  final String? errorMessage;

  const BleState({
    this.detectedBeacons = const {},
    this.isScanning      = false,
    this.errorMessage,
  });

  BleState copyWith({
    Map<String, BleBeacon>? detectedBeacons,
    bool?   isScanning,
    String? errorMessage,
    bool    clearError = false,
  }) =>
      BleState(
        detectedBeacons: detectedBeacons ?? this.detectedBeacons,
        isScanning:      isScanning      ?? this.isScanning,
        errorMessage:    clearError ? null : (errorMessage ?? this.errorMessage),
      );

  List<BleBeacon> get sortedBeacons {
    final list = detectedBeacons.values
        .where((b) => b.distanceMetres <= AppConstants.proximityTriggerMetres && b.isConfirmedInRange)
        .toList();
    list.sort((a, b) => a.distanceMetres.compareTo(b.distanceMetres));
    return list;
  }
}

class BleNotifier extends StateNotifier<BleState> {
  BleNotifier() : super(const BleState());

  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _timeoutTimer;

  /// One Kalman filter per beacon MAC address — persists between scans.
  final Map<String, KalmanFilter> _kalmanFilters = {};

  /// Track the latest timestamp we've processed for each beacon to ignore cached scan results.
  final Map<String, DateTime> _lastProcessedTimes = {};

  // ─────────────────────────────────────────────────────────────────────────
  // Scan lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    if (state.isScanning) return;

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      state = state.copyWith(
          errorMessage: 'Bluetooth is off. Please enable Bluetooth.');
      return;
    }

    state = state.copyWith(isScanning: true, clearError: true);
    _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);

    try {
      // ╔══════════════════════════════════════════════════════════════════╗
      // ║  CRITICAL FIX — scan mode & filter                              ║
      // ║                                                                  ║
      // ║  DO NOT pass withServices: [] — on Android, an empty filter     ║
      // ║  list causes the OS to switch to OPPORTUNISTIC mode, where       ║
      // ║  results are only delivered when ANOTHER app is also actively    ║
      // ║  scanning. That is why other BLE devices appeared (because       ║
      // ║  nRF Connect was running), but our dedicated beacons did not.   ║
      // ║                                                                  ║
      // ║  Solution: pass NO filter at all + explicit lowLatency mode.     ║
      // ╚══════════════════════════════════════════════════════════════════╝
      await FlutterBluePlus.startScan(
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.lowLatency, // SCAN_MODE_LOW_LATENCY
        // No withServices / withName filters → OS uses full active scanning
        // No timeout → scan until stopScan() is called
      );
    } catch (e) {
      debugPrint('BLE startScan error: $e');
      state = state.copyWith(
          errorMessage: 'BLE scan failed: $e', isScanning: false);
      return;
    }

    // Periodic timeout sweep — removes beacons we haven't seen recently.
    _timeoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _removeTimedOutBeacons();
    });
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _timeoutTimer?.cancel();
    _scanSub      = null;
    _timeoutTimer = null;
    _lastProcessedTimes.clear();
    state = state.copyWith(isScanning: false);
  }

  @override
  void dispose() {
    stopScan();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Advertisement processing
  // ─────────────────────────────────────────────────────────────────────────

  void _onScanResults(List<ScanResult> results) {
    for (final result in results) {
      if (result.rssi < AppConstants.minUsableRssi) continue;
      
      final mac = result.device.remoteId.str.toUpperCase();
      final lastTime = _lastProcessedTimes[mac];
      // Ignore packets we've already processed (FlutterBluePlus aggregates them)
      if (lastTime != null && !result.timeStamp.isAfter(lastTime)) {
        continue;
      }
      _lastProcessedTimes[mac] = result.timeStamp;

      final beacon = _parseBeacon(result);
      if (beacon != null) {
        _updateBeaconState(beacon);
      }
    }
  }


  /// ══════════════════════════════════════════════════════════════════════
  /// Multi-format beacon parser.
  ///
  ///  KEY FINDING: These EasyReach beacons do NOT put their UUID in the
  ///  advertisement packet. The UUID "E4CCDBE2-..." is a GATT service UUID,
  ///  only visible after connecting. Runtime advertisement data contains:
  ///    - Device name:  "ER26C00004"  ← primary identifier at scan time
  ///    - MfData:       Company=0xA50E, Bytes=[] (empty)
  ///
  ///  Detection order (fastest → slowest):
  ///    5. Device name starts with "ER26C"          ← PRIMARY (fastest)
  ///    6. MAC address starts with "0E:A5:26:34:00:" ← SECONDARY
  ///    1-4. UUID in various ad-data fields         ← FALLBACK (future-proof)
  /// ══════════════════════════════════════════════════════════════════════
  BleBeacon? _parseBeacon(ScanResult result) {
    final mac  = result.device.remoteId.str.toUpperCase();
    final name = result.advertisementData.advName;

    if (name.startsWith(AppConstants.knownBeaconNamePrefix)) {
      return _buildBeacon(
        result,
        AppConstants.knownBeaconUuids.first,
        0, // major — not in ad packet
        _serialFromName(name), // minor derived from last digits of name
      );
    }

    // ── Approach 6 (SECONDARY): Match by MAC address prefix ──────────────
    // All beacons share MAC prefix "0E:A5:26:34:00:".
    if (mac.startsWith(AppConstants.knownMacPrefix.toUpperCase())) {
      return _buildBeacon(result, AppConstants.knownBeaconUuids.first, 0, 0);
    }

    // ── Approaches 1-4: UUID in advertisement data (future-proof) ─────────
    // These fire if a beacon is ever reconfigured to broadcast the UUID.

    // 1. iBeacon structure under any company ID
    for (final entry in result.advertisementData.manufacturerData.entries) {
      final bytes = entry.value;
      if (bytes.length >= 23 && bytes[0] == 0x02 && bytes[1] == 0x15) {
        final uuid      = _bytesToUuid(bytes.sublist(2, 18));
        final uuidUpper = uuid.toUpperCase();
        if (AppConstants.knownBeaconUuids.contains(uuidUpper)) {
          final major = (bytes[18] << 8) | bytes[19];
          final minor = (bytes[20] << 8) | bytes[21];
          debugPrint('  ✅ iBeacon UUID match (company=0x'
              '${entry.key.toRadixString(16).toUpperCase()}): '
              '$uuidUpper  Major=$major  Minor=$minor');
          return _buildBeacon(result, uuidUpper, major, minor);
        }
      }
    }

    // 2. Service UUID list
    for (final svcUuid in result.advertisementData.serviceUuids) {
      for (final known in AppConstants.knownBeaconUuids) {
        if (_normalise(svcUuid.toString()) == _normalise(known)) {
          debugPrint('  ✅ Service UUID match: $svcUuid');
          return _buildBeacon(result, known, 0, 0);
        }
      }
    }

    // 3. Service data key
    for (final entry in result.advertisementData.serviceData.entries) {
      for (final known in AppConstants.knownBeaconUuids) {
        if (_normalise(entry.key.toString()) == _normalise(known)) {
          debugPrint('  ✅ Service data UUID match: ${entry.key}');
          return _buildBeacon(result, known, 0, 0);
        }
      }
    }

    // 4. Raw UUID bytes anywhere in manufacturer data
    if (AppConstants.knownBeaconUuids.isNotEmpty) {
      final targetBytes = _uuidToBytes(AppConstants.knownBeaconUuids.first);
      for (final entry in result.advertisementData.manufacturerData.entries) {
        final idx = _findSublist(entry.value, targetBytes);
        if (idx >= 0) {
          debugPrint('  ✅ Raw UUID bytes in MfData at index $idx');
          return _buildBeacon(result, AppConstants.knownBeaconUuids.first, 0, 0);
        }
      }
    }

    return null; // not one of our beacons
  }

  /// Extract serial number from name "ER26C00004" → minor = 4.
  /// Used as a minor value surrogate so EKF and content lookup work.
  static int _serialFromName(String name) {
    final digits = RegExp(r'\d+$').firstMatch(name)?.group(0);
    return int.tryParse(digits ?? '0') ?? 0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Beacon construction
  // ─────────────────────────────────────────────────────────────────────────

  BleBeacon _buildBeacon(
      ScanResult result, String uuidUpper, int major, int minor) {
    final rssi       = result.rssi.toDouble();
    final mac        = result.device.remoteId.str.toUpperCase();
    final deviceName = result.advertisementData.advName;


    final kalman = _kalmanFilters.putIfAbsent(
        mac,
        () => KalmanFilter(
              initialEstimate: rssi,
              q: AppConstants.kalmanQ,
              r: AppConstants.kalmanR,
            ));
    final filteredRssi = kalman.update(rssi);
    final distance     = BleBeacon.rssiToDistance(filteredRssi);

    return BleBeacon(
      uuid:           uuidUpper,
      macAddress:     mac,
      deviceName:     deviceName,
      major:          major,
      minor:          minor,
      rawRssi:        rssi,
      filteredRssi:   filteredRssi,
      distanceMetres: distance,
      consecutiveInRangeCount: 0, // Placeholder, will be updated in _updateBeaconState
      lastSeen:       DateTime.now(),
    );
  }

  void _updateBeaconState(BleBeacon beacon) {
    final updated = Map<String, BleBeacon>.from(state.detectedBeacons);

    final existing  = updated[beacon.key];
    final prevCount = existing?.consecutiveInRangeCount ?? 0;
    int   newCount;

    if (beacon.distanceMetres <= AppConstants.proximityTriggerMetres) {
      // In range — increment, but CAP it so it doesn't grow infinitely!
      final maxCap = AppConstants.beaconConfirmationThreshold + 1;
      newCount = (prevCount + 1).clamp(0, maxCap);
    } else {
      // Out of range — graceful decrement. 
      // Because of the cap above, this will drop to 0 in max 3-4 packets.
      newCount = (prevCount - 1).clamp(0, 999);
    }

    updated[beacon.key] = beacon.copyWith(consecutiveInRangeCount: newCount);
    state = state.copyWith(detectedBeacons: updated);
  }

  void _removeTimedOutBeacons() {
    final now = DateTime.now();
    final updated = Map<String, BleBeacon>.from(state.detectedBeacons)
      ..removeWhere((_, b) =>
          now.difference(b.lastSeen).inSeconds > AppConstants.beaconTimeoutSeconds);
    if (updated.length != state.detectedBeacons.length) {
      state = state.copyWith(detectedBeacons: updated);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Utility helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// 16 bytes → dashed UUID string (8-4-4-4-12).
  static String _bytesToUuid(List<int> bytes) {
    assert(bytes.length == 16);
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}'
        '-${hex.substring(12, 16)}-${hex.substring(16, 20)}'
        '-${hex.substring(20)}';
  }

  /// Dashed UUID string → 16 bytes (big-endian).
  static List<int> _uuidToBytes(String uuid) {
    final hex = uuid.replaceAll('-', '');
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  /// Remove dashes and colons, uppercase — for flexible UUID comparison.
  static String _normalise(String s) =>
      s.replaceAll('-', '').replaceAll(':', '').toUpperCase();

  /// Finds [sub] inside [data], returns start index or -1.
  static int _findSublist(List<int> data, List<int> sub) {
    if (sub.isEmpty || data.length < sub.length) return -1;
    outer:
    for (int i = 0; i <= data.length - sub.length; i++) {
      for (int j = 0; j < sub.length; j++) {
        if (data[i + j] != sub[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}

final bleProvider =
    StateNotifierProvider<BleNotifier, BleState>(
  (ref) => BleNotifier(),
);
