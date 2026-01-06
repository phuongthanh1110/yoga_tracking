/// Advanced smoothing system for retargeting with multiple techniques:
/// - Velocity-based adaptive smoothing
/// - Quaternion temporal continuity
/// - Outlier detection and rejection
/// - Adaptive interpolation factors

import 'dart:math' as math;
import 'math_types.dart';
import 'one_euro_filter.dart';

/// Advanced smoothing configuration
class SmoothingConfig {
  const SmoothingConfig({
    this.enableVelocityAdaptive = true,
    this.enableQuaternionSmoothing = true,
    this.enableOutlierRejection = true,
    this.baseInterpolationFactor = 0.5,
    this.minInterpolationFactor = 0.1,
    this.maxInterpolationFactor = 0.9,
    this.velocityThreshold = 0.1,
    this.outlierThreshold = 3.0, // Standard deviations
    // Hand-specific smoothing config
    this.handBaseInterpolationFactor = 0.7, // Higher for hands
    this.handMinInterpolationFactor = 0.3,
    this.handMaxInterpolationFactor = 0.85,
  });

  final bool enableVelocityAdaptive;
  final bool enableQuaternionSmoothing;
  final bool enableOutlierRejection;
  final double baseInterpolationFactor;
  final double minInterpolationFactor;
  final double maxInterpolationFactor;
  final double velocityThreshold;
  final double outlierThreshold;
  // Hand-specific interpolation factors
  final double handBaseInterpolationFactor;
  final double handMinInterpolationFactor;
  final double handMaxInterpolationFactor;
}

/// Quaternion smoother with temporal continuity and velocity-based adaptation
class QuaternionSmoother {
  QuaternionSmoother({
    this.config = const SmoothingConfig(),
  });

  final SmoothingConfig config;
  Quat? _prevQuat;
  double? _prevTime;
  final List<double> _recentAngularVelocities = [];

  /// Get recent angular velocities for adaptive interpolation
  List<double> getRecentVelocities() => List.from(_recentAngularVelocities);

  /// Smooth quaternion with temporal continuity and velocity adaptation
  Quat smooth(double t, Quat targetQuat) {
    if (_prevQuat == null || _prevTime == null) {
      _prevQuat = Quat.clone(targetQuat);
      _prevTime = t;
      return targetQuat;
    }

    final dt = t - _prevTime!;
    if (dt <= 0) {
      return _prevQuat!;
    }

    // Check for quaternion flip (temporal continuity)
    Quat adjustedTarget = Quat.clone(targetQuat);
    if (config.enableQuaternionSmoothing) {
      final dot = _prevQuat!.x * targetQuat.x +
          _prevQuat!.y * targetQuat.y +
          _prevQuat!.z * targetQuat.z +
          _prevQuat!.w * targetQuat.w;
      if (dot < 0) {
        // Flip quaternion to maintain continuity
        adjustedTarget = Quat(
          -targetQuat.x,
          -targetQuat.y,
          -targetQuat.z,
          -targetQuat.w,
        );
      }
    }

    // Calculate angular velocity
    final prevInv =
        Quat(-_prevQuat!.x, -_prevQuat!.y, -_prevQuat!.z, _prevQuat!.w);
    final deltaQuat = Quat.clone(adjustedTarget)..multiply(prevInv);
    final angularVelocity = _quaternionToAngularVelocity(deltaQuat, dt);

    // Track recent velocities for adaptive smoothing
    if (config.enableVelocityAdaptive) {
      _recentAngularVelocities.add(angularVelocity);
      if (_recentAngularVelocities.length > 10) {
        _recentAngularVelocities.removeAt(0);
      }
    }

    // Adaptive interpolation factor based on velocity
    double interpolationFactor = config.baseInterpolationFactor;
    if (config.enableVelocityAdaptive && _recentAngularVelocities.isNotEmpty) {
      if (angularVelocity > config.velocityThreshold) {
        // Fast movement: use higher interpolation factor (more responsive)
        interpolationFactor = math.min(
          config.baseInterpolationFactor * 1.5,
          config.maxInterpolationFactor,
        );
      } else {
        // Slow movement: use lower interpolation factor (smoother)
        interpolationFactor = math.max(
          config.baseInterpolationFactor * 0.7,
          config.minInterpolationFactor,
        );
      }
    }

    // Slerp interpolation
    final smoothed = Quat.clone(_prevQuat!)
      ..slerp(adjustedTarget, interpolationFactor)
      ..normalized();

    _prevQuat = smoothed;
    _prevTime = t;

    return smoothed;
  }

  /// Convert quaternion delta to angular velocity (rad/s)
  double _quaternionToAngularVelocity(Quat deltaQuat, double dt) {
    if (dt <= 0) return 0.0;

    // Extract rotation angle from quaternion
    final angle = 2.0 * math.acos(deltaQuat.w.clamp(-1.0, 1.0));
    return angle / dt;
  }

  void reset() {
    _prevQuat = null;
    _prevTime = null;
    _recentAngularVelocities.clear();
  }
}

/// Position smoother with outlier rejection and velocity adaptation
class PositionSmoother {
  PositionSmoother({
    SmoothingConfig? config,
    OneEuroFilterVector3? oneEuroFilter,
  })  : config = config ?? const SmoothingConfig(),
        _oneEuroFilter = oneEuroFilter ??
            OneEuroFilterVector3(
              minCutoff: 0.004,
              beta: 1.0,
              dCutoff: 1.0,
            );

  final SmoothingConfig config;
  final OneEuroFilterVector3 _oneEuroFilter;
  Vec3? _prevPosition;
  double? _prevTime;
  final List<double> _recentVelocities = [];
  final List<Vec3> _recentPositions = [];

  /// Smooth position with outlier rejection and velocity adaptation
  Vec3 smooth(double t, Vec3 targetPosition) {
    // Outlier rejection
    if (config.enableOutlierRejection && _recentPositions.isNotEmpty) {
      if (!_isValidPosition(targetPosition)) {
        // Use previous position if current is outlier
        return _prevPosition ?? targetPosition;
      }
    }

    // OneEuro filter for basic smoothing
    final filtered = _oneEuroFilter.filter(t, targetPosition);

    // Track recent positions and velocities
    _recentPositions.add(Vec3.clone(filtered));
    if (_recentPositions.length > 10) {
      _recentPositions.removeAt(0);
    }

    if (_prevPosition != null && _prevTime != null) {
      final dt = t - _prevTime!;
      if (dt > 0) {
        final velocity = Vec3.clone(filtered)
          ..sub(_prevPosition!)
          ..scale(1.0 / dt);
        final speed = velocity.length;

        _recentVelocities.add(speed);
        if (_recentVelocities.length > 10) {
          _recentVelocities.removeAt(0);
        }
      }
    }

    _prevPosition = Vec3.clone(filtered);
    _prevTime = t;

    return filtered;
  }

  /// Check if position is valid (not an outlier)
  bool _isValidPosition(Vec3 position) {
    if (_recentPositions.length < 3) return true;

    // Calculate mean and standard deviation
    final mean = Vec3(0, 0, 0);
    for (final pos in _recentPositions) {
      mean.x += pos.x;
      mean.y += pos.y;
      mean.z += pos.z;
    }
    mean.x /= _recentPositions.length;
    mean.y /= _recentPositions.length;
    mean.z /= _recentPositions.length;

    // Calculate standard deviation
    double variance = 0.0;
    for (final pos in _recentPositions) {
      final diff = Vec3.clone(pos)..sub(mean);
      variance += diff.lengthSq;
    }
    final stdDev = math.sqrt(variance / _recentPositions.length);

    // Check if current position is within threshold
    final diff = Vec3.clone(position)..sub(mean);
    final distance = diff.length;

    return distance <= (stdDev * config.outlierThreshold);
  }

  void reset() {
    _prevPosition = null;
    _prevTime = null;
    _recentVelocities.clear();
    _recentPositions.clear();
    _oneEuroFilter.reset();
  }
}

/// Bone rotation smoother with advanced techniques
class BoneRotationSmoother {
  BoneRotationSmoother({
    SmoothingConfig? config,
  }) : config = config ?? const SmoothingConfig();

  final SmoothingConfig config;
  final Map<String, QuaternionSmoother> _quatSmoothers = {};
  final Map<String, PositionSmoother> _posSmoothers = {};

  /// Smooth bone rotation
  Quat smoothRotation(String boneName, double t, Quat targetQuat) {
    final smoother = _quatSmoothers.putIfAbsent(
      boneName,
      () => QuaternionSmoother(config: config),
    );
    return smoother.smooth(t, targetQuat);
  }

  /// Smooth bone position
  Vec3 smoothPosition(String boneName, double t, Vec3 targetPos) {
    final smoother = _posSmoothers.putIfAbsent(
      boneName,
      () => PositionSmoother(config: config),
    );
    return smoother.smooth(t, targetPos);
  }

  /// Get adaptive interpolation factor for a bone based on its velocity
  double getAdaptiveInterpolationFactor(String boneName) {
    final quatSmoother = _quatSmoothers[boneName];
    if (quatSmoother == null) {
      // Use hand-specific factor if it's a hand bone
      return _isHandBone(boneName)
          ? config.handBaseInterpolationFactor
          : config.baseInterpolationFactor;
    }

    // Access velocities through a getter method
    final velocities = quatSmoother.getRecentVelocities();
    final baseFactor = _isHandBone(boneName)
        ? config.handBaseInterpolationFactor
        : config.baseInterpolationFactor;
    final minFactor = _isHandBone(boneName)
        ? config.handMinInterpolationFactor
        : config.minInterpolationFactor;
    final maxFactor = _isHandBone(boneName)
        ? config.handMaxInterpolationFactor
        : config.maxInterpolationFactor;

    // Create temporary config with hand-specific values
    final handConfig = SmoothingConfig(
      enableVelocityAdaptive: config.enableVelocityAdaptive,
      enableQuaternionSmoothing: config.enableQuaternionSmoothing,
      enableOutlierRejection: config.enableOutlierRejection,
      baseInterpolationFactor: baseFactor,
      minInterpolationFactor: minFactor,
      maxInterpolationFactor: maxFactor,
      velocityThreshold: config.velocityThreshold,
      outlierThreshold: config.outlierThreshold,
      handBaseInterpolationFactor: config.handBaseInterpolationFactor,
      handMinInterpolationFactor: config.handMinInterpolationFactor,
      handMaxInterpolationFactor: config.handMaxInterpolationFactor,
    );

    return _calculateAdaptiveFactor(velocities, handConfig);
  }

  /// Check if bone is part of hand (hand or finger bones)
  bool _isHandBone(String boneName) {
    return boneName.contains('Hand') &&
        (boneName.contains('Thumb') ||
            boneName.contains('Index') ||
            boneName.contains('Middle') ||
            boneName.contains('Ring') ||
            boneName.contains('Pinky') ||
            boneName == 'LeftHand' ||
            boneName == 'RightHand');
  }

  void reset() {
    for (final smoother in _quatSmoothers.values) {
      smoother.reset();
    }
    for (final smoother in _posSmoothers.values) {
      smoother.reset();
    }
  }

  void resetBone(String boneName) {
    _quatSmoothers[boneName]?.reset();
    _posSmoothers[boneName]?.reset();
  }
}

/// Helper to calculate adaptive interpolation factor from velocities
double _calculateAdaptiveFactor(
  List<double> velocities,
  SmoothingConfig config,
) {
  if (velocities.isEmpty) {
    return config.baseInterpolationFactor;
  }

  final avgVelocity = velocities.reduce((a, b) => a + b) / velocities.length;

  if (avgVelocity > config.velocityThreshold) {
    // Fast movement: more responsive
    return math.min(
      config.baseInterpolationFactor * 1.5,
      config.maxInterpolationFactor,
    );
  } else {
    // Slow movement: smoother
    return math.max(
      config.baseInterpolationFactor * 0.7,
      config.minInterpolationFactor,
    );
  }
}
