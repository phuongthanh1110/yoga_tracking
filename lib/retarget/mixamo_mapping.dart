import 'math_types.dart';
import 'one_euro_filter.dart';

/// Landmark indices (MediaPipe Pose).
class PoseLandmarkIndex {
  static const int nose = 0;
  static const int leftEyeInner = 1;
  static const int leftEye = 2;
  static const int leftEyeOuter = 3;
  static const int rightEyeInner = 4;
  static const int rightEye = 5;
  static const int rightEyeOuter = 6;
  static const int leftEar = 7;
  static const int rightEar = 8;
  static const int mouthLeft = 9;
  static const int mouthRight = 10;
  static const int leftShoulder = 11;
  static const int rightShoulder = 12;
  static const int leftElbow = 13;
  static const int rightElbow = 14;
  static const int leftWrist = 15;
  static const int rightWrist = 16;
  static const int leftPinky = 17;
  static const int rightPinky = 18;
  static const int leftIndex = 19;
  static const int rightIndex = 20;
  static const int leftThumb = 21;
  static const int rightThumb = 22;
  static const int leftHip = 23;
  static const int rightHip = 24;
  static const int leftKnee = 25;
  static const int rightKnee = 26;
  static const int leftAnkle = 27;
  static const int rightAnkle = 28;
  static const int leftHeel = 29;
  static const int rightHeel = 30;
  static const int leftFootIndex = 31;
  static const int rightFootIndex = 32;
}

/// Landmark indices (MediaPipe Hand - 21 points per hand).
class HandLandmarkIndex {
  static const int wrist = 0;
  static const int thumbCmc = 1;
  static const int thumbMcp = 2;
  static const int thumbIp = 3;
  static const int thumbTip = 4;
  static const int indexFingerMcp = 5;
  static const int indexFingerPip = 6;
  static const int indexFingerDip = 7;
  static const int indexFingerTip = 8;
  static const int middleFingerMcp = 9;
  static const int middleFingerPip = 10;
  static const int middleFingerDip = 11;
  static const int middleFingerTip = 12;
  static const int ringFingerMcp = 13;
  static const int ringFingerPip = 14;
  static const int ringFingerDip = 15;
  static const int ringFingerTip = 16;
  static const int pinkyMcp = 17;
  static const int pinkyPip = 18;
  static const int pinkyDip = 19;
  static const int pinkyTip = 20;
}

class MixamoPoint {
  MixamoPoint({required this.position, required this.visibility});

  Vec3 position;
  double visibility;
}

typedef MixamoPose = Map<String, MixamoPoint>;

Vec3 _toVec3(dynamic landmark) {
  // MediaPipe poseWorldLandmarks: x,y,z, visibility?
  // Handle both Map (from JSON) and object with properties
  double getX(dynamic obj) {
    if (obj is Map) {
      try {
        return (obj['x'] as num?)?.toDouble() ?? 0.0;
      } catch (e) {
        return 0.0;
      }
    }
    try {
      return (obj.x as num).toDouble();
    } catch (e) {
      return 0.0;
    }
  }

  double getY(dynamic obj) {
    if (obj is Map) {
      try {
        return (obj['y'] as num?)?.toDouble() ?? 0.0;
      } catch (e) {
        return 0.0;
      }
    }
    try {
      return (obj.y as num).toDouble();
    } catch (e) {
      return 0.0;
    }
  }

  double getZ(dynamic obj) {
    if (obj is Map) {
      try {
        return (obj['z'] as num?)?.toDouble() ?? 0.0;
      } catch (e) {
        return 0.0;
      }
    }
    try {
      return (obj.z as num).toDouble();
    } catch (e) {
      return 0.0;
    }
  }

  final v = Vec3(
    getX(landmark),
    getY(landmark),
    getZ(landmark),
  );
  // Match JS axis adjustments
  v.y = -v.y;
  v.z = -v.z;
  return v;
}

MixamoPoint? _clonePoint(MixamoPoint? p) {
  if (p == null) return null;
  return MixamoPoint(
      position: Vec3.clone(p.position), visibility: p.visibility);
}

/// Calculate palm normal vector from poseWorldLandmarks (stable 3D coordinates)
/// and disambiguate using elbow direction.
/// Returns true if palm normal should be flipped (palm facing away), false otherwise.
///
/// Strategy:
/// 1. Use poseWorldLandmarks (wrist, index, pinky) for palm orientation - stable 3D coordinates
/// 2. Calculate palm normal from cross product: (wrist → index) × (index → pinky)
/// 3. Disambiguate using elbow direction: if palm normal points toward elbow, flip it
///
/// Note: handLandmarks are normalized 2D-ish with unstable z, so we use poseWorldLandmarks
/// for orientation. handLandmarks should only be used for finger flexion, not palm orientation.
bool _shouldFlipPalmNormal(
  MixamoPoint? poseWrist,
  MixamoPoint? poseIndex,
  MixamoPoint? posePinky,
  MixamoPoint? poseElbow,
) {
  if (poseWrist == null ||
      poseIndex == null ||
      posePinky == null ||
      poseElbow == null) {
    return false; // Default: no flip
  }

  // Use poseWorldLandmarks (stable 3D world coordinates) for palm orientation
  // vAcross: ngang lòng bàn tay (index → pinky)
  final vAcross = Vec3.clone(posePinky.position)..sub(poseIndex.position);
  if (vAcross.lengthSq < 1e-6) return false;

  // vForward: dọc bàn tay (wrist → index)
  final vForward = Vec3.clone(poseIndex.position)..sub(poseWrist.position);
  if (vForward.lengthSq < 1e-6) return false;

  // Palm normal: cross(vAcross, vForward)
  // Using poseWorldLandmarks ensures stable 3D coordinates (no unstable z from normalized handLandmarks)
  final palmNormal = Vec3.clone(vAcross)..cross(vForward);
  if (palmNormal.lengthSq < 1e-6) return false; // Vectors are parallel
  palmNormal.normalize();

  // Elbow direction: elbow → wrist (in world coordinates, already axis-adjusted)
  final elbowDirection = Vec3.clone(poseWrist.position)
    ..sub(poseElbow.position);
  if (elbowDirection.lengthSq < 1e-6) return false;
  elbowDirection.normalize();

  // Disambiguate: if palm normal points toward elbow (positive dot product),
  // it means palm is facing toward elbow, so we need to flip Z axis
  final dotProduct = palmNormal.dot(elbowDirection);
  // If dot product > 0: palm normal points in same direction as elbow direction
  // (palm facing toward elbow) → need to flip Z axis
  // If dot product < 0: palm normal points away from elbow → no flip needed
  return dotProduct > 0.0;
}

/// Convert hand landmark from normalized image coordinates to world coordinates.
/// Hand landmarks are in normalized image space (0-1 range), need to be converted
/// to world coordinates by aligning with pose wrist and scaling relative distances.
///
/// Strategy: Calculate relative offsets from hand wrist, scale based on pose landmarks,
/// then apply to poseWorld wrist position.
/// Uses shouldFlipPalmZ parameter (calculated from poseWorldLandmarks) to adjust Z axis.
MixamoPoint? _convertHandLandmarkToWorld(
  dynamic handLandmark,
  dynamic handWristLandmark, // Hand wrist (index 0) for reference
  MixamoPoint? poseWrist, // Pose world wrist position (anchor point)
  MixamoPoint? poseElbow, // Pose world elbow (for scale calculation)
  bool
      shouldFlipPalmZ, // Whether to flip Z axis (from palm orientation detection)
) {
  if (poseWrist == null || handWristLandmark == null) return null;

  double getValue(dynamic obj, String key) {
    if (obj is Map) {
      return (obj[key] as num?)?.toDouble() ?? 0.0;
    }
    try {
      return (obj as dynamic)[key] as double;
    } catch (_) {
      return 0.0;
    }
  }

  // Get normalized coordinates
  final handX = getValue(handLandmark, 'x');
  final handY = getValue(handLandmark, 'y');
  final handZ = getValue(handLandmark, 'z');
  final wristX = getValue(handWristLandmark, 'x');
  final wristY = getValue(handWristLandmark, 'y');
  final wristZ = getValue(handWristLandmark, 'z');

  // Calculate relative offsets in normalized space
  final offsetX = handX - wristX;
  final offsetY = handY - wristY;
  final offsetZ = handZ - wristZ;

  // Calculate scale factor from pose landmarks (elbow to wrist distance)
  // Typical hand span in normalized space is ~0.05-0.15
  // Typical elbow-wrist distance in world space is ~0.25-0.35m
  double scaleFactor = 0.25; // Default scale: 0.25m per normalized unit
  if (poseElbow != null) {
    final elbowWristDist = poseWrist.position.distanceTo(poseElbow.position);
    // Hand span is roughly 1/3 to 1/2 of forearm length
    // Normalized hand span is ~0.1, so scale = (elbow-wrist dist) / 0.1 * hand_ratio
    final handToForearmRatio = 0.4; // Hand span is ~40% of forearm length
    final normalizedHandSpan = 0.1; // Typical normalized hand span
    scaleFactor = (elbowWristDist / normalizedHandSpan) * handToForearmRatio;
    // Clamp to reasonable range
    scaleFactor = scaleFactor.clamp(0.1, 1.0);
  }

  // Convert normalized offsets to world offsets
  final worldOffsetX = offsetX * scaleFactor;
  final worldOffsetY = offsetY * scaleFactor;
  final worldOffsetZ = offsetZ * scaleFactor;

  // Apply axis adjustments (match _toVec3() for pose landmarks)
  // MediaPipe coordinates need to be adjusted: y=-y, z=-z
  final adjustedOffsetY = -worldOffsetY;
  var adjustedOffsetZ = -worldOffsetZ;

  // Apply palm orientation flip (calculated from poseWorldLandmarks, passed as parameter)
  // If palm normal points toward elbow, flip Z axis to correct orientation
  if (shouldFlipPalmZ) {
    adjustedOffsetZ =
        -adjustedOffsetZ; // Double flip = back to original direction
  }

  // Apply to pose wrist position (which is already axis-adjusted)
  final worldPos = Vec3(
    poseWrist.position.x + worldOffsetX,
    poseWrist.position.y + adjustedOffsetY,
    poseWrist.position.z + adjustedOffsetZ,
  );

  return MixamoPoint(position: worldPos, visibility: 1.0);
}

MixamoPoint? _averagePoints(List<MixamoPoint?> points) {
  final filtered = points.where((p) => p != null).cast<MixamoPoint>().toList();
  if (filtered.isEmpty) return null;
  final pos = Vec3();
  double vis = 0;
  for (final p in filtered) {
    pos.add(p.position);
    vis += p.visibility;
  }
  pos.scale(1 / filtered.length);
  vis /= filtered.length;
  return MixamoPoint(position: pos, visibility: vis);
}

MixamoPoint? _getPoint(List<dynamic> landmarks, int index) {
  if (index < 0 || index >= landmarks.length) return null;
  final lm = landmarks[index];

  // Handle both Map (from JSON) and object with properties
  double getVisibility(dynamic obj) {
    // Check if it's any kind of Map first - use [] operator, never use .visibility on Map
    if (obj is Map) {
      final vis = obj['visibility'];
      if (vis != null && vis is num) {
        return vis.toDouble();
      }
      return 1.0;
    }
    // For object types (like LandmarkPoint from pose landmarks)
    // Use noSuchMethod to safely access property
    try {
      // Use dynamic invocation only if not a Map
      final vis = (obj as dynamic).visibility;
      if (vis != null && vis is num) {
        return vis.toDouble();
      }
      return 1.0;
    } catch (e) {
      return 1.0;
    }
  }

  final visibility = getVisibility(lm);
  return MixamoPoint(position: _toVec3(lm), visibility: visibility);
}

List<MixamoPoint> _createFingerChain(
  MixamoPoint? base,
  MixamoPoint? tip, {
  int segments = 4,
}) {
  if (base == null || tip == null) return const [];
  final List<MixamoPoint> chain = [];
  for (int i = 1; i <= segments; i++) {
    final t = i / segments;
    final pos = Vec3.clone(base.position)
      ..add(
        Vec3.clone(tip.position)
          ..sub(base.position)
          ..scale(t),
      );
    final vis =
        (base.visibility <= tip.visibility) ? base.visibility : tip.visibility;
    chain.add(MixamoPoint(position: pos, visibility: vis));
  }
  return chain;
}

/// Build Mixamo-like pose from MediaPipe world landmarks.
/// Optionally uses hand landmarks from MediaPipe Holistic for more accurate finger tracking.
MixamoPose buildMixamoPose({
  required List<dynamic> landmarksWorld,
  List<dynamic>? leftHandLandmarks,
  List<dynamic>? rightHandLandmarks,
}) {
  if (landmarksWorld.isEmpty) return {};

  final leftHip = _getPoint(landmarksWorld, PoseLandmarkIndex.leftHip);
  final rightHip = _getPoint(landmarksWorld, PoseLandmarkIndex.rightHip);
  final leftShoulder =
      _getPoint(landmarksWorld, PoseLandmarkIndex.leftShoulder);
  final rightShoulder =
      _getPoint(landmarksWorld, PoseLandmarkIndex.rightShoulder);
  final leftEyeCenter = _getPoint(landmarksWorld, PoseLandmarkIndex.leftEye);
  final rightEyeCenter = _getPoint(landmarksWorld, PoseLandmarkIndex.rightEye);
  final leftEar = _getPoint(landmarksWorld, PoseLandmarkIndex.leftEar);
  final rightEar = _getPoint(landmarksWorld, PoseLandmarkIndex.rightEar);
  final leftWrist = _getPoint(landmarksWorld, PoseLandmarkIndex.leftWrist);
  final rightWrist = _getPoint(landmarksWorld, PoseLandmarkIndex.rightWrist);
  final leftPinky = _getPoint(landmarksWorld, PoseLandmarkIndex.leftPinky);
  final rightPinky = _getPoint(landmarksWorld, PoseLandmarkIndex.rightPinky);
  final leftIndex = _getPoint(landmarksWorld, PoseLandmarkIndex.leftIndex);
  final rightIndex = _getPoint(landmarksWorld, PoseLandmarkIndex.rightIndex);
  final leftThumb = _getPoint(landmarksWorld, PoseLandmarkIndex.leftThumb);
  final rightThumb = _getPoint(landmarksWorld, PoseLandmarkIndex.rightThumb);

  final hips = _averagePoints([leftHip, rightHip]);
  final neck = _averagePoints([leftShoulder, rightShoulder]);
  MixamoPoint? head = _averagePoints([leftEar, rightEar]) ??
      _clonePoint(_getPoint(landmarksWorld, PoseLandmarkIndex.nose));

  final mixamoPose = <String, MixamoPoint>{};
  if (hips != null) mixamoPose['Hips'] = _clonePoint(hips)!;
  if (neck != null) mixamoPose['Neck'] = _clonePoint(neck)!;
  if (head != null) mixamoPose['Head'] = _clonePoint(head)!;

  if (leftEyeCenter != null) {
    mixamoPose['LeftEye'] = _clonePoint(leftEyeCenter)!;
  }
  if (rightEyeCenter != null) {
    mixamoPose['RightEye'] = _clonePoint(rightEyeCenter)!;
  }

  MixamoPoint? makeHeadTopEnd() {
    if (neck == null || head == null) return null;
    final dir = Vec3.clone(head.position)..sub(neck.position);
    if (dir.lengthSq == 0) {
      return MixamoPoint(
        position: Vec3.clone(head.position),
        visibility: head.visibility,
      );
    }
    final pos = Vec3.clone(head.position)..add(dir.scale(0.3));
    return MixamoPoint(position: pos, visibility: head.visibility);
  }

  final headTopEnd = makeHeadTopEnd();
  if (headTopEnd != null) {
    mixamoPose['HeadTop_End'] = headTopEnd;
  }

  final spine1 = _averagePoints([hips, neck]);
  final spine = _averagePoints([hips, spine1]);
  final spine2 = _averagePoints([spine1, neck]);
  if (spine1 != null) mixamoPose['Spine1'] = _clonePoint(spine1)!;
  if (spine != null) mixamoPose['Spine'] = _clonePoint(spine)!;
  if (spine2 != null) mixamoPose['Spine2'] = _clonePoint(spine2)!;

  if (leftShoulder != null) mixamoPose['LeftArm'] = _clonePoint(leftShoulder)!;
  if (rightShoulder != null) {
    mixamoPose['RightArm'] = _clonePoint(rightShoulder)!;
  }

  final leftForeArm = _clonePoint(
    _getPoint(landmarksWorld, PoseLandmarkIndex.leftElbow),
  );
  if (leftForeArm != null) {
    mixamoPose['LeftForeArm'] = leftForeArm;
  }
  final rightForeArm = _clonePoint(
    _getPoint(landmarksWorld, PoseLandmarkIndex.rightElbow),
  );
  if (rightForeArm != null) {
    mixamoPose['RightForeArm'] = rightForeArm;
  }

  if (leftWrist != null) mixamoPose['LeftHand'] = _clonePoint(leftWrist)!;
  if (rightWrist != null) mixamoPose['RightHand'] = _clonePoint(rightWrist)!;

  // Fingers - use hand landmarks if available, otherwise fallback to pose landmarks
  void assignFinger(String prefix, List<MixamoPoint> chain,
      {int maxSegments = 4}) {
    for (int i = 0; i < chain.length && i < maxSegments; i++) {
      final p = chain[i];
      mixamoPose['$prefix${i + 1}'] = MixamoPoint(
        position: Vec3.clone(p.position),
        visibility: p.visibility,
      );
    }
  }

  // Left hand fingers - Full animation restored
  if (leftHandLandmarks != null &&
      leftHandLandmarks.isNotEmpty &&
      leftWrist != null) {
    // Use detailed hand landmarks from MediaPipe Holistic
    // Convert from normalized image coordinates to world coordinates
    final leftHandWristRaw = leftHandLandmarks[HandLandmarkIndex.wrist];
    final leftElbow = _getPoint(landmarksWorld, PoseLandmarkIndex.leftElbow);

    // Wrist position: Always use poseWorld wrist (world coordinates)
    // Hand landmarks are only used for finger rotations/positions relative to wrist
    // This avoids coordinate system mismatch (hand landmarks are normalized, poseWorld is world coords)
    mixamoPose['LeftHand'] = _clonePoint(leftWrist)!;

    // Calculate palm orientation using poseWorldLandmarks (stable 3D coordinates)
    // Use poseWorldLandmarks for palm orientation, not handLandmarks (unstable z)
    final leftIndex = _getPoint(landmarksWorld, PoseLandmarkIndex.leftIndex);
    final leftPinky = _getPoint(landmarksWorld, PoseLandmarkIndex.leftPinky);
    final shouldFlipLeftPalmZ =
        _shouldFlipPalmNormal(leftWrist, leftIndex, leftPinky, leftElbow);

    // Convert hand landmarks from normalized coordinates to world coordinates
    // Helper function to convert hand landmark to world space
    MixamoPoint? convertHand(int index) {
      if (index < 0 || index >= leftHandLandmarks.length) return null;
      return _convertHandLandmarkToWorld(
        leftHandLandmarks[index],
        leftHandWristRaw,
        leftWrist,
        leftElbow,
        shouldFlipLeftPalmZ,
      );
    }

    // Thumb: MCP -> IP -> TIP (3 segments)
    final leftHandThumbMcp = convertHand(HandLandmarkIndex.thumbMcp);
    final leftHandThumbIp = convertHand(HandLandmarkIndex.thumbIp);
    final leftHandThumbTip = convertHand(HandLandmarkIndex.thumbTip);
    if (leftHandThumbMcp != null &&
        leftHandThumbIp != null &&
        leftHandThumbTip != null) {
      final thumbChain = [
        _clonePoint(leftHandThumbMcp)!,
        _clonePoint(leftHandThumbIp)!,
        _clonePoint(leftHandThumbTip)!,
      ];
      assignFinger('LeftHandThumb', thumbChain);
    }

    // Index finger: MCP -> PIP -> DIP -> TIP (4 segments)
    final leftHandIndexMcp = convertHand(HandLandmarkIndex.indexFingerMcp);
    final leftHandIndexPip = convertHand(HandLandmarkIndex.indexFingerPip);
    final leftHandIndexDip = convertHand(HandLandmarkIndex.indexFingerDip);
    final leftHandIndexTip = convertHand(HandLandmarkIndex.indexFingerTip);
    if (leftHandIndexMcp != null &&
        leftHandIndexPip != null &&
        leftHandIndexDip != null &&
        leftHandIndexTip != null) {
      final indexChain = [
        _clonePoint(leftHandIndexMcp)!,
        _clonePoint(leftHandIndexPip)!,
        _clonePoint(leftHandIndexDip)!,
        _clonePoint(leftHandIndexTip)!,
      ];
      assignFinger('LeftHandIndex', indexChain);
    }

    // Middle finger: MCP -> PIP -> DIP -> TIP (4 segments)
    final leftHandMiddleMcp = convertHand(HandLandmarkIndex.middleFingerMcp);
    final leftHandMiddlePip = convertHand(HandLandmarkIndex.middleFingerPip);
    final leftHandMiddleDip = convertHand(HandLandmarkIndex.middleFingerDip);
    final leftHandMiddleTip = convertHand(HandLandmarkIndex.middleFingerTip);
    if (leftHandMiddleMcp != null &&
        leftHandMiddlePip != null &&
        leftHandMiddleDip != null &&
        leftHandMiddleTip != null) {
      final middleChain = [
        _clonePoint(leftHandMiddleMcp)!,
        _clonePoint(leftHandMiddlePip)!,
        _clonePoint(leftHandMiddleDip)!,
        _clonePoint(leftHandMiddleTip)!,
      ];
      assignFinger('LeftHandMiddle', middleChain);
    }

    // Ring finger: MCP -> PIP -> DIP -> TIP (4 segments)
    final leftHandRingMcp = convertHand(HandLandmarkIndex.ringFingerMcp);
    final leftHandRingPip = convertHand(HandLandmarkIndex.ringFingerPip);
    final leftHandRingDip = convertHand(HandLandmarkIndex.ringFingerDip);
    final leftHandRingTip = convertHand(HandLandmarkIndex.ringFingerTip);
    if (leftHandRingMcp != null &&
        leftHandRingPip != null &&
        leftHandRingDip != null &&
        leftHandRingTip != null) {
      final ringChain = [
        _clonePoint(leftHandRingMcp)!,
        _clonePoint(leftHandRingPip)!,
        _clonePoint(leftHandRingDip)!,
        _clonePoint(leftHandRingTip)!,
      ];
      assignFinger('LeftHandRing', ringChain);
    }

    // Pinky finger: MCP -> PIP -> DIP -> TIP (4 segments)
    final leftHandPinkyMcp = convertHand(HandLandmarkIndex.pinkyMcp);
    final leftHandPinkyPip = convertHand(HandLandmarkIndex.pinkyPip);
    final leftHandPinkyDip = convertHand(HandLandmarkIndex.pinkyDip);
    final leftHandPinkyTip = convertHand(HandLandmarkIndex.pinkyTip);
    if (leftHandPinkyMcp != null &&
        leftHandPinkyPip != null &&
        leftHandPinkyDip != null &&
        leftHandPinkyTip != null) {
      final pinkyChain = [
        _clonePoint(leftHandPinkyMcp)!,
        _clonePoint(leftHandPinkyPip)!,
        _clonePoint(leftHandPinkyDip)!,
        _clonePoint(leftHandPinkyTip)!,
      ];
      assignFinger('LeftHandPinky', pinkyChain);
    }
  } else {
    // Fallback to pose landmarks estimation
    final leftThumbChain = _createFingerChain(leftWrist, leftThumb);
    final leftIndexChain = _createFingerChain(leftWrist, leftIndex);
    final leftPinkyChain = _createFingerChain(leftWrist, leftPinky);
    final leftMiddleTip = _averagePoints([leftIndex, leftPinky]);
    final leftRingTip = _averagePoints([leftIndex, leftPinky]);
    final leftMiddleChain = _createFingerChain(leftWrist, leftMiddleTip);
    final leftRingChain = _createFingerChain(leftWrist, leftRingTip);

    assignFinger('LeftHandThumb', leftThumbChain);
    assignFinger('LeftHandIndex', leftIndexChain);
    assignFinger('LeftHandMiddle', leftMiddleChain);
    assignFinger('LeftHandRing', leftRingChain);
    assignFinger('LeftHandPinky', leftPinkyChain);
  }

  // Right hand fingers - Full animation restored
  if (rightHandLandmarks != null &&
      rightHandLandmarks.isNotEmpty &&
      rightWrist != null) {
    // Use detailed hand landmarks from MediaPipe Holistic
    // Convert from normalized image coordinates to world coordinates
    final rightHandWristRaw = rightHandLandmarks[HandLandmarkIndex.wrist];
    final rightElbow = _getPoint(landmarksWorld, PoseLandmarkIndex.rightElbow);

    // Wrist position: Always use poseWorld wrist (world coordinates)
    mixamoPose['RightHand'] = _clonePoint(rightWrist)!;

    // Calculate palm orientation using poseWorldLandmarks (stable 3D coordinates)
    // Use poseWorldLandmarks for palm orientation, not handLandmarks (unstable z)
    final rightIndex = _getPoint(landmarksWorld, PoseLandmarkIndex.rightIndex);
    final rightPinky = _getPoint(landmarksWorld, PoseLandmarkIndex.rightPinky);
    final shouldFlipRightPalmZ =
        _shouldFlipPalmNormal(rightWrist, rightIndex, rightPinky, rightElbow);

    // Convert hand landmarks from normalized coordinates to world coordinates
    // Helper function to convert hand landmark to world space
    MixamoPoint? convertHand(int index) {
      if (index < 0 || index >= rightHandLandmarks.length) return null;
      return _convertHandLandmarkToWorld(
        rightHandLandmarks[index],
        rightHandWristRaw,
        rightWrist,
        rightElbow,
        shouldFlipRightPalmZ,
      );
    }

    // Thumb: MCP -> IP -> TIP (3 segments)
    final rightHandThumbMcp = convertHand(HandLandmarkIndex.thumbMcp);
    final rightHandThumbIp = convertHand(HandLandmarkIndex.thumbIp);
    final rightHandThumbTip = convertHand(HandLandmarkIndex.thumbTip);
    if (rightHandThumbMcp != null &&
        rightHandThumbIp != null &&
        rightHandThumbTip != null) {
      final thumbChain = [
        _clonePoint(rightHandThumbMcp)!,
        _clonePoint(rightHandThumbIp)!,
        _clonePoint(rightHandThumbTip)!,
      ];
      assignFinger('RightHandThumb', thumbChain);
    }

    // Index finger: MCP -> PIP -> DIP -> TIP (4 segments)
    final rightHandIndexMcp = convertHand(HandLandmarkIndex.indexFingerMcp);
    final rightHandIndexPip = convertHand(HandLandmarkIndex.indexFingerPip);
    final rightHandIndexDip = convertHand(HandLandmarkIndex.indexFingerDip);
    final rightHandIndexTip = convertHand(HandLandmarkIndex.indexFingerTip);
    if (rightHandIndexMcp != null &&
        rightHandIndexPip != null &&
        rightHandIndexDip != null &&
        rightHandIndexTip != null) {
      final indexChain = [
        _clonePoint(rightHandIndexMcp)!,
        _clonePoint(rightHandIndexPip)!,
        _clonePoint(rightHandIndexDip)!,
        _clonePoint(rightHandIndexTip)!,
      ];
      assignFinger('RightHandIndex', indexChain);
    }

    // Middle finger: MCP -> PIP -> DIP -> TIP (4 segments)
    final rightHandMiddleMcp = convertHand(HandLandmarkIndex.middleFingerMcp);
    final rightHandMiddlePip = convertHand(HandLandmarkIndex.middleFingerPip);
    final rightHandMiddleDip = convertHand(HandLandmarkIndex.middleFingerDip);
    final rightHandMiddleTip = convertHand(HandLandmarkIndex.middleFingerTip);
    if (rightHandMiddleMcp != null &&
        rightHandMiddlePip != null &&
        rightHandMiddleDip != null &&
        rightHandMiddleTip != null) {
      final middleChain = [
        _clonePoint(rightHandMiddleMcp)!,
        _clonePoint(rightHandMiddlePip)!,
        _clonePoint(rightHandMiddleDip)!,
        _clonePoint(rightHandMiddleTip)!,
      ];
      assignFinger('RightHandMiddle', middleChain);
    }

    // Ring finger: MCP -> PIP -> DIP -> TIP (4 segments)
    final rightHandRingMcp = convertHand(HandLandmarkIndex.ringFingerMcp);
    final rightHandRingPip = convertHand(HandLandmarkIndex.ringFingerPip);
    final rightHandRingDip = convertHand(HandLandmarkIndex.ringFingerDip);
    final rightHandRingTip = convertHand(HandLandmarkIndex.ringFingerTip);
    if (rightHandRingMcp != null &&
        rightHandRingPip != null &&
        rightHandRingDip != null &&
        rightHandRingTip != null) {
      final ringChain = [
        _clonePoint(rightHandRingMcp)!,
        _clonePoint(rightHandRingPip)!,
        _clonePoint(rightHandRingDip)!,
        _clonePoint(rightHandRingTip)!,
      ];
      assignFinger('RightHandRing', ringChain);
    }

    // Pinky finger: MCP -> PIP -> DIP -> TIP (4 segments)
    final rightHandPinkyMcp = convertHand(HandLandmarkIndex.pinkyMcp);
    final rightHandPinkyPip = convertHand(HandLandmarkIndex.pinkyPip);
    final rightHandPinkyDip = convertHand(HandLandmarkIndex.pinkyDip);
    final rightHandPinkyTip = convertHand(HandLandmarkIndex.pinkyTip);
    if (rightHandPinkyMcp != null &&
        rightHandPinkyPip != null &&
        rightHandPinkyDip != null &&
        rightHandPinkyTip != null) {
      final pinkyChain = [
        _clonePoint(rightHandPinkyMcp)!,
        _clonePoint(rightHandPinkyPip)!,
        _clonePoint(rightHandPinkyDip)!,
        _clonePoint(rightHandPinkyTip)!,
      ];
      assignFinger('RightHandPinky', pinkyChain);
    }
  } else {
    // Fallback to pose landmarks estimation
    final rightThumbChain = _createFingerChain(rightWrist, rightThumb);
    final rightIndexChain = _createFingerChain(rightWrist, rightIndex);
    final rightPinkyChain = _createFingerChain(rightWrist, rightPinky);
    final rightMiddleTip = _averagePoints([rightIndex, rightPinky]);
    final rightRingTip = _averagePoints([rightIndex, rightPinky]);
    final rightMiddleChain = _createFingerChain(rightWrist, rightMiddleTip);
    final rightRingChain = _createFingerChain(rightWrist, rightRingTip);

    assignFinger('RightHandThumb', rightThumbChain);
    assignFinger('RightHandIndex', rightIndexChain);
    assignFinger('RightHandMiddle', rightMiddleChain);
    assignFinger('RightHandRing', rightRingChain);
    assignFinger('RightHandPinky', rightPinkyChain);
  }

  // Legs & feet
  final leftKnee = _getPoint(landmarksWorld, PoseLandmarkIndex.leftKnee);
  final rightKnee = _getPoint(landmarksWorld, PoseLandmarkIndex.rightKnee);
  final leftAnkle = _getPoint(landmarksWorld, PoseLandmarkIndex.leftAnkle);
  final rightAnkle = _getPoint(landmarksWorld, PoseLandmarkIndex.rightAnkle);
  final leftToeBase =
      _getPoint(landmarksWorld, PoseLandmarkIndex.leftFootIndex);
  final rightToeBase =
      _getPoint(landmarksWorld, PoseLandmarkIndex.rightFootIndex);

  if (leftHip != null) mixamoPose['LeftUpLeg'] = _clonePoint(leftHip)!;
  if (rightHip != null) mixamoPose['RightUpLeg'] = _clonePoint(rightHip)!;
  if (leftKnee != null) mixamoPose['LeftLeg'] = _clonePoint(leftKnee)!;
  if (rightKnee != null) mixamoPose['RightLeg'] = _clonePoint(rightKnee)!;
  if (leftAnkle != null) mixamoPose['LeftFoot'] = _clonePoint(leftAnkle)!;
  if (rightAnkle != null) mixamoPose['RightFoot'] = _clonePoint(rightAnkle)!;
  if (leftToeBase != null) {
    mixamoPose['LeftToeBase'] = _clonePoint(leftToeBase)!;
  }
  if (rightToeBase != null) {
    mixamoPose['RightToeBase'] = _clonePoint(rightToeBase)!;
  }

  MixamoPoint? makeToeEnd(MixamoPoint? ankle, MixamoPoint? base) {
    if (ankle == null || base == null) return null;
    final dir = Vec3.clone(base.position)..sub(ankle.position);
    if (dir.lengthSq == 0) {
      return MixamoPoint(
        position: Vec3.clone(base.position),
        visibility: base.visibility,
      );
    }
    final pos = Vec3.clone(base.position)..add(dir.scale(0.3));
    final vis = (ankle.visibility <= base.visibility)
        ? ankle.visibility
        : base.visibility;
    return MixamoPoint(position: pos, visibility: vis);
  }

  final leftToeEnd = makeToeEnd(leftAnkle, leftToeBase);
  final rightToeEnd = makeToeEnd(rightAnkle, rightToeBase);
  if (leftToeEnd != null) {
    mixamoPose['LeftToe_End'] = leftToeEnd;
  }
  if (rightToeEnd != null) {
    mixamoPose['RightToe_End'] = rightToeEnd;
  }

  return mixamoPose;
}

/// Get appropriate filter parameters based on body part and visibility.
/// Option 5: Adaptive filtering with body part-specific parameters and visibility adjustment.
OneEuroFilterVector3 _getFilterForBodyPart(String key, double visibility) {
  double baseBeta;

  // Different base beta for different body parts
  // Hands/Fingers: More responsive (faster movements) - Improved for better hand tracking
  if (key.contains('Hand') ||
      key.contains('Finger') ||
      key.contains('Thumb') ||
      key.contains('Pinky') ||
      key.contains('Index') ||
      key.contains('Middle') ||
      key.contains('Ring')) {
    baseBeta =
        0.45; // Hands: More responsive for better finger tracking (reduced lag)
  }
  // Head/Neck: Moderate responsiveness
  else if (key.contains('Head') ||
      key.contains('Neck') ||
      key.contains('Eye') ||
      key.contains('Ear')) {
    baseBeta = 0.15; // Head: moderate
  }
  // Body core (Hips, Spine): Smoother (slower, stable movements)
  else if (key.contains('Hips') ||
      key.contains('Spine') ||
      key.contains('Spine1') ||
      key.contains('Spine2')) {
    baseBeta = 0.05; // Core: smooth
  }
  // Default: Balanced
  else {
    baseBeta = 0.1; // Default: balanced
  }

  // Adjust based on visibility
  // Low visibility (< 0.7) = less reliable data = more responsive (higher beta)
  // High visibility (>= 0.7) = reliable data = can smooth more (lower beta)
  if (visibility < 0.7) {
    baseBeta *= 1.5; // Low visibility: more responsive
  }

  // Clamp beta to reasonable range
  final finalBeta = baseBeta.clamp(0.05, 0.5);

  // Lower minCutoff for hands/fingers for smoother tracking
  final minCutoff = (key.contains('Hand') ||
          key.contains('Finger') ||
          key.contains('Thumb') ||
          key.contains('Pinky') ||
          key.contains('Index') ||
          key.contains('Middle') ||
          key.contains('Ring'))
      ? 0.003 // Hands: Lower cutoff for smoother tracking and less lag
      : 0.01; // Default: Standard cutoff

  return OneEuroFilterVector3(
    minCutoff: minCutoff,
    beta: finalBeta,
    dCutoff: 1.0,
  );
}

/// Apply OneEuro filters to all pose points (world space smoothing).
/// Option 5: Uses adaptive filtering with body part-specific parameters and visibility adjustment.
void smoothMixamoPose(
  MixamoPose pose,
  double t,
  Map<String, OneEuroFilterVector3> filters,
) {
  void smooth(String key) {
    final p = pose[key];
    if (p == null) return;
    filters.putIfAbsent(
      key,
      () => _getFilterForBodyPart(key, p.visibility),
    );
    final f = filters[key]!;
    final smoothed = f.filter(t, p.position);
    p.position
      ..x = smoothed.x
      ..y = smoothed.y
      ..z = smoothed.z;
  }

  for (final key in pose.keys) {
    smooth(key);
  }
}
