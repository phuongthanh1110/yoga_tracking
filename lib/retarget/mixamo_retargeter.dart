import 'dart:math' as math;

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
  }) : bones = Map.unmodifiable(bones) {
    _recomputeBindPose();
  }

  final dynamic modelRoot;
  final Map<String, dynamic> bones;
  final double visibilityThreshold;

  final Map<String, _BindInfo> _bindPose = {};
  final RootMotionHelper _rootHelper = RootMotionHelper();
  final Quat _hipsBindBasis = Quat();
  final Quat _spineBindBasis = Quat();
  double _modelLegLength = 1.0;

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
  }) {
    if (pose.isEmpty) return;

    _positionHips(pose, poseLandmarks, videoWidth, videoHeight);
    _handleHips(pose);
    _handleSpine(pose);

    // Swivel-aware limbs (elbows/knees) and hands (palm twist)
    // For arms: include finger tip for better forearm twist and wrist alignment
    _handleLimb(
      pose,
      start: 'LeftArm',
      mid: 'LeftForeArm',
      end: 'LeftHand',
      fingerTip: 'LeftHandMiddle1', // Use middle finger for stable direction
    );
    _handleLimb(
      pose,
      start: 'RightArm',
      mid: 'RightForeArm',
      end: 'RightHand',
      fingerTip: 'RightHandMiddle1',
    );
    // Legs: no finger equivalent needed
    _handleLimb(pose, start: 'LeftUpLeg', mid: 'LeftLeg', end: 'LeftFoot');
    _handleLimb(pose, start: 'RightUpLeg', mid: 'RightLeg', end: 'RightFoot');

    _handleHand(
      pose,
      hand: 'LeftHand',
      forearm: 'LeftForeArm',
      index: 'LeftHandIndex1',
      pinky: 'LeftHandPinky1',
    );
    _handleHand(
      pose,
      hand: 'RightHand',
      forearm: 'RightForeArm',
      index: 'RightHandIndex1',
      pinky: 'RightHandPinky1',
    );

    // Handle head with proper orientation (not just direction)
    _handleHead(pose);

    // Standard alignment for remaining links (fingers, toes, etc.)
    // Note: Head is now handled separately above
    for (final link in _standardChainLinks) {
      if (link.$1 == 'Neck' && link.$2 == 'Head')
        continue; // Skip, handled above
      _alignBone(link.$1, link.$2, pose);
    }

    try {
      modelRoot.updateMatrixWorld(true);
    } catch (_) {}
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

    // Use average visibility of hip-related landmarks
    final avgVisibility =
        (pHips.visibility + pLeft.visibility + pRight.visibility) / 3.0;
    if (avgVisibility < visibilityThreshold * 0.5) {
      return;
    }

    // Calculate hip orientation from hip and leg positions
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

    // Fallback: Use shoulder orientation if hip visibility is low
    final pLeftArm = pose['LeftArm'];
    final pRightArm = pose['RightArm'];
    if (pLeftArm != null &&
        pRightArm != null &&
        avgVisibility < visibilityThreshold) {
      // Blend with shoulder-based right vector
      final shoulderRight = Vec3.clone(pLeftArm.position)
        ..sub(pRightArm.position)
        ..normalize();
      final shoulderVis = (pLeftArm.visibility + pRightArm.visibility) / 2.0;

      if (shoulderVis > avgVisibility) {
        // Blend shoulder right into hip right
        final blendFactor =
            ((shoulderVis - avgVisibility) / (1.0 - avgVisibility))
                .clamp(0.0, 0.5);
        orthoRight
          ..scale(1.0 - blendFactor)
          ..add(shoulderRight.scale(blendFactor))
          ..normalize();
      }
    }

    final targetQuat = _quatFromBasis(orthoRight, up, fwd);
    final delta = Quat.clone(targetQuat)..multiply(_invert(_hipsBindBasis));

    final hipsBind = _bindPose['Hips'];
    if (hipsBind == null) return;

    final targetWorld = Quat.clone(delta)..multiply(hipsBind.quaternion);

    // Higher weight when visibility is good, lower when uncertain
    final weight = 0.3 + 0.4 * avgVisibility.clamp(0.0, 1.0);
    _applyWorldRotationToBone(hipBone, targetWorld, weight);
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

    // Average visibility of spine-related landmarks
    final avgVisibility =
        (pNeck.visibility + pLeftArm.visibility + pRightArm.visibility) / 3.0;
    if (avgVisibility < visibilityThreshold * 0.5) {
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

    // Adaptive weight based on visibility
    final weight = 0.3 + 0.4 * avgVisibility.clamp(0.0, 1.0);
    _applyWorldRotationToBone(spineBone, targetWorld, weight);

    // Distribute rotation to spine chain for more natural bending
    final spine1Bind = _bindPose['Spine1'];
    final spine2Bind = _bindPose['Spine2'];
    if (spine1Bone != null && spine1Bind != null) {
      _slerpBoneQuat(spine1Bone, spine1Bind.localQuaternion, 0.7);
    }
    if (spine2Bone != null && spine2Bind != null) {
      _slerpBoneQuat(spine2Bone, spine2Bind.localQuaternion, 0.7);
    }
  }

  /// Handles head rotation with proper orientation calculation.
  /// Uses ears for yaw/roll, shoulders as fallback, with sanity checks
  /// to prevent head "breaking" (flipping to wrong direction).
  void _handleHead(MixamoPose pose) {
    final headBone = bones['Head'];
    final neckBone = bones['Neck'];
    if (headBone == null) return;

    final pHead = pose['Head'];
    final pNeck = pose['Neck'];
    if (pHead == null || pNeck == null) return;

    final headBind = _bindPose['Head'];
    final neckBind = _bindPose['Neck'];
    if (headBind == null || neckBind == null) return;

    // Get face landmarks for orientation
    final pLeftEar = pose['LeftEar'];
    final pRightEar = pose['RightEar'];
    final pLeftEye = pose['LeftEye'];
    final pRightEye = pose['RightEye'];
    // Note: Nose could be used for pitch calculation in future
    // final pNose = pose['Nose'];

    // Get shoulder for fallback right vector
    final pLeftArm = pose['LeftArm'];
    final pRightArm = pose['RightArm'];

    // Calculate average visibility
    double visSum = pHead.visibility;
    int visCount = 1;
    if (pLeftEar != null && pRightEar != null) {
      visSum += (pLeftEar.visibility + pRightEar.visibility) / 2;
      visCount++;
    }
    final avgVisibility = visSum / visCount;

    // Skip if visibility too low
    if (avgVisibility < visibilityThreshold * 0.5) {
      // Fallback: simple directional alignment
      _alignBone('Neck', 'Head', pose);
      return;
    }

    // === Calculate head basis vectors ===
    // UP: neck → head direction
    Vec3 headUp = Vec3.clone(pHead.position)..sub(pNeck.position);
    if (headUp.lengthSq < 1e-6) {
      _alignBone('Neck', 'Head', pose);
      return;
    }
    headUp.normalize();

    // RIGHT: from ears (preferred) or eyes or shoulders (fallback)
    Vec3? headRight;
    double rightConfidence = 0;

    // Method 1: Use ears (most reliable for yaw)
    if (pLeftEar != null &&
        pRightEar != null &&
        pLeftEar.visibility > visibilityThreshold * 0.7 &&
        pRightEar.visibility > visibilityThreshold * 0.7) {
      headRight = Vec3.clone(pLeftEar.position)..sub(pRightEar.position);

      // Validate: ears should be roughly horizontal relative to neck-head axis
      final earDirNorm = Vec3.clone(headRight)..normalize();
      final dotWithUp = earDirNorm.dot(headUp).abs();
      if (dotWithUp < 0.7) {
        // Valid - ears are not too aligned with up vector
        rightConfidence = (pLeftEar.visibility + pRightEar.visibility) / 2;
      } else {
        headRight = null; // Invalid, fallback
      }
    }

    // Method 2: Use eyes as fallback
    if (headRight == null &&
        pLeftEye != null &&
        pRightEye != null &&
        pLeftEye.visibility > visibilityThreshold &&
        pRightEye.visibility > visibilityThreshold) {
      headRight = Vec3.clone(pLeftEye.position)..sub(pRightEye.position);
      rightConfidence = (pLeftEye.visibility + pRightEye.visibility) / 2 * 0.8;
    }

    // Method 3: Use shoulders as last resort
    if (headRight == null &&
        pLeftArm != null &&
        pRightArm != null &&
        pLeftArm.visibility > visibilityThreshold &&
        pRightArm.visibility > visibilityThreshold) {
      headRight = Vec3.clone(pLeftArm.position)..sub(pRightArm.position);
      rightConfidence = 0.5; // Lower confidence for shoulders
    }

    // If no right vector found, fallback to simple alignment
    if (headRight == null || headRight.lengthSq < 1e-6) {
      _alignBone('Neck', 'Head', pose);
      return;
    }
    headRight.normalize();

    // === Build orthonormal basis ===
    // Forward: cross of right × up
    Vec3 headForward = Vec3()
      ..setFromCross(headRight, headUp)
      ..normalize();

    // Re-orthogonalize right to ensure valid basis
    headRight = Vec3()
      ..setFromCross(headUp, headForward)
      ..normalize();

    // === Sanity check: prevent head flipping ===
    // Check if forward is pointing roughly in the same direction as bind pose
    final bindDir = neckBind.childDirections['Head'];
    if (bindDir != null) {
      // Get bind forward direction (perpendicular to bind up)
      final bindUp = Vec3.clone(bindDir)..normalize();
      final bindRight = Vec3(1, 0, 0); // Assume X-right in T-pose
      final bindForward = Vec3()
        ..setFromCross(bindRight, bindUp)
        ..normalize();

      // Check if calculated forward is flipped
      final forwardDot = headForward.dot(bindForward);
      if (forwardDot < -0.3) {
        // Head appears to be flipped - this is likely a tracking error
        // Reduce confidence or use more conservative rotation
        rightConfidence *= 0.3;
      }
    }

    // === Calculate target rotation ===
    final targetQuat = _quatFromBasis(headRight, headUp, headForward);

    // === Calculate bind pose head basis ===
    final bindUp = Vec3.clone(headBind.position)
      ..sub(neckBind.position)
      ..normalize();

    // Use stored bind child direction for neck→head
    Vec3 bindRight;
    final storedBindDir = neckBind.childDirections['Head'];
    if (storedBindDir != null) {
      // Create a right vector perpendicular to bind up
      bindRight = Vec3(1, 0, 0); // Assume standard T-pose
      if (bindRight.dot(bindUp).abs() > 0.9) {
        bindRight = Vec3(0, 0, 1);
      }
    } else {
      bindRight = Vec3(1, 0, 0);
    }

    Vec3 bindForward = Vec3()
      ..setFromCross(bindRight, bindUp)
      ..normalize();
    bindRight = Vec3()
      ..setFromCross(bindUp, bindForward)
      ..normalize();

    final bindQuat = _quatFromBasis(bindRight, bindUp, bindForward);

    // Calculate delta rotation
    final delta = Quat.clone(targetQuat)..multiply(_invert(bindQuat));
    final targetWorld = Quat.clone(delta)..multiply(headBind.quaternion);

    // === Apply rotation with visibility-based weight ===
    // Lower weight when confidence is low to prevent jerky movement
    final weight = 0.3 + 0.5 * rightConfidence.clamp(0.0, 1.0);
    _applyWorldRotationToBone(headBone, targetWorld, weight);

    // Also apply partial rotation to neck for smoother movement
    if (neckBone != null) {
      // Neck gets a smaller portion of the head rotation
      final neckWeight = weight * 0.25;
      final neckTarget = Quat.clone(delta)..multiply(neckBind.quaternion);
      _applyWorldRotationToBone(neckBone, neckTarget, neckWeight);
    }
  }

  /// Handles palm twist and wrist bend using index/pinky to build a palm basis.
  /// This now properly calculates wrist bend angle for poses like hands on ground.
  void _handleHand(
    MixamoPose pose, {
    required String hand,
    required String forearm,
    required String index,
    required String pinky,
  }) {
    final handBone = bones[hand];
    final pHand = pose[hand];
    final pForeArm = pose[forearm];
    final pIndex = pose[index];
    final pPinky = pose[pinky];
    final bindHand = _bindPose[hand];
    final bindForeArm = _bindPose[forearm];
    final bindIndex = _bindPose[index];
    final bindPinky = _bindPose[pinky];
    if (handBone == null ||
        pHand == null ||
        pForeArm == null ||
        pIndex == null ||
        pPinky == null ||
        bindHand == null ||
        bindForeArm == null ||
        bindIndex == null ||
        bindPinky == null ||
        pHand.visibility < visibilityThreshold) {
      return;
    }

    // Build target hand basis from pose data
    // Y-axis: hand → fingers (primary direction)
    // Z-axis: palm normal (cross of index and pinky directions)
    // X-axis: thumb side direction
    final targetFingerDir = Vec3.clone(pIndex.position)
      ..sub(pHand.position)
      ..normalize();
    final targetPinkyDir = Vec3.clone(pPinky.position)
      ..sub(pHand.position)
      ..normalize();

    // Average finger direction for more stable Y-axis
    final targetY = Vec3.clone(targetFingerDir)
      ..add(targetPinkyDir)
      ..scale(0.5)
      ..normalize();

    // Palm normal from cross product
    var targetZ = Vec3()
      ..setFromCross(targetFingerDir, targetPinkyDir)
      ..normalize();
    if (targetZ.lengthSq < 1e-6) {
      // Fallback: use forearm direction to compute palm normal
      final forearmDir = Vec3.clone(pHand.position)
        ..sub(pForeArm.position)
        ..normalize();
      targetZ = Vec3()
        ..setFromCross(targetY, forearmDir)
        ..normalize();
    }
    if (targetZ.lengthSq < 1e-6) return;

    final targetX = Vec3()
      ..setFromCross(targetY, targetZ)
      ..normalize();
    final targetBasis = _quatFromBasis(targetX, targetY, targetZ);

    // Build bind pose hand basis
    final bindFingerDir = Vec3.clone(bindIndex.position)
      ..sub(bindHand.position)
      ..normalize();
    final bindPinkyDir = Vec3.clone(bindPinky.position)
      ..sub(bindHand.position)
      ..normalize();

    final bindY = Vec3.clone(bindFingerDir)
      ..add(bindPinkyDir)
      ..scale(0.5)
      ..normalize();

    var bindZ = Vec3()
      ..setFromCross(bindFingerDir, bindPinkyDir)
      ..normalize();
    if (bindZ.lengthSq < 1e-6) {
      final bindForearmDir = Vec3.clone(bindHand.position)
        ..sub(bindForeArm.position)
        ..normalize();
      bindZ = Vec3()
        ..setFromCross(bindY, bindForearmDir)
        ..normalize();
    }
    if (bindZ.lengthSq < 1e-6) return;

    final bindX = Vec3()
      ..setFromCross(bindY, bindZ)
      ..normalize();
    final bindBasis = _quatFromBasis(bindX, bindY, bindZ);

    final delta = Quat.clone(targetBasis)..multiply(_invert(bindBasis));
    final targetWorld = Quat.clone(delta)..multiply(bindHand.quaternion);

    // High interpolation weight for responsive wrist movement
    _applyWorldRotationToBone(handBone, targetWorld, 0.9);
  }

  /// Adds swivel (pole vector) so elbows/knees point correctly.
  /// For arms: also considers finger direction for better forearm twist.
  void _handleLimb(
    MixamoPose pose, {
    required String start,
    required String mid,
    required String end,
    String?
        fingerTip, // Optional: for arms, use finger position for better end direction
  }) {
    // Directional alignment first
    _alignBone(start, mid, pose);
    _alignBone(mid, end, pose);

    final startBone = bones[start];
    final midBone = bones[mid];
    final pStart = pose[start];
    final pMid = pose[mid];
    final pEnd = pose[end];
    final bStart = _bindPose[start];
    final bMid = _bindPose[mid];
    final bEnd = _bindPose[end];
    if (startBone == null ||
        midBone == null ||
        pStart == null ||
        pMid == null ||
        pEnd == null ||
        bStart == null ||
        bMid == null ||
        bEnd == null) {
      return;
    }

    // Upper limb (shoulder/hip) swivel
    final pVec1 = Vec3.clone(pMid.position)
      ..sub(pStart.position)
      ..normalize();
    final pVec2 = Vec3.clone(pEnd.position)
      ..sub(pMid.position)
      ..normalize();
    var pNormal = Vec3()..setFromCross(pVec1, pVec2);
    if (pNormal.lengthSq < 0.01) return;
    pNormal.normalize();

    final bVec1 = Vec3.clone(bMid.position)
      ..sub(bStart.position)
      ..normalize();
    final bVec2 = Vec3.clone(bEnd.position)
      ..sub(bMid.position)
      ..normalize();
    var bNormal = Vec3()..setFromCross(bVec1, bVec2);
    if (bNormal.lengthSq < 0.01) return;
    bNormal.normalize();

    final pOrtho = Vec3()
      ..setFromCross(pNormal, pVec1)
      ..normalize();
    final bOrtho = Vec3()
      ..setFromCross(bNormal, bVec1)
      ..normalize();

    final pBasis = _quatFromBasis(pOrtho, pVec1, pNormal);
    final bBasis = _quatFromBasis(bOrtho, bVec1, bNormal);
    final delta = Quat.clone(pBasis)..multiply(_invert(bBasis));
    final targetWorld = Quat.clone(delta)..multiply(bStart.quaternion);
    // Higher weight for arms (fingerTip != null), normal for legs
    final limbWeight = fingerTip != null ? 0.75 : 0.5;
    _applyWorldRotationToBone(startBone, targetWorld, limbWeight);

    // Forearm twist: use finger direction for better wrist alignment
    // Only apply if finger has good visibility
    final pFinger = fingerTip != null ? pose[fingerTip] : null;
    final bFinger = fingerTip != null ? _bindPose[fingerTip] : null;
    if (pFinger != null &&
        bFinger != null &&
        pFinger.visibility >= visibilityThreshold) {
      _handleForearmTwist(
        midBone: midBone,
        pMid: pMid,
        pEnd: pEnd,
        pFinger: pFinger,
        bMid: bMid,
        bEnd: bEnd,
        bFinger: bFinger,
      );
    }
  }

  /// Calculates forearm twist based on finger direction for natural wrist positioning.
  void _handleForearmTwist({
    required dynamic midBone,
    required MixamoPoint pMid,
    required MixamoPoint pEnd,
    required MixamoPoint pFinger,
    required _BindInfo bMid,
    required _BindInfo bEnd,
    required _BindInfo bFinger,
  }) {
    // Pose: forearm direction and hand-to-finger direction
    final pForearmDir = Vec3.clone(pEnd.position)
      ..sub(pMid.position)
      ..normalize();
    final pFingerDir = Vec3.clone(pFinger.position)
      ..sub(pEnd.position)
      ..normalize();

    // Calculate the twist axis (along forearm)
    // and the rotation needed to align hand direction
    var pTwistNormal = Vec3()..setFromCross(pForearmDir, pFingerDir);
    if (pTwistNormal.lengthSq < 1e-6) return;
    pTwistNormal.normalize();

    // Bind pose: same calculation
    final bForearmDir = Vec3.clone(bEnd.position)
      ..sub(bMid.position)
      ..normalize();
    final bFingerDir = Vec3.clone(bFinger.position)
      ..sub(bEnd.position)
      ..normalize();

    var bTwistNormal = Vec3()..setFromCross(bForearmDir, bFingerDir);
    if (bTwistNormal.lengthSq < 1e-6) return;
    bTwistNormal.normalize();

    // Build basis for forearm orientation
    final pOrtho = Vec3()
      ..setFromCross(pForearmDir, pTwistNormal)
      ..normalize();
    final bOrtho = Vec3()
      ..setFromCross(bForearmDir, bTwistNormal)
      ..normalize();

    final pBasis = _quatFromBasis(pTwistNormal, pForearmDir, pOrtho);
    final bBasis = _quatFromBasis(bTwistNormal, bForearmDir, bOrtho);

    final delta = Quat.clone(pBasis)..multiply(_invert(bBasis));
    final targetWorld = Quat.clone(delta)..multiply(bMid.quaternion);

    // Higher weight for responsive forearm twist
    _applyWorldRotationToBone(midBone, targetWorld, 0.75);
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

    // Use higher weight for arm bones for responsive movement
    final isArmBone = parentName.contains('Arm') ||
        parentName.contains('ForeArm') ||
        parentName.contains('Hand');
    final weight = isArmBone ? 0.8 : 0.5;
    _applyWorldRotationToBone(parentBone, targetWorld, weight);
  }

  // --- Helpers ---

  void _applyWorldRotationToBone(dynamic bone, Quat targetWorld, double t) {
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
    _slerpBoneQuat(bone, newLocal, t);
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

/// Links that still need standard directional alignment after special handling.
List<(String, String)> get _standardChainLinks => const [
      ('Neck', 'Head'),
      // Fingers
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
      // Right fingers
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
      // Feet/toes
      ('LeftFoot', 'LeftToeBase'),
      ('LeftToeBase', 'LeftToe_End'),
      ('RightFoot', 'RightToeBase'),
      ('RightToeBase', 'RightToe_End'),
    ];
