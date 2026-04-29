import 'dart:math';

/// Madgwick AHRS filter — Stage 2 of the three-stage pipeline.
///
/// Fuses accelerometer + gyroscope + optional magnetometer streams into a
/// stable orientation quaternion from which we extract a heading angle.
///
/// Reference:
///   Madgwick, S.O.H. (2010) "An efficient orientation filter for inertial
///   and inertial/magnetic sensor arrays"
///
/// Analogy: if RSSI is a jittery thermometer, the gyroscope is an accurate
/// but drifting compass, and the accelerometer/magnetometer correct that drift.
/// Madgwick blends them at exactly the right weight.
class MadgwickFilter {
  /// Filter gain β — how strongly accelerometer/magnetometer pull the estimate.
  /// Higher β = faster convergence, more noise. Range: 0.01–0.1.
  final double beta;

  /// Sample period in seconds (1 / sensor_hz). At 50 Hz → 0.02.
  final double samplePeriod;

  // Internal orientation quaternion (w, x, y, z).
  double _q0 = 1.0, _q1 = 0.0, _q2 = 0.0, _q3 = 0.0;

  MadgwickFilter({this.beta = 0.033, this.samplePeriod = 0.02});

  // ── 9-DOF update (accel + gyro + magnetometer) ──────────────────────────

  /// All units: accel m/s² (or g), gyro rad/s, mag µT.
  void update9Dof({
    required double ax, required double ay, required double az,
    required double gx, required double gy, required double gz,
    required double mx, required double my, required double mz,
  }) {
    double q0 = _q0, q1 = _q1, q2 = _q2, q3 = _q3;

    // Normalise accelerometer
    double norm = sqrt(ax * ax + ay * ay + az * az);
    if (norm == 0) return;
    ax /= norm; ay /= norm; az /= norm;

    // Normalise magnetometer
    norm = sqrt(mx * mx + my * my + mz * mz);
    if (norm == 0) { update6Dof(ax: ax, ay: ay, az: az, gx: gx, gy: gy, gz: gz); return; }
    mx /= norm; my /= norm; mz /= norm;

    // Reference direction of Earth's magnetic field in world frame
    final hx = 2*mx*(0.5 - q2*q2 - q3*q3) + 2*my*(q1*q2 - q0*q3) + 2*mz*(q1*q3 + q0*q2);
    final hy = 2*mx*(q1*q2 + q0*q3) + 2*my*(0.5 - q1*q1 - q3*q3) + 2*mz*(q2*q3 - q0*q1);
    final hz = 2*mx*(q1*q3 - q0*q2) + 2*my*(q2*q3 + q0*q1) + 2*mz*(0.5 - q1*q1 - q2*q2);
    final bx = sqrt(hx * hx + hy * hy);
    final bz = hz;

    // Gradient descent corrective step (objective function gradient)
    double s0 =
        -2*q2*(2*q1*q3 - 2*q0*q2 - ax) +
        2*q1*(2*q0*q1 + 2*q2*q3 - ay) -
        2*bz*q2*(2*bx*(0.5 - q2*q2 - q3*q3) + 2*bz*(q1*q3 - q0*q2) - mx) +
        (-2*bx*q3 + 2*bz*q1)*(2*bx*(q1*q2 - q0*q3) + 2*bz*(q0*q1 + q2*q3) - my) +
        2*bx*q2*(2*bx*(q0*q2 + q1*q3) + 2*bz*(0.5 - q1*q1 - q2*q2) - mz);

    double s1 =
        2*q3*(2*q1*q3 - 2*q0*q2 - ax) +
        2*q0*(2*q0*q1 + 2*q2*q3 - ay) -
        4*q1*(1 - 2*q1*q1 - 2*q2*q2 - az) +
        2*bz*q3*(2*bx*(0.5 - q2*q2 - q3*q3) + 2*bz*(q1*q3 - q0*q2) - mx) +
        (2*bx*q2 + 2*bz*q0)*(2*bx*(q1*q2 - q0*q3) + 2*bz*(q0*q1 + q2*q3) - my) +
        (2*bx*q3 - 4*bz*q1)*(2*bx*(q0*q2 + q1*q3) + 2*bz*(0.5 - q1*q1 - q2*q2) - mz);

    double s2 =
        -2*q0*(2*q1*q3 - 2*q0*q2 - ax) +
        2*q3*(2*q0*q1 + 2*q2*q3 - ay) -
        4*q2*(1 - 2*q1*q1 - 2*q2*q2 - az) +
        (-4*bx*q2 - 2*bz*q0)*(2*bx*(0.5 - q2*q2 - q3*q3) + 2*bz*(q1*q3 - q0*q2) - mx) +
        (2*bx*q1 + 2*bz*q3)*(2*bx*(q1*q2 - q0*q3) + 2*bz*(q0*q1 + q2*q3) - my) +
        (2*bx*q0 - 4*bz*q2)*(2*bx*(q0*q2 + q1*q3) + 2*bz*(0.5 - q1*q1 - q2*q2) - mz);

    double s3 =
        2*q1*(2*q1*q3 - 2*q0*q2 - ax) +
        2*q2*(2*q0*q1 + 2*q2*q3 - ay) +
        (-4*bx*q3 + 2*bz*q1)*(2*bx*(0.5 - q2*q2 - q3*q3) + 2*bz*(q1*q3 - q0*q2) - mx) +
        (-2*bx*q0 + 2*bz*q2)*(2*bx*(q1*q2 - q0*q3) + 2*bz*(q0*q1 + q2*q3) - my) +
        2*bx*q1*(2*bx*(q0*q2 + q1*q3) + 2*bz*(0.5 - q1*q1 - q2*q2) - mz);

    norm = sqrt(s0*s0 + s1*s1 + s2*s2 + s3*s3);
    if (norm == 0) return;
    s0 /= norm; s1 /= norm; s2 /= norm; s3 /= norm;

    _integrateAndNormalise(q0, q1, q2, q3, gx, gy, gz, s0, s1, s2, s3);
  }

  // ── 6-DOF update (accel + gyro only, no magnetometer) ───────────────────

  void update6Dof({
    required double ax, required double ay, required double az,
    required double gx, required double gy, required double gz,
  }) {
    double q0 = _q0, q1 = _q1, q2 = _q2, q3 = _q3;

    double norm = sqrt(ax * ax + ay * ay + az * az);
    if (norm == 0) return;
    ax /= norm; ay /= norm; az /= norm;

    // Gradient for 6-DOF (gravity reference only)
    double s0 = -2*q2*(2*(q1*q3 - q0*q2) - ax) +
                 2*q1*(2*(q0*q1 + q2*q3) - ay);
    double s1 =  2*q3*(2*(q1*q3 - q0*q2) - ax) +
                 2*q0*(2*(q0*q1 + q2*q3) - ay) -
                 4*q1*(1 - 2*(q1*q1 + q2*q2) - az);
    double s2 = -2*q0*(2*(q1*q3 - q0*q2) - ax) +
                 2*q3*(2*(q0*q1 + q2*q3) - ay) -
                 4*q2*(1 - 2*(q1*q1 + q2*q2) - az);
    double s3 =  2*q1*(2*(q1*q3 - q0*q2) - ax) +
                 2*q2*(2*(q0*q1 + q2*q3) - ay);

    final norm2 = sqrt(s0*s0 + s1*s1 + s2*s2 + s3*s3);
    if (norm2 != 0) {
      s0 /= norm2; s1 /= norm2; s2 /= norm2; s3 /= norm2;
    }

    _integrateAndNormalise(q0, q1, q2, q3, gx, gy, gz, s0, s1, s2, s3);
  }

  void _integrateAndNormalise(
    double q0, double q1, double q2, double q3,
    double gx, double gy, double gz,
    double s0, double s1, double s2, double s3,
  ) {
    // Rate of change of quaternion from gyroscope
    final qDot0 = 0.5 * (-q1*gx - q2*gy - q3*gz) - beta * s0;
    final qDot1 = 0.5 * ( q0*gx + q2*gz - q3*gy) - beta * s1;
    final qDot2 = 0.5 * ( q0*gy - q1*gz + q3*gx) - beta * s2;
    final qDot3 = 0.5 * ( q0*gz + q1*gy - q2*gx) - beta * s3;

    // Integrate
    q0 += qDot0 * samplePeriod;
    q1 += qDot1 * samplePeriod;
    q2 += qDot2 * samplePeriod;
    q3 += qDot3 * samplePeriod;

    // Normalise
    final n = sqrt(q0*q0 + q1*q1 + q2*q2 + q3*q3);
    _q0 = q0 / n; _q1 = q1 / n; _q2 = q2 / n; _q3 = q3 / n;
  }

  // ── Output ───────────────────────────────────────────────────────────────

  /// Heading (yaw) in degrees, 0–360, clockwise from magnetic north.
  double get headingDegrees {
    final yaw = atan2(
      2 * (_q0*_q3 + _q1*_q2),
      1 - 2 * (_q2*_q2 + _q3*_q3),
    );
    return (yaw * 180.0 / pi + 360) % 360;
  }

  /// Pitch in degrees.
  double get pitchDegrees {
    final pitch = asin(2 * (_q0*_q2 - _q3*_q1));
    return pitch * 180.0 / pi;
  }

  void reset() { _q0 = 1.0; _q1 = 0.0; _q2 = 0.0; _q3 = 0.0; }
}
