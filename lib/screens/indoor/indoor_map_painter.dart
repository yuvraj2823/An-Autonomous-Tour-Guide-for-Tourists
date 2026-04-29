import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/venue_config.dart';
import '../../app/theme.dart';
import '../../models/ble_beacon_model.dart';

/// Draws the entire indoor floor plan AND position overlays in one pass.
///
/// Draw order (back to front):
///   1. Floor background + outer walls
///   2. Room divider (Hall A / Hall B)
///   3. Exhibit boxes with labels
///   4. Entrance marker + scale bar
///   5. Debug grid (conditional)
///   6. Beacon diamond markers + proximity circles
///   7. User position dot
class IndoorMapPainter extends CustomPainter {
  final Offset? userPosition;
  final Map<String, BleBeacon> detectedBeacons;
  final Size renderedSize;
  final bool showGrid;
  final double heading; // Madgwick yaw in degrees (0=north, 90=east)

  const IndoorMapPainter({
    required this.userPosition,
    required this.detectedBeacons,
    required this.renderedSize,
    required this.showGrid,
    this.heading = 0.0,
  });

  // ── Screen-space scale factors ────────────────────────────────────────
  double get scaleX => renderedSize.width  / VenueConfig.svgWidth;
  double get scaleY => renderedSize.height / VenueConfig.svgHeight;

  /// Convert real-world metres → screen pixels.
  Offset _toScreen(Offset realPos) {
    final svgPos = VenueConfig.realToSvg(realPos);
    return Offset(svgPos.dx * scaleX, svgPos.dy * scaleY);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawFloorPlan(canvas, size);
    if (showGrid) _drawDebugGrid(canvas, size);
    _drawBeaconMarkers(canvas, size);
    if (userPosition != null) _drawUserDot(canvas, userPosition!);
  }

  // ──────────────────────────────────────────────────────────────────────
  // 1. Floor plan
  // ──────────────────────────────────────────────────────────────────────
  void _drawFloorPlan(Canvas canvas, Size size) {
    final floorPaint = Paint()..color = const Color(0xFFF5F0E8);
    final wallPaint  = Paint()
      ..color       = const Color(0xFF2C2C2C)
      ..strokeWidth = 10 * scaleX
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.square;
    final dividerPaint = Paint()
      ..color       = const Color(0xFF2C2C2C)
      ..strokeWidth = 4  * scaleX
      ..style       = PaintingStyle.stroke;

    // Outer boundary in SVG coords
    final outerRect = Rect.fromLTWH(
      VenueConfig.svgMargin  * scaleX,
      VenueConfig.svgMargin  * scaleY,
      (VenueConfig.svgWidth  - 2 * VenueConfig.svgMargin) * scaleX,
      (VenueConfig.svgHeight - 2 * VenueConfig.svgMargin) * scaleY,
    );

    canvas.drawRect(outerRect, floorPaint);
    canvas.drawRect(outerRect, wallPaint);

    // ── Hall Divider at X = 9.5m ────────────────────────────────────────
    final divX9_5 = _toScreen(const Offset(9.5, 0));
    final divXTop = _toScreen(const Offset(9.5, VenueConfig.venueHeightMetres));
    canvas.drawLine(divX9_5, divXTop, dividerPaint);

    // ── Entrance gap in south wall at X = 8.5–10.5 ────────────────────
    // (painted over the outer rect edge to simulate an opening)
    final gapPaint = Paint()
      ..color       = const Color(0xFFF5F0E8)
      ..strokeWidth = 12 * scaleX
      ..style       = PaintingStyle.stroke;
    canvas.drawLine(
      _toScreen(const Offset(8.5,  0)),
      _toScreen(const Offset(10.5, 0)),
      gapPaint,
    );

    // ── Exhibit boxes ────────────────────────────────────────────────────
    _drawExhibitBox(canvas, const Offset(1.0, 4.0), const Offset(5.0, 8.0),
        'Hall A\nExhibit 1', const Color(0xFFFFF3CD));
    _drawExhibitBox(canvas, const Offset(1.0, 0.5), const Offset(5.0, 3.0),
        'Hall A\nExhibit 2', const Color(0xFFFFF3CD));
    _drawExhibitBox(canvas, const Offset(10.5, 4.0), const Offset(14.5, 8.0),
        'Hall B\nExhibit 1', const Color(0xFFD4EDDA));
    _drawExhibitBox(canvas, const Offset(10.5, 0.5), const Offset(14.5, 3.0),
        'Hall B\nExhibit 2', const Color(0xFFD4EDDA));

    // ── Hall labels ──────────────────────────────────────────────────────
    _drawLabel(canvas, _toScreen(const Offset(4.5, 10.5)), 'HALL A',
        fontSize: 14, bold: true, color: const Color(0xFF5A4500));
    _drawLabel(canvas, _toScreen(const Offset(15.0, 10.5)), 'HALL B',
        fontSize: 14, bold: true, color: const Color(0xFF1A5C30));

    // ── Entrance label ───────────────────────────────────────────────────
    _drawLabel(canvas, _toScreen(const Offset(9.5, -0.5)), 'ENTRANCE',
        fontSize: 10, bold: false, color: const Color(0xFF888888));

    // ── Scale bar (2m = 2 * pxPerMetreX * scaleX pixels) ────────────────
    _drawScaleBar(canvas, size);
  }

  void _drawExhibitBox(Canvas canvas, Offset realTL, Offset realBR,
      String label, Color fill) {
    final tl = _toScreen(realTL);
    final br = _toScreen(realBR);
    final rect = Rect.fromPoints(tl, br);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(4 * scaleX)),
      Paint()..color = fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(4 * scaleX)),
      Paint()
        ..color       = fill.withValues(alpha: 0.9)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1.5 * scaleX,
    );

    final centre = Offset((tl.dx + br.dx) / 2, (tl.dy + br.dy) / 2);
    _drawLabel(canvas, centre, label,
        fontSize: 9, bold: false, color: const Color(0xFF333333));
  }

  void _drawScaleBar(Canvas canvas, Size size) {
    final barPaint = Paint()
      ..color       = AppTheme.textPrimary
      ..strokeWidth = 2;
    // 2 metre bar at bottom-right
    final rightM   = _toScreen(const Offset(18.0, 0.5));
    final leftM    = _toScreen(const Offset(16.0, 0.5));
    canvas.drawLine(leftM, rightM, barPaint);
    canvas.drawLine(
        leftM  - Offset(0, 4 * scaleY), leftM  + Offset(0, 4 * scaleY), barPaint);
    canvas.drawLine(
        rightM - Offset(0, 4 * scaleY), rightM + Offset(0, 4 * scaleY), barPaint);
    _drawLabel(
        canvas, Offset((leftM.dx + rightM.dx) / 2, leftM.dy - 10 * scaleY),
        '2m', fontSize: 9, bold: false, color: AppTheme.textSecondary);
  }

  // ──────────────────────────────────────────────────────────────────────
  // 2. Debug Grid
  // ──────────────────────────────────────────────────────────────────────
  void _drawDebugGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color       = Colors.red.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;

    // Vertical lines every 2m (X axis)
    for (double x = 0; x <= VenueConfig.venueWidthMetres; x += 2) {
      final top    = _toScreen(Offset(x, VenueConfig.venueHeightMetres));
      final bottom = _toScreen(Offset(x, 0));
      canvas.drawLine(top, bottom, gridPaint);
      _drawLabel(canvas, bottom + const Offset(0, 6),
          '${x.toInt()}', fontSize: 8, bold: false, color: Colors.red);
    }

    // Horizontal lines every 2m (Y axis) — use size.width as line endpoint
    for (double y = 0; y <= VenueConfig.venueHeightMetres; y += 2) {
      final left  = _toScreen(Offset(0, y));
      final right = _toScreen(Offset(VenueConfig.venueWidthMetres, y));
      canvas.drawLine(left, right, gridPaint);
      _drawLabel(canvas, left - const Offset(14, 0),
          '${y.toInt()}', fontSize: 8, bold: false, color: Colors.red);
    }

    // Origin label
    _drawLabel(canvas, _toScreen(Offset.zero) + const Offset(4, -14),
        '(0,0)', fontSize: 8, bold: false, color: Colors.red);
  }

  // ──────────────────────────────────────────────────────────────────────
  // 3. Beacon markers
  // ──────────────────────────────────────────────────────────────────────
  void _drawBeaconMarkers(Canvas canvas, Size size) {
    for (final entry in VenueConfig.beaconPositions.entries) {
      final uuid      = entry.key;
      final realPos   = entry.value;
      final screen    = _toScreen(realPos);
      final isDetected = detectedBeacons.containsKey(uuid);
      final isNear    = detectedBeacons[uuid]?.isNear ?? false;
      final name      = VenueConfig.beaconNames[uuid] ?? 'Beacon';

      // Proximity circle (only when near)
      if (isNear) {
        canvas.drawCircle(
          screen,
          VenueConfig.pxPerMetreX * scaleX * 2.5, // 2.5m radius
          Paint()
            ..color = AppTheme.accentColor.withValues(alpha: 0.15)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          screen,
          VenueConfig.pxPerMetreX * scaleX * 2.5,
          Paint()
            ..color       = AppTheme.accentColor.withValues(alpha: 0.5)
            ..style       = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }

      // Diamond shape
      final diamondSize = 9.0 * scaleX;
      final path = Path()
        ..moveTo(screen.dx, screen.dy - diamondSize)
        ..lineTo(screen.dx + diamondSize, screen.dy)
        ..lineTo(screen.dx, screen.dy + diamondSize)
        ..lineTo(screen.dx - diamondSize, screen.dy)
        ..close();

      canvas.drawPath(
        path,
        Paint()
          ..color = isDetected
              ? (isNear ? AppTheme.accentColor : AppTheme.primaryColor)
              : Colors.grey.shade400,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color       = Colors.white
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Short label below
      _drawLabel(
        canvas,
        screen + Offset(0, diamondSize + 10),
        name,
        fontSize: 9,
        bold: isDetected,
        color: isDetected ? AppTheme.primaryColor : Colors.grey,
      );

      // RSSI label if detected
      if (isDetected) {
        final b    = detectedBeacons[uuid]!;
        final dist = b.distanceMetres.toStringAsFixed(1);
        _drawLabel(
          canvas,
          screen + Offset(0, diamondSize + 22),
          '${dist}m',
          fontSize: 8,
          bold: false,
          color: AppTheme.textSecondary,
        );
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // 4. User dot
  // ──────────────────────────────────────────────────────────────────────
  void _drawUserDot(Canvas canvas, Offset realPos) {
    final screen = _toScreen(realPos);

    // Outer pulse ring
    canvas.drawCircle(
      screen,
      20 * scaleX,
      Paint()
        ..color = AppTheme.primaryColor.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    // Mid ring
    canvas.drawCircle(
      screen,
      13 * scaleX,
      Paint()
        ..color = AppTheme.primaryColor.withValues(alpha: 0.30)
        ..style = PaintingStyle.fill,
    );
    // Solid dot
    canvas.drawCircle(
      screen,
      8 * scaleX,
      Paint()..color = AppTheme.primaryColor,
    );
    // White centre
    canvas.drawCircle(
      screen,
      3.5 * scaleX,
      Paint()..color = Colors.white,
    );
    // Border
    canvas.drawCircle(
      screen,
      8 * scaleX,
      Paint()
        ..color       = Colors.white
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── Heading arrow ────────────────────────────────────────────────────
    final arrowLen = 18.0 * scaleX;
    final rad = heading * math.pi / 180.0;
    // Heading 0=north (+Y in real world) → up on screen (−Y in screen coords)
    // VenueConfig Y increases upward, so north on screen is decreasing dy.
    final arrowTip = Offset(
      screen.dx + arrowLen * math.sin(rad),
      screen.dy - arrowLen * math.cos(rad),
    );
    canvas.drawLine(
      screen,
      arrowTip,
      Paint()
        ..color       = Colors.white
        ..strokeWidth = 2.5 * scaleX
        ..strokeCap   = StrokeCap.round,
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Text helper
  // ──────────────────────────────────────────────────────────────────────
  void _drawLabel(
    Canvas canvas,
    Offset centre,
    String text, {
    double fontSize = 11,
    bool bold = false,
    Color color = AppTheme.textPrimary,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color:      color,
          fontSize:   fontSize * scaleX.clamp(0.6, 1.4),
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          height:     1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign:     TextAlign.center,
    )..layout();
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(IndoorMapPainter old) =>
      old.userPosition    != userPosition    ||
      old.detectedBeacons != detectedBeacons ||
      old.showGrid        != showGrid        ||
      old.heading         != heading         ||
      old.renderedSize    != renderedSize;
}
