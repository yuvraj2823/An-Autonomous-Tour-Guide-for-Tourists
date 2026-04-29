import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../models/floor_model.dart';
import '../../../models/beacon_model.dart';
import '../../../models/ble_beacon_model.dart';

/// Paints beacon markers and proximity highlights on top of the floor plan image.
///
/// Background is fully transparent — the actual floor plan PNG is rendered
/// by a CachedNetworkImage widget beneath this painter.
///
/// Draw order (back → front):
///   1. Pulse ring   — soft glow for confirmed in-range beacons
///   2. Diamond dot  — position marker for every beacon on this floor
///   3. Room label   — name printed below each diamond
///   4. Distance tag — "1.2m" printed when detected
class FloorOverlayPainter extends CustomPainter {
  final FloorConfig floorConfig;

  /// All beacons that belong to this floor (from Firestore, includes pixelX/Y).
  final List<BeaconContent> floorBeacons;

  /// Live confirmed beacons currently within 4 m, keyed by MAC (uppercase).
  final Map<String, BleBeacon> detectedBeacons;

  /// The Size that the parent widget is actually rendered at on screen.
  final Size renderedSize;

  /// Current value from an animation controller (0.0 to 1.0)
  final double pulseValue;

  const FloorOverlayPainter({
    required this.floorConfig,
    required this.floorBeacons,
    required this.detectedBeacons,
    required this.renderedSize,
    required this.pulseValue,
  });

  // ── Coordinate helper ────────────────────────────────────────────────────

  /// Map stored pixel coords → on-screen coordinates.
  Offset _toScreen(double px, double py) {
    final sx = px / floorConfig.imageWidthPixels  * renderedSize.width;
    final sy = py / floorConfig.imageHeightPixels * renderedSize.height;
    return Offset(sx, sy);
  }

  // ── Scale helper (for marker sizes) ─────────────────────────────────────

  /// Average scale factor (screen pixels per image pixel).
  double get _scale =>
      (renderedSize.width  / floorConfig.imageWidthPixels +
       renderedSize.height / floorConfig.imageHeightPixels) /
      2.5;

  // ── Paint ────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    for (final beacon in floorBeacons) {
      if (beacon.pixelX == 0 && beacon.pixelY == 0) continue; // no coords yet

      final screen     = _toScreen(beacon.pixelX, beacon.pixelY);
      final mac        = beacon.macAddress.toUpperCase();
      final isDetected = detectedBeacons.containsKey(mac);
      final isNear     = detectedBeacons[mac]?.isConfirmedInRange ?? false;

      // 1. Pulse & Proximity Glow (Confirmed beacons)
      if (isNear) {
        final bleBeacon = detectedBeacons[mac]!;
        final distance  = bleBeacon.distanceMetres;

        // Proximity factor: 1.0 at 0m, 0.0 at proximityTriggerMetres (4m)
        final proximity = (1.0 - (distance / 4.0)).clamp(0.0, 1.0);

        // A: The static "Proximity Glow" — grows stronger as you get closer
        final glowRadius = (60.0 + (40.0 * proximity)) * _scale.clamp(0.3, 1.5);
        final glowOpacity = (0.08 + (0.20 * proximity)).clamp(0.0, 1.0);

        canvas.drawCircle(
          screen,
          glowRadius,
          Paint()
            ..color = AppTheme.accentColor.withValues(alpha: glowOpacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
        );

        // B: The "Breath" Pulse — repeats continuously
        // We use two rings with different phase/scaling for a premium effect
        final pulseRadius = glowRadius * (0.9 + (0.5 * pulseValue));
        final pulseOpacity = (0.25 * (1.0 - pulseValue)).clamp(0.0, 1.0);

        canvas.drawCircle(
          screen,
          pulseRadius,
          Paint()
            ..color       = AppTheme.accentColor.withValues(alpha: pulseOpacity)
            ..style       = PaintingStyle.stroke
            ..strokeWidth = 3.5 * _scale.clamp(0.5, 1.5),
        );
      }

      // 2. Diamond marker
      final dSize = (isNear ? 16.0 : 12.0) * _scale.clamp(0.4, 1.8);
      final path  = Path()
        ..moveTo(screen.dx, screen.dy - dSize)
        ..lineTo(screen.dx + dSize, screen.dy)
        ..lineTo(screen.dx, screen.dy + dSize)
        ..lineTo(screen.dx - dSize, screen.dy)
        ..close();

      canvas.drawPath(
        path,
        Paint()
          ..color = isNear
              ? AppTheme.accentColor
              : isDetected
                  ? AppTheme.primaryColor
                  : Colors.grey.shade400,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color       = Colors.white
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      // 3. Room / exhibit label below the diamond
      _drawLabel(
        canvas,
        screen + Offset(4, dSize + 14 * _scale.clamp(0.5, 1.5)),
        beacon.objectName.isNotEmpty ? beacon.objectName : 'Beacon',
        fontSize:  17 * _scale.clamp(0.5, 1.5),
        bold:      isDetected,
        color:     isDetected ? AppTheme.primaryColor : Colors.grey.shade600,
      );

    }
  }

  // ── Text helper ──────────────────────────────────────────────────────────

  void _drawLabel(
    Canvas canvas,
    Offset centre,
    String text, {
    double fontSize = 10,
    bool bold = false,
    Color color = AppTheme.textPrimary,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color:      color,
          fontSize:   fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          height:     1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign:     TextAlign.center,
    )..layout(maxWidth: 100 * _scale.clamp(0.5, 1.5));
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(FloorOverlayPainter old) =>
      old.detectedBeacons != detectedBeacons ||
      old.renderedSize    != renderedSize    ||
      old.floorBeacons    != floorBeacons    ||
      old.pulseValue      != pulseValue;
}
