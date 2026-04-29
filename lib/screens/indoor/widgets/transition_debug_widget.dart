import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/constants.dart';
import '../../../providers/location_mode_provider.dart';
import '../../../providers/ble_provider.dart';

/// Real-time debug overlay for the Seamless Transition Engine.
///
/// Shows GPS accuracy, evidence score, beacon count, timers, and
/// force-mode buttons for field testing.
///
/// Usage — add anywhere in the widget tree (e.g. IndoorScreen FAB overlay):
///   if (kDebugMode) const TransitionDebugWidget()
class TransitionDebugWidget extends ConsumerWidget {
  const TransitionDebugWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ts  = ref.watch(locationModeProvider);
    final ble = ref.watch(bleProvider);

    final nearestRssi = ble.detectedBeacons.values.isEmpty
        ? null
        : ble.detectedBeacons.values
            .map((b) => b.filteredRssi)
            .reduce((a, b) => a > b ? a : b);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          const Text(
            '⚙ Transition Engine Debug',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),

          _row(
            'Mode',
            ts.mode.name.toUpperCase(),
            ts.mode == LocationMode.indoor
                ? Colors.greenAccent
                : ts.mode == LocationMode.transitioning
                    ? Colors.amber
                    : Colors.lightBlueAccent,
          ),
          _row(
            'GPS Accuracy',
            '${ts.gpsAccuracy.toStringAsFixed(1)} m',
            ts.gpsAccuracy < AppConstants.gpsGoodThreshold
                ? Colors.greenAccent
                : ts.gpsAccuracy < AppConstants.gpsAccuracyThreshold
                    ? Colors.amber
                    : Colors.redAccent,
          ),
          _row(
            'Evidence',
            '${ts.evidenceScore.toStringAsFixed(2)} / ${AppConstants.maxEvidence.toStringAsFixed(0)}',
            ts.evidenceScore >= AppConstants.indoorEvidenceThreshold
                ? Colors.greenAccent
                : Colors.amber,
          ),
          _row(
            'Beacons visible',
            '${ble.detectedBeacons.length}',
            ble.detectedBeacons.isNotEmpty ? Colors.greenAccent : Colors.grey,
          ),
          if (nearestRssi != null)
            _row(
              'Strongest RSSI',
              '${nearestRssi.toStringAsFixed(0)} dBm'
              ' (strong > ${AppConstants.bleStrongRssi.toStringAsFixed(0)})',
              nearestRssi > AppConstants.bleStrongRssi
                  ? Colors.greenAccent
                  : Colors.amber,
            ),
          if (ts.mode == LocationMode.transitioning)
            _row(
              'Transition timer',
              '${ts.transitionSecs}s / ${AppConstants.minTransitionDuration}s min',
              Colors.amber,
            ),
          if (ts.mode == LocationMode.indoor && ts.beaconLostSecs > 0)
            _row(
              'Beacon loss',
              '${ts.beaconLostSecs}s / ${AppConstants.beaconLossDuration}s',
              Colors.orange,
            ),

          const SizedBox(height: 8),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 8),

          // Force-mode buttons
          Row(
            children: [
              _btn('Force Outdoor', LocationMode.outdoor, ref, Colors.lightBlueAccent),
              const SizedBox(width: 6),
              _btn('Force Indoor', LocationMode.indoor, ref, Colors.greenAccent),
              const SizedBox(width: 6),
              _btn('→ Transit', LocationMode.transitioning, ref, Colors.amber),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 10),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, LocationMode mode, WidgetRef ref, Color color) {
    return GestureDetector(
      onTap: () => ref.read(locationModeProvider.notifier).setMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
