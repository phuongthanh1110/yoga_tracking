import 'dart:math' as math;

import 'advanced_smoothing.dart';
import 'hip_translation.dart';
import 'math_types.dart';
import 'mixamo_mapping.dart';
import 'package:three_js/three_js.dart' as three;

const double _defaultVisibilityThreshold = 0.5;

/// Dart port of mixamo_retargeter.js using pure math types (Vec3/Quat).
/// Bone objects are expected to have `position` (x,y,z) and `quaternion` (x,y,z,w)
/// fields similar to Three.js Bone.
class MixamoRetargeter {
  MixamoRetargeter({
    required this.modelRoot,
    required Map<String, dynamic> bones,
    this.visibilityThreshold = _defaultVisibilityThreshold,
    SmoothingConfig? smoothingConfig,
    bool enableAdvancedSmoothing = true,
  })  : bones = Map.unmodifiable(bones),
        _smoothingConfig = smoothingConfig ?? const SmoothingConfig(),
        _enableAdvancedSmoothing = enableAdvancedSmoothing {
    _recomputeBindPose();
    if (_enableAdvancedSmoothing) {
      _boneSmoother = BoneRotationSmoother(config: _smoothingConfig);
    }
  }

  final dynamic modelRoot;
  final Map<String, dynamic> bones;
  final double visibilityThreshold;
  final SmoothingConfig _smoothingConfig;
  final bool _enableAdvancedSmoothing;

  final Map<String, _BindInfo> _bindPose = {};
  final RootMotionHelper _rootHelper = RootMotionHelper();
  final Quat _hipsBindBasis = Quat();
  final Quat _spineBindBasis = Quat();
  double _modelLegLength = 1.0;

  // Advanced smoothing
  BoneRotationSmoother? _boneSmoother;
  double _currentTime = 0.0;

  // Axis detection (supports Y-up and negative-Z-up rigs)
  String _verticalAxis = 'y';
  String _forwardAxis = 'z';
  String _sideAxis = 'x';
  double _upSign = 1.0;

  void _recomputeBindPose() {
    _bindPose.clear();

    try {
      modelRoot.updateMatrixWorld(true);
    } catch (_) {}

    bones.forEach((name, bone) {
      final pos = _worldPos(bone);
      final quat = _worldQuat(bone);
      _bindPose[name] = _BindInfo(
        position: pos,
        quaternion: quat,
        localQuaternion: _quatFromBone(bone),
      );
    });

    for (final link in _chainLinks) {
      final parent = _bindPose[link.$1];
      final child = _bindPose[link.$2];
      if (parent == null || child == null) continue;
      final dir = Vec3.clone(child.position)
        ..sub(parent.position)
        ..normalize();
      parent.childDirections[link.$2] = dir;
    }

    _computeHipsBasis();
    _detectAxes();
    _computeModelLegLength();
    _computeSpineBasis();
  }

  void _computeHipsBasis() {
    final hips = _bindPose['Hips'];
    final spine = _bindPose['Spine'];
    final leftUpLeg = _bindPose['LeftUpLeg'];
    final rightUpLeg = _bindPose['RightUpLeg'];
    if (hips == null ||
        spine == null ||
        leftUpLeg == null ||
        rightUpLeg == null) {
      return;
    }

    final up = Vec3.clone(spine.position)
      ..sub(hips.position)
      ..normalize();
    final right = Vec3.clone(leftUpLeg.position)
      ..sub(rightUpLeg.position)
      ..normalize();
    final fwd = Vec3()
      ..setFromCross(right, up)
      ..normalize();
    final orthoRight = Vec3()
      ..setFromCross(up, fwd)
      ..normalize();

    _hipsBindBasis.copyFrom(_quatFromBasis(orthoRight, up, fwd));

    final hipWidth = leftUpLeg.position.distanceTo(rightUpLeg.position);
    _rootHelper.updateModelMetrics(hipSpan: hipWidth);
  }

  void _detectAxes() {
    final hipsBone = bones['Hips'];
    if (hipsBone == null) return;
    final pos = _vecFromBone(hipsBone);
    final absX = pos.x.abs();
    final absY = pos.y.abs();
    final absZ = pos.z.abs();
    if (absZ > absY && absZ > absX) {
      _verticalAxis = 'z';
      _forwardAxis = 'y';
      _sideAxis = 'x';
      _upSign = pos.z.sign == 0 ? -1.0 : pos.z.sign.toDouble();
    } else {
      _verticalAxis = 'y';
      _forwardAxis = 'z';
      _sideAxis = 'x';
      _upSign = pos.y.sign == 0 ? 1.0 : pos.y.sign.toDouble();
    }
  }

  void _computeModelLegLength() {
    final hips = _bindPose['Hips'];
    final leftKnee = _bindPose['LeftLeg'];
    final rightKnee = _bindPose['RightLeg'];
    final leftFoot = _bindPose['LeftFoot'];
    final rightFoot = _bindPose['RightFoot'];

    if (hips != null) {
      _modelLegLength = _verticalValue(hips.position).abs();
    }

    if (hips != null &&
        leftKnee != null &&
        rightKnee != null &&
        leftFoot != null &&
        rightFoot != null) {
      final leftLen = hips.position.distanceTo(leftKnee.position) +
          leftKnee.position.distanceTo(leftFoot.position);
      final rightLen = hips.position.distanceTo(rightKnee.position) +
          rightKnee.position.distanceTo(rightFoot.position);
      final avg = (leftLen + rightLen) * 0.5;
      if (avg > 0.01) _modelLegLength = avg;
    }

    if (_modelLegLength < 0.01) _modelLegLength = 1.0;
    if (_modelLegLength > 0.5 && _modelLegLength < 5.0) {
      _modelLegLength *= 100.0;
    }
  }

  void _computeSpineBasis() {
    final spine = _bindPose['Spine'];
    final hips = _bindPose['Hips'];
    final leftArm = _bindPose['LeftArm'];
    final rightArm = _bindPose['RightArm'];
    final neck = _bindPose['Neck'];
    if (spine == null ||
        hips == null ||
        leftArm == null ||
        rightArm == null ||
        neck == null) {
      return;
    }

    final up = Vec3.clone(neck.position)
      ..sub(spine.position)
      ..normalize();
    final right = Vec3.clone(leftArm.position)
      ..sub(rightArm.position)
      ..normalize();
    final fwd = Vec3()
      ..setFromCross(right, up)
      ..normalize();
    final orthoRight = Vec3()
      ..setFromCross(up, fwd)
      ..normalize();
    _spineBindBasis.copyFrom(_quatFromBasis(orthoRight, up, fwd));
  }

  void applyPose({
    required MixamoPose pose,
    required List<dynamic> poseLandmarks,
    required double videoWidth,
    required double videoHeight,
    double? timestamp,
  }) {
    if (pose.isEmpty) return;

    // Update timestamp for smoothing
    if (timestamp != null) {
      _currentTime = timestamp;
    } else {
      _currentTime += 0.033; // Default 30fps
    }

    _positionHips(pose, poseLandmarks, videoWidth, videoHeight);
    _handleHips(pose);
    _handleSpine(pose);

    for (final link in _chainLinks) {
      _alignBone(link.$1, link.$2, pose);
    }

    try {
      modelRoot.updateMatrixWorld(true);
    } catch (_) {}
  }

  /// Reset smoothing state (call when starting new video/animation)
  void resetSmoothing() {
    _boneSmoother?.reset();
    _currentTime = 0.0;
  }

  void _positionHips(
    MixamoPose pose,
    List<dynamic> poseLandmarks,
    double width,
    double height,
  ) {
    final hipBone = bones['Hips'];
    final pHips = pose['Hips'];
    final pLeftFoot = pose['LeftFoot'];
    final pRightFoot = pose['RightFoot'];
    final pLeftToe = pose['LeftToeBase'];
    final pRightToe = pose['RightToeBase'];
    if (hipBone == null ||
        pHips == null ||
        pLeftFoot == null ||
        pRightFoot == null) {
      return;
    }

    final pLeftKnee = pose['LeftLeg'];
    final pRightKnee = pose['RightLeg'];

    double mpLegLength = 1.0;
    if (pLeftKnee != null && pRightKnee != null) {
      final leftLen = pHips.position.distanceTo(pLeftKnee.position) +
          pLeftKnee.position.distanceTo(pLeftFoot.position);
      final rightLen = pHips.position.distanceTo(pRightKnee.position) +
          pRightKnee.position.distanceTo(pRightFoot.position);
      mpLegLength = (leftLen + rightLen) * 0.5;
    }

    final safeMp = mpLegLength > 0.01 ? mpLegLength : 1.0;
    final scale = _modelLegLength / safeMp;

    double minWorldY = pLeftFoot.position.y;
    if (pRightFoot.position.y < minWorldY) minWorldY = pRightFoot.position.y;
    if (pLeftToe != null && pLeftToe.position.y < minWorldY) {
      minWorldY = pLeftToe.position.y;
    }
    if (pRightToe != null && pRightToe.position.y < minWorldY) {
      minWorldY = pRightToe.position.y;
    }

    final distToFloor = (pHips.position.y - minWorldY).abs();
    final rawHeight = distToFloor * scale;
    final minHeight = _modelLegLength * 0.85;
    double targetHeight = math.max(rawHeight, minHeight) * _upSign;
    // Clamp to ground based on sign
    if (_upSign < 0 && targetHeight > 0) targetHeight = 0;
    if (_upSign > 0 && targetHeight < 0) targetHeight = 0;

    final curr = _getBonePosition(hipBone);
    double targetSide = _axisValue(curr, _sideAxis);
    double targetForward = _axisValue(curr, _forwardAxis);

    _rootHelper.reset(width: width.toInt(), height: height.toInt());
    final translation = _rootHelper.computeTranslation(poseLandmarks);
    if (translation != null) {
      targetSide = translation.x;
      targetForward = translation.z;
    }

    const alpha = 0.1;
    final pos = _getBonePosition(hipBone);
    double newX = pos.x;
    double newY = pos.y;
    double newZ = pos.z;

    // Apply side (x)
    newX = _lerp(newX, targetSide, alpha);

    if (_verticalAxis == 'y') {
      newY = _lerp(newY, targetHeight, alpha);
      newZ = _lerp(newZ, targetForward, alpha);
    } else {
      newZ = _lerp(newZ, targetHeight, alpha);
      newY = _lerp(newY, targetForward, alpha);
    }

    final newPos = Vec3(newX, newY, newZ);
    _setBonePosition(hipBone, newPos);
  }

  void _handleHips(MixamoPose pose) {
    final hipBone = bones['Hips'];
    if (hipBone == null) return;

    final pHips = pose['Hips'];
    final pSpine = pose['Spine'];
    final pLeft = pose['LeftUpLeg'];
    final pRight = pose['RightUpLeg'];
    if (pHips == null || pSpine == null || pLeft == null || pRight == null) {
      return;
    }
    if (pHips.visibility < visibilityThreshold) {
      return;
    }

    final up = Vec3.clone(pSpine.position)
      ..sub(pHips.position)
      ..normalize();
    final right = Vec3.clone(pLeft.position)
      ..sub(pRight.position)
      ..normalize();
    final fwd = Vec3()
      ..setFromCross(right, up)
      ..normalize();
    final orthoRight = Vec3()
      ..setFromCross(up, fwd)
      ..normalize();

    final targetQuat = _quatFromBasis(orthoRight, up, fwd);
    final delta = Quat.clone(targetQuat)..multiply(_invert(_hipsBindBasis));

    final hipsBind = _bindPose['Hips'];
    if (hipsBind == null) return;

    final targetWorld = Quat.clone(delta)..multiply(hipsBind.quaternion);
    _applyWorldRotationToBone(hipBone, targetWorld, 0.5, 'Hips');
  }

  void _handleSpine(MixamoPose pose) {
    final spineBone = bones['Spine'];
    final spine1Bone = bones['Spine1'];
    final spine2Bone = bones['Spine2'];
    if (spineBone == null) return;

    final pNeck = pose['Neck'];
    final pLeftArm = pose['LeftArm'];
    final pRightArm = pose['RightArm'];
    final pSpine = pose['Spine'];
    if (pNeck == null ||
        pLeftArm == null ||
        pRightArm == null ||
        pSpine == null) {
      return;
    }
    if (pNeck.visibility < visibilityThreshold) {
      return;
    }

    final up = Vec3.clone(pNeck.position)
      ..sub(pSpine.position)
      ..normalize();
    final right = Vec3.clone(pLeftArm.position)
      ..sub(pRightArm.position)
      ..normalize();
    final fwd = Vec3()
      ..setFromCross(right, up)
      ..normalize();
    final orthoRight = Vec3()
      ..setFromCross(up, fwd)
      ..normalize();

    final targetQuat = _quatFromBasis(orthoRight, up, fwd);
    final delta = Quat.clone(targetQuat)..multiply(_invert(_spineBindBasis));

    final spineBind = _bindPose['Spine'];
    if (spineBind == null) return;

    final targetWorld = Quat.clone(delta)..multiply(spineBind.quaternion);
    _applyWorldRotationToBone(spineBone, targetWorld, 0.5, 'Spine');

    final spine1Bind = _bindPose['Spine1'];
    final spine2Bind = _bindPose['Spine2'];
    if (spine1Bone != null && spine1Bind != null) {
      _slerpBoneQuat(spine1Bone, spine1Bind.localQuaternion, 0.8);
    }
    if (spine2Bone != null && spine2Bind != null) {
      _slerpBoneQuat(spine2Bone, spine2Bind.localQuaternion, 0.8);
    }
  }

  void _alignBone(String parentName, String childName, MixamoPose pose) {
    final parentBone = bones[parentName];
    final parentPose = pose[parentName];
    final childPose = pose[childName];
    if (parentBone == null || parentPose == null || childPose == null) return;
    if (parentPose.visibility < visibilityThreshold) return;

    final bind = _bindPose[parentName];
    final bindDir = bind?.childDirections[childName];
    if (bind == null || bindDir == null) return;

    final targetDir = Vec3.clone(childPose.position)..sub(parentPose.position);
    if (targetDir.lengthSq == 0) return;
    targetDir.normalize();

    final rotDelta = _quatFromUnitVectors(bindDir, targetDir);
    final targetWorld = Quat.clone(rotDelta)..multiply(bind.quaternion);

    // Use higher interpolation factor for hand bones for better responsiveness
    final isHandBone = _isHandBone(parentName);
    final interpolationFactor = isHandBone ? 0.75 : 0.5;

    _applyWorldRotationToBone(
        parentBone, targetWorld, interpolationFactor, parentName);
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

  // --- Helpers ---

  void _applyWorldRotationToBone(dynamic bone, Quat targetWorld, double t,
      [String? boneName]) {
    Quat newLocal = targetWorld;

    if (bone is three.Object3D && bone.parent != null) {
      final parent = bone.parent!;
      parent.updateMatrixWorld(true);
      final parentWorld = three.Quaternion();
      parent.getWorldQuaternion(parentWorld);
      final pInv = Quat(
        parentWorld.x.toDouble(),
        parentWorld.y.toDouble(),
        parentWorld.z.toDouble(),
        parentWorld.w.toDouble(),
      ).invert();
      newLocal = pInv.multiply(targetWorld);
    }

    newLocal.normalized();

    // Apply advanced smoothing if enabled
    if (_enableAdvancedSmoothing && _boneSmoother != null && boneName != null) {
      final smoothed =
          _boneSmoother!.smoothRotation(boneName, _currentTime, newLocal);
      // Use adaptive interpolation factor, but adjust for hand bones
      double adaptiveT =
          _boneSmoother!.getAdaptiveInterpolationFactor(boneName);

      // Increase interpolation factor for hand bones for better responsiveness
      if (_isHandBone(boneName)) {
        adaptiveT =
            math.min(adaptiveT * 1.2, 0.85); // Boost hand bones, cap at 0.85
      }

      _slerpBoneQuat(bone, smoothed, adaptiveT);
    } else {
      // For hand bones without smoothing, use higher interpolation factor
      final finalT = (boneName != null && _isHandBone(boneName))
          ? math.min(t * 1.5, 0.8)
          : t;
      _slerpBoneQuat(bone, newLocal, finalT);
    }

    _updateBoneMatrix(bone);
  }

  void _updateBoneMatrix(dynamic bone) {
    if (bone is three.Object3D) {
      bone.updateMatrixWorld(true);
    }
  }

  Vec3 _vecFromBone(dynamic bone) => Vec3(
        (bone.position.x as num).toDouble(),
        (bone.position.y as num).toDouble(),
        (bone.position.z as num).toDouble(),
      );

  double _verticalValue(Vec3 v) {
    switch (_verticalAxis) {
      case 'z':
        return v.z;
      case 'y':
      default:
        return v.y;
    }
  }

  double _axisValue(Vec3 v, String axis) {
    switch (axis) {
      case 'x':
        return v.x;
      case 'z':
        return v.z;
      case 'y':
      default:
        return v.y;
    }
  }

  Vec3 _worldPos(dynamic bone) {
    if (bone is three.Object3D) {
      final v = three.Vector3();
      bone.getWorldPosition(v);
      return Vec3(v.x.toDouble(), v.y.toDouble(), v.z.toDouble());
    }
    return _vecFromBone(bone);
  }

  Quat _quatFromBone(dynamic bone) => Quat(
        (bone.quaternion.x as num).toDouble(),
        (bone.quaternion.y as num).toDouble(),
        (bone.quaternion.z as num).toDouble(),
        (bone.quaternion.w as num).toDouble(),
      );

  Quat _worldQuat(dynamic bone) {
    if (bone is three.Object3D) {
      final q = three.Quaternion();
      bone.getWorldQuaternion(q);
      return Quat(
        q.x.toDouble(),
        q.y.toDouble(),
        q.z.toDouble(),
        q.w.toDouble(),
      );
    }
    return _quatFromBone(bone);
  }

  Vec3 _getBonePosition(dynamic bone) => _vecFromBone(bone);

  void _setBonePosition(dynamic bone, Vec3 v) {
    bone.position.x = v.x;
    bone.position.y = v.y;
    bone.position.z = v.z;
  }

  void _slerpBoneQuat(dynamic bone, Quat target, double t) {
    final current = _quatFromBone(bone);
    current.slerp(target, t).normalized();
    bone.quaternion.x = current.x;
    bone.quaternion.y = current.y;
    bone.quaternion.z = current.z;
    bone.quaternion.w = current.w;
  }

  Quat _invert(Quat q) => Quat(-q.x, -q.y, -q.z, q.w);

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  Quat _quatFromUnitVectors(Vec3 from, Vec3 to) {
    final v1 = Vec3.clone(from)..normalize();
    final v2 = Vec3.clone(to)..normalize();
    double r = v1.dot(v2) + 1;
    Vec3 axis;
    if (r < 1e-6) {
      axis = Vec3(1, 0, 0).cross(v1);
      if (axis.lengthSq < 1e-6) {
        axis = Vec3(0, 1, 0).cross(v1);
      }
      axis.normalize();
      return Quat(axis.x, axis.y, axis.z, 0);
    }
    final cross = Vec3.clone(v1).cross(v2);
    return Quat(cross.x, cross.y, cross.z, r).normalized();
  }

  Quat _quatFromBasis(Vec3 right, Vec3 up, Vec3 fwd) {
    final m00 = right.x, m01 = up.x, m02 = fwd.x;
    final m10 = right.y, m11 = up.y, m12 = fwd.y;
    final m20 = right.z, m21 = up.z, m22 = fwd.z;
    final trace = m00 + m11 + m22;
    double x, y, z, w;
    if (trace > 0) {
      final s = 0.5 / math.sqrt(trace + 1.0);
      w = 0.25 / s;
      x = (m21 - m12) * s;
      y = (m02 - m20) * s;
      z = (m10 - m01) * s;
    } else if (m00 > m11 && m00 > m22) {
      final s = 2.0 * math.sqrt(1.0 + m00 - m11 - m22);
      w = (m21 - m12) / s;
      x = 0.25 * s;
      y = (m01 + m10) / s;
      z = (m02 + m20) / s;
    } else if (m11 > m22) {
      final s = 2.0 * math.sqrt(1.0 + m11 - m00 - m22);
      w = (m02 - m20) / s;
      x = (m01 + m10) / s;
      y = 0.25 * s;
      z = (m12 + m21) / s;
    } else {
      final s = 2.0 * math.sqrt(1.0 + m22 - m00 - m11);
      w = (m10 - m01) / s;
      x = (m02 + m20) / s;
      y = (m12 + m21) / s;
      z = 0.25 * s;
    }
    return Quat(x, y, z, w).normalized();
  }
}

class _BindInfo {
  _BindInfo({
    required this.position,
    required this.quaternion,
    required this.localQuaternion,
  });

  final Vec3 position;
  final Quat quaternion;
  final Quat localQuaternion;
  final Map<String, Vec3> childDirections = {};
}

/// Parent-child bone chains to align.
List<(String, String)> get _chainLinks => const [
      ('Neck', 'Head'),
      // Left arm and hand
      ('LeftArm', 'LeftForeArm'),
      ('LeftForeArm', 'LeftHand'),
      ('LeftHand', 'LeftHandThumb1'),
      ('LeftHandThumb1', 'LeftHandThumb2'),
      ('LeftHandThumb2', 'LeftHandThumb3'),
      ('LeftHandThumb3', 'LeftHandThumb4'),
      ('LeftHand', 'LeftHandIndex1'),
      ('LeftHandIndex1', 'LeftHandIndex2'),
      ('LeftHandIndex2', 'LeftHandIndex3'),
      ('LeftHandIndex3', 'LeftHandIndex4'),
      ('LeftHand', 'LeftHandMiddle1'),
      ('LeftHandMiddle1', 'LeftHandMiddle2'),
      ('LeftHandMiddle2', 'LeftHandMiddle3'),
      ('LeftHandMiddle3', 'LeftHandMiddle4'),
      ('LeftHand', 'LeftHandRing1'),
      ('LeftHandRing1', 'LeftHandRing2'),
      ('LeftHandRing2', 'LeftHandRing3'),
      ('LeftHandRing3', 'LeftHandRing4'),
      ('LeftHand', 'LeftHandPinky1'),
      ('LeftHandPinky1', 'LeftHandPinky2'),
      ('LeftHandPinky2', 'LeftHandPinky3'),
      ('LeftHandPinky3', 'LeftHandPinky4'),
      // Right arm and hand
      ('RightArm', 'RightForeArm'),
      ('RightForeArm', 'RightHand'),
      ('RightHand', 'RightHandThumb1'),
      ('RightHandThumb1', 'RightHandThumb2'),
      ('RightHandThumb2', 'RightHandThumb3'),
      ('RightHandThumb3', 'RightHandThumb4'),
      ('RightHand', 'RightHandIndex1'),
      ('RightHandIndex1', 'RightHandIndex2'),
      ('RightHandIndex2', 'RightHandIndex3'),
      ('RightHandIndex3', 'RightHandIndex4'),
      ('RightHand', 'RightHandMiddle1'),
      ('RightHandMiddle1', 'RightHandMiddle2'),
      ('RightHandMiddle2', 'RightHandMiddle3'),
      ('RightHandMiddle3', 'RightHandMiddle4'),
      ('RightHand', 'RightHandRing1'),
      ('RightHandRing1', 'RightHandRing2'),
      ('RightHandRing2', 'RightHandRing3'),
      ('RightHandRing3', 'RightHandRing4'),
      ('RightHand', 'RightHandPinky1'),
      ('RightHandPinky1', 'RightHandPinky2'),
      ('RightHandPinky2', 'RightHandPinky3'),
      ('RightHandPinky3', 'RightHandPinky4'),
      // Legs
      ('LeftUpLeg', 'LeftLeg'),
      ('LeftLeg', 'LeftFoot'),
      ('LeftFoot', 'LeftToeBase'),
      ('LeftToeBase', 'LeftToe_End'),
      ('RightUpLeg', 'RightLeg'),
      ('RightLeg', 'RightFoot'),
      ('RightFoot', 'RightToeBase'),
      ('RightToeBase', 'RightToe_End'),
    ];
