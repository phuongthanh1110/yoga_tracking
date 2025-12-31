// Lightweight One Euro filter implementation (math only, no 3D engine types).
// Inspired by SystemAnimatorOnline's adaptive filtering approach.

import 'math_types.dart';

const double _twoPi = 2 * 3.1415926535897932;

class OneEuroFilter {
  OneEuroFilter({
    this.minCutoff = 0.004,
    double beta = 1.0,
    this.dCutoff = 1.0,
  }) : _beta = beta;

  final double minCutoff;
  double _beta;
  final double dCutoff;

  /// Allows dynamically adjusting beta for adaptive filtering.
  /// Higher beta = more responsive but potentially jittery.
  /// Lower beta = smoother but slower response.
  set beta(double value) => _beta = value;
  double get beta => _beta;

  double? _xPrev;
  double _dxPrev = 0;
  double? _tPrev;

  double filter(double t, double x) {
    if (_xPrev == null || _tPrev == null) {
      _xPrev = x;
      _tPrev = t;
      return x;
    }

    final te = t - _tPrev!;
    if (te <= 0) {
      return _xPrev!;
    }

    final aD = _smoothingFactor(te, dCutoff);
    final dx = (x - _xPrev!) / te;
    final dxHat = _exponentialSmoothing(aD, dx, _dxPrev);

    final cutoff = minCutoff + _beta * dxHat.abs();
    final a = _smoothingFactor(te, cutoff);
    final xHat = _exponentialSmoothing(a, x, _xPrev!);

    _xPrev = xHat;
    _dxPrev = dxHat;
    _tPrev = t;
    return xHat;
  }

  void reset() {
    _xPrev = null;
    _dxPrev = 0;
    _tPrev = null;
  }

  double _smoothingFactor(double te, double cutoff) {
    if (cutoff <= 0) return 1;
    final r = _twoPi * cutoff * te;
    return r / (r + 1);
  }

  double _exponentialSmoothing(double a, double x, double prevX) {
    return a * x + (1 - a) * prevX;
  }
}

class OneEuroFilterVector3 {
  OneEuroFilterVector3({
    double minCutoff = 0.004,
    double beta = 1.0,
    double dCutoff = 1.0,
  })  : _fx = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff),
        _fy = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff),
        _fz = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff),
        _result = Vec3();

  final OneEuroFilter _fx;
  final OneEuroFilter _fy;
  final OneEuroFilter _fz;
  final Vec3 _result;

  /// Updates beta for all three axes (for adaptive filtering).
  set beta(double value) {
    _fx.beta = value;
    _fy.beta = value;
    _fz.beta = value;
  }

  Vec3 filter(double t, Vec3 vec) {
    _result
      ..x = _fx.filter(t, vec.x)
      ..y = _fy.filter(t, vec.y)
      ..z = _fz.filter(t, vec.z);
    return _result;
  }

  void reset() {
    _fx.reset();
    _fy.reset();
    _fz.reset();
  }
}
