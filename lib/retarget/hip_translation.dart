import 'math_types.dart';

/// Root motion helper ported from hip_translation.js
class RootMotionHelper {
  static const double _zDamper = 1.5;
  static const int _leftHipIdx = 23;
  static const int _rightHipIdx = 24;

  int _width = 640;
  int _height = 480;
  double _modelHipSpan = 100;
  Vec3? _origin;
  double _currentFactor = 1;
  final Vec3 translation = Vec3();

  void updateModelMetrics({required double hipSpan}) {
    _modelHipSpan = hipSpan;
  }

  void reset({int width = 640, int height = 480}) {
    _width = width;
    _height = height;
    _origin = null;
    _currentFactor = 1;
    translation.set(0, 0, 0);
  }

  Vec3? computeTranslation(List<dynamic> poseLandmarks) {
    if (poseLandmarks.isEmpty) return null;
    final leftHip = _toVec(poseLandmarks[_leftHipIdx]);
    final rightHip = _toVec(poseLandmarks[_rightHipIdx]);
    if (leftHip == null || rightHip == null) return null;

    final hipAvg = _average(leftHip, rightHip);
    if (hipAvg == null) return null;

    if (_origin == null) {
      _origin = Vec3.clone(hipAvg);
      translation.set(0, 0, 0);
      return translation;
    }

    final pixelDistance = leftHip.distanceTo(rightHip);
    final xDiff = (leftHip.x - rightHip.x).abs();
    final zDiff = (leftHip.z - rightHip.z).abs();
    double targetFactor = _currentFactor;
    if (pixelDistance > 20 && xDiff > zDiff) {
      targetFactor = _modelHipSpan / pixelDistance;
    }
    _currentFactor = _lerp(_currentFactor, targetFactor, 0.05);

    final delta = Vec3.clone(hipAvg)..sub(_origin!);
    translation.set(
      delta.x * _currentFactor,
      -delta.y * _currentFactor,
      delta.z * _currentFactor * _zDamper,
    );
    return translation;
  }

  Vec3? _toVec(dynamic lm) {
    if (lm == null) return null;
    return Vec3(
      (lm.x as num).toDouble() * _width,
      (lm.y as num).toDouble() * _height,
      (lm.z as num).toDouble() * _width,
    );
  }

  Vec3? _average(Vec3 a, Vec3 b) {
    return Vec3(
      (a.x + b.x) * 0.5,
      (a.y + b.y) * 0.5,
      (a.z + b.z) * 0.5,
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}
