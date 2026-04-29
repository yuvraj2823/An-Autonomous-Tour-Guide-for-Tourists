/// Standard Kalman Filter for 1-D signal smoothing (Stage 1 of the three-stage pipeline).
///
/// Used to smooth noisy BLE RSSI values over time.
///
/// Analogy: imagine you're trying to measure the temperature in a room but
/// your thermometer jiggles ±2°C every second. The Kalman filter keeps a
/// running "best estimate" and blends each new noisy reading into it — the
/// more uncertain it is, the more it trusts new data; the more stable, the
/// less it moves.
class KalmanFilter {
  double _estimate;
  double _errorCovariance;
  final double _q; // process noise — how fast the true value can change
  final double _r; // measurement noise — how unreliable the sensor readings are

  KalmanFilter({
    double initialEstimate = -70.0,
    double initialError    = 1.0,
    double? q,
    double? r,
  })  : _estimate        = initialEstimate,
        _errorCovariance = initialError,
        _q               = q ?? 0.02,
        _r               = r ?? 2.0;

  /// Feed a new raw measurement. Returns the updated (smoothed) estimate.
  double update(double measurement) {
    // PREDICT: we expect the error covariance to grow a little each step
    // (we become less certain as time passes).
    _errorCovariance += _q;

    // Kalman gain: how much do we trust the new measurement vs our estimate?
    // High gain → trust new data. Low gain → stick with current estimate.
    final double gain = _errorCovariance / (_errorCovariance + _r);

    // UPDATE: blend the estimate toward the new measurement.
    _estimate        += gain * (measurement - _estimate);

    // Our uncertainty shrinks after incorporating a new reading.
    _errorCovariance  = (1.0 - gain) * _errorCovariance;

    return _estimate;
  }

  /// Reset the filter (e.g. when a beacon re-appears after a timeout).
  void reset(double initialEstimate) {
    _estimate        = initialEstimate;
    _errorCovariance = 1.0;
  }

  double get currentEstimate => _estimate;
}
