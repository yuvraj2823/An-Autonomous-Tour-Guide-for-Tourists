import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'madgwick_filter.dart';

/// A single pedestrian step event emitted by [PdrEngine].
class PdrStep {
  /// Compass heading in degrees (0 = north, 90 = east).
  final double headingDeg;

  /// Estimated step length in metres (Weinberg model or fixed).
  final double stepLength;

  const PdrStep({required this.headingDeg, required this.stepLength});
}

/// Pedestrian Dead Reckoning engine.
///
/// Subscribes to phone IMU streams, runs the Madgwick filter for heading,
/// detects walking steps via accelerometer peak detection, and emits
/// [PdrStep] events for each step.
///
/// Analogy: a ship's navigator who knows speed and direction — no GPS needed,
/// just "I took 10 steps north" → dead-reckoning position.
class PdrEngine {
  // ── Madgwick filter (Stage 2) ────────────────────────────────────────────
  final MadgwickFilter _madgwick;

  // ── Sensor subscriptions ─────────────────────────────────────────────────
  StreamSubscription<AccelerometerEvent>?  _accelSub;
  StreamSubscription<GyroscopeEvent>?      _gyroSub;
  StreamSubscription<MagnetometerEvent>?   _magSub;

  // ── Latest sensor values ─────────────────────────────────────────────────
  double _ax = 0, _ay = 0, _az = 9.8;
  double _gx = 0, _gy = 0, _gz = 0;
  double _mx = 0, _my = 0, _mz = 0;
  bool   _hasMag = false;

  // ── Step detection ───────────────────────────────────────────────────────
  double _smoothMag = 9.8;    // low-pass filtered acceleration magnitude
  bool   _peakUp    = false;  // are we in the rising phase of a step?
  int    _stepCount = 0;

  // Thresholds — tune for walking gait (units: m/s² including gravity)
  static const double _stepUpThresh   = 10.5;  // rising edge
  static const double _stepDownThresh = 9.2;   // falling edge
  static const double _lpAlpha        = 0.25;  // low-pass coefficient

  // Fixed step length (metres). Weinberg's formula [L = k * (amax-amin)^0.25]
  // requires calibration; fixed 0.75m is accurate enough for this use case.
  static const double _stepLength = 0.75;

  // ── Step stream ──────────────────────────────────────────────────────────
  final StreamController<PdrStep> _stepCtrl =
      StreamController<PdrStep>.broadcast();

  Stream<PdrStep> get stepStream => _stepCtrl.stream;

  PdrEngine({double beta = 0.033, double samplePeriod = 0.02})
      : _madgwick = MadgwickFilter(beta: beta, samplePeriod: samplePeriod);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void start() {
    // Accelerometer: provides step detection + Madgwick correction
    _accelSub = accelerometerEventStream().listen(_onAccel);

    // Gyroscope: drives Madgwick integration
    _gyroSub = gyroscopeEventStream().listen(_onGyro);

    // Magnetometer: optional — gives absolute north reference
    try {
      _magSub = magnetometerEventStream().listen(_onMag);
    } catch (_) {
      debugPrint('PdrEngine: magnetometer not available — using 6-DOF mode');
    }
  }

  void stop() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _magSub?.cancel();
    _accelSub = null; _gyroSub = null; _magSub = null;
    _hasMag   = false;
  }

  void dispose() {
    stop();
    _stepCtrl.close();
  }

  // ── Sensor callbacks ──────────────────────────────────────────────────────

  void _onAccel(AccelerometerEvent e) {
    _ax = e.x; _ay = e.y; _az = e.z;

    // Update Madgwick with latest IMU data
    if (_hasMag) {
      _madgwick.update9Dof(
        ax: _ax, ay: _ay, az: _az,
        gx: _gx, gy: _gy, gz: _gz,
        mx: _mx, my: _my, mz: _mz,
      );
    } else {
      _madgwick.update6Dof(
        ax: _ax, ay: _ay, az: _az,
        gx: _gx, gy: _gy, gz: _gz,
      );
    }

    _detectStep();
  }

  void _onGyro(GyroscopeEvent e) {
    _gx = e.x; _gy = e.y; _gz = e.z;
  }

  void _onMag(MagnetometerEvent e) {
    _mx = e.x; _my = e.y; _mz = e.z;
    _hasMag = true;
  }

  // ── Step detection (peak detection on smoothed magnitude) ─────────────────

  void _detectStep() {
    final mag = sqrt(_ax * _ax + _ay * _ay + _az * _az);

    // Low-pass filter — removes footstep vibration noise
    _smoothMag = _lpAlpha * mag + (1 - _lpAlpha) * _smoothMag;

    // Rising edge (start of step)
    if (!_peakUp && _smoothMag > _stepUpThresh) {
      _peakUp = true;
    }
    // Falling edge (step complete)
    else if (_peakUp && _smoothMag < _stepDownThresh) {
      _peakUp = false;
      _stepCount++;
      if (!_stepCtrl.isClosed) {
        _stepCtrl.add(PdrStep(
          headingDeg: _madgwick.headingDegrees,
          stepLength: _stepLength,
        ));
      }
    }
  }

  // ── Accessors ─────────────────────────────────────────────────────────────
  int    get stepCount        => _stepCount;
  double get currentHeading   => _madgwick.headingDegrees;
  bool   get isMagAvailable   => _hasMag;
}
