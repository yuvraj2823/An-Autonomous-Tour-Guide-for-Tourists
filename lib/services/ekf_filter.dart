import 'dart:math';

/// Extended Kalman Filter for 2-D indoor positioning — Stage 3 pipeline.
///
/// State vector: [x, y] — real-world metres from venue south-west origin.
///
/// **Predict** — called on each PDR step:
///   New position = old + stepLength * [sin(heading), cos(heading)]
///   (sin for X/east, cos for Y/north — heading is compass-style 0=north)
///
/// **Update** — called on each BLE range measurement:
///   Nonlinear measurement model: d = sqrt((x-bx)² + (y-by)²)
///   Linearised via Jacobian → standard Kalman update.
///
/// **Hard reset** — called when user is within 2.5m of a known beacon:
///   Overrides state directly — eliminates accumulated PDR drift.
class EkfFilter {
  // ── State ─────────────────────────────────────────────────────────────────
  double _x, _y;
  bool   _initialised = false; // true after first BLE anchor or setInitialPosition

  // ── Error covariance P (2×2, stored as 4 doubles) ────────────────────────
  double _p00, _p01, _p10, _p11;

  // ── Noise parameters ─────────────────────────────────────────────────────
  final double _qVar; // process noise variance per step
  final double _rVar; // BLE measurement noise variance (metres²)

  EkfFilter({
    double initialX          = 0.0,
    double initialY          = 0.0,
    double processNoise      = 0.08, // ~28 cm std dev per step
    double measurementNoise  = 2.25, // ~1.5 m std dev for BLE distance
  })  : _x   = initialX,
        _y   = initialY,
        _p00 = 5.0, _p01 = 0.0, _p10 = 0.0, _p11 = 5.0,
        _qVar = processNoise,
        _rVar = measurementNoise;

  // ── Predict step ─────────────────────────────────────────────────────────

  /// Advance state by one pedestrian step.
  ///
  /// [headingDeg] — compass bearing in degrees (0 = north, 90 = east).
  /// [stepLength] — estimated step length in metres (~0.75 m).
  void predict(double headingDeg, double stepLength) {
    final rad = headingDeg * pi / 180.0;
    _x += stepLength * sin(rad); // east component
    _y += stepLength * cos(rad); // north component

    // Covariance prediction: P_k|k-1 = F*P*F^T + Q
    // F = identity (simple random-walk motion model), so P_k|k-1 = P + Q*I
    _p00 += _qVar;
    _p11 += _qVar;
  }

  // ── Measurement update ───────────────────────────────────────────────────

  /// Correct position using a BLE distance-to-beacon measurement.
  ///
  /// [beaconX], [beaconY] — known real-world beacon position (metres).
  /// [measuredDist]       — Kalman-smoothed BLE distance estimate (metres).
  void update(double beaconX, double beaconY, double measuredDist) {
    final dx = _x - beaconX;
    final dy = _y - beaconY;
    final predictedDist = sqrt(dx * dx + dy * dy);
    if (predictedDist < 0.01) return; // avoid divide-by-zero at exact match

    // Jacobian of h(x) = dist: H = [dx/dist, dy/dist]
    final h0 = dx / predictedDist;
    final h1 = dy / predictedDist;

    // Innovation covariance: S = H*P*H^T + R
    final hp0 = h0 * _p00 + h1 * _p10;
    final hp1 = h0 * _p01 + h1 * _p11;
    final s   = hp0 * h0 + hp1 * h1 + _rVar;
    if (s.abs() < 1e-9) return;

    // Kalman gain: K = P*H^T / S  (2×1 vector)
    final k0 = (_p00 * h0 + _p01 * h1) / s;
    final k1 = (_p10 * h0 + _p11 * h1) / s;

    // State update
    final innovation = measuredDist - predictedDist;
    _x += k0 * innovation;
    _y += k1 * innovation;

    // Covariance update: P = (I - K*H) * P
    final newP00 = (1 - k0 * h0) * _p00 - k0 * h1 * _p10;
    final newP01 = (1 - k0 * h0) * _p01 - k0 * h1 * _p11;
    final newP10 = -k1 * h0 * _p00 + (1 - k1 * h1) * _p10;
    final newP11 = -k1 * h0 * _p01 + (1 - k1 * h1) * _p11;
    _p00 = newP00; _p01 = newP01; _p10 = newP10; _p11 = newP11;
  }

  // ── Hard anchor correction ────────────────────────────────────────────────

  /// Snap position to a beacon's known location when user is ≤2.5m away.
  /// Also shrinks error covariance — we now know position precisely.
  void hardReset(double x, double y) {
    _x = x; _y = y;
    _initialised = true;
    // Tight covariance after hard anchor (~31 cm std dev)
    _p00 = 0.1; _p01 = 0.0; _p10 = 0.0; _p11 = 0.1;
  }

  // ── Accessors ─────────────────────────────────────────────────────────────
  double get x => _x;
  double get y => _y;

  /// Position uncertainty: average diagonal of P (metres std dev).
  double get positionStdDev => sqrt((_p00 + _p11) / 2.0);

  void setInitialPosition(double x, double y) {
    _x = x; _y = y;
    _initialised = true;
    _p00 = 5.0; _p01 = 0.0; _p10 = 0.0; _p11 = 5.0;
  }

  /// True once a BLE anchor or manual position has been set.
  bool get isInitialised => _initialised;
}
