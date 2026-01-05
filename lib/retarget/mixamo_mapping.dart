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

/// Landmark indices (MediaPipe Hands).
class HandLandmarkIndex {
  static const int wrist = 0;
  static const int thumbCMC = 1;
  static const int thumbMCP = 2;
  static const int thumbIP = 3;
  static const int thumbTip = 4;
  static const int indexMCP = 5;
  static const int indexPIP = 6;
  static const int indexDIP = 7;
  static const int indexTip = 8;
  static const int middleMCP = 9;
  static const int middlePIP = 10;
  static const int middleDIP = 11;
  static const int middleTip = 12;
  static const int ringMCP = 13;
  static const int ringPIP = 14;
  static const int ringDIP = 15;
  static const int ringTip = 16;
  static const int pinkyMCP = 17;
  static const int pinkyPIP = 18;
  static const int pinkyDIP = 19;
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
  final v = Vec3(
    (landmark.x as num).toDouble(),
    (landmark.y as num).toDouble(),
    (landmark.z as num).toDouble(),
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
  final visibility =
      (lm.visibility is num) ? (lm.visibility as num).toDouble() : 1.0;
  return MixamoPoint(position: _toVec3(lm), visibility: visibility);
}

/// Convert hand landmark to Vec3.
/// Applies same Y/Z axis flip as pose landmarks for consistency.
MixamoPoint? _getHandPoint(List<dynamic> handLandmarks, int index) {
  if (handLandmarks.isEmpty || index < 0 || index >= handLandmarks.length) {
    return null;
  }
  final lm = handLandmarks[index];
  final visibility =
      (lm.visibility is num) ? (lm.visibility as num).toDouble() : 1.0;

  final v = Vec3(
    (lm.x as num).toDouble(),
    (lm.y as num).toDouble(),
    (lm.z as num).toDouble(),
  );
  // Apply same axis adjustments as pose landmarks
  v.y = -v.y;
  v.z = -v.z;

  return MixamoPoint(position: v, visibility: visibility);
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

/// Adjusts Z-depth of hand landmarks based on palm aspect ratio.
/// Inspired by SystemAnimatorOnline's hand Z correction algorithm.
/// This helps when hands are viewed from the side (palm facing camera).
void _adjustHandZDepth(List<dynamic> handLandmarks) {
  if (handLandmarks.isEmpty || handLandmarks.length < 21) return;

  // Palm landmarks: 0=wrist, 1=thumb_cmc, 5=index_mcp, 9=middle_mcp, 13=ring_mcp, 17=pinky_mcp
  final wrist = handLandmarks[0];
  final thumbCmc = handLandmarks[1];
  final pinkyMcp = handLandmarks[17];
  final middleMcp = handLandmarks[9];

  // Calculate palm width (thumb to pinky) and height (wrist to middle)
  final palmWidth = Vec3(
    (thumbCmc.x - pinkyMcp.x).toDouble(),
    (thumbCmc.y - pinkyMcp.y).toDouble(),
    (thumbCmc.z - pinkyMcp.z).toDouble(),
  );
  final palmHeight = Vec3(
    (wrist.x - middleMcp.x).toDouble(),
    (wrist.y - middleMcp.y).toDouble(),
    (wrist.z - middleMcp.z).toDouble(),
  );

  final wPalm = palmWidth.length;
  final hPalm = palmHeight.length;
  if (wPalm < 0.001 || hPalm < 0.001) return;

  // Expected ratio is ~1.25-1.75 when palm faces camera
  // If ratio is outside this range, Z-depth is likely incorrect
  double aspectRatio = hPalm / wPalm;

  // Clamp to reasonable range
  if (aspectRatio < 1.25) {
    aspectRatio = 1.25;
  } else if (aspectRatio > 1.75) {
    aspectRatio = 1.75;
  } else {
    return; // Already in good range, no adjustment needed
  }

  // Calculate Z adjustment factor based on aspect ratio deviation
  final zAdjust = aspectRatio * aspectRatio;
  final zScale = _calculateZScale(palmWidth, palmHeight, zAdjust);

  if (zScale.abs() > 0.01 && zScale < 1.5) {
    // Apply Z adjustment to all hand landmarks
    for (final lm in handLandmarks) {
      lm.z = (lm.z as num) * zScale;
    }
  }
}

double _calculateZScale(Vec3 palmWidth, Vec3 palmHeight, double targetRatio) {
  // Solve for Z scale that makes aspect ratio match target
  // palm_height^2 / target = palm_width^2
  // (h_xy + h_z*s)^2 / target = (w_xy + w_z*s)^2
  final hXy = palmHeight.x * palmHeight.x + palmHeight.y * palmHeight.y;
  final wXy = palmWidth.x * palmWidth.x + palmWidth.y * palmWidth.y;
  final hZ = palmHeight.z * palmHeight.z;
  final wZ = palmWidth.z * palmWidth.z;

  if ((wZ - hZ / targetRatio).abs() < 0.0001) return 1.0;

  final s2 = ((hXy / targetRatio) - wXy) / (wZ - hZ / targetRatio);
  if (s2 < 0) return 1.0;

  return s2.clamp(0.5, 1.5);
}

/// Build Mixamo-like pose from MediaPipe world landmarks.
MixamoPose buildMixamoPose({
  required List<dynamic> landmarksWorld,
  List<dynamic> leftHandWorldLandmarks = const [],
  List<dynamic> rightHandWorldLandmarks = const [],
}) {
  if (landmarksWorld.isEmpty) return {};

  // Apply Z-depth correction for hand landmarks (improves side-view accuracy)
  _adjustHandZDepth(leftHandWorldLandmarks);
  _adjustHandZDepth(rightHandWorldLandmarks);

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

  // Store ear landmarks for head yaw/roll calculation (critical for proper head orientation)
  if (leftEar != null) {
    mixamoPose['LeftEar'] = _clonePoint(leftEar)!;
  }
  if (rightEar != null) {
    mixamoPose['RightEar'] = _clonePoint(rightEar)!;
  }

  // Store nose for head pitch calculation
  final nose = _getPoint(landmarksWorld, PoseLandmarkIndex.nose);
  if (nose != null) {
    mixamoPose['Nose'] = _clonePoint(nose)!;
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

  void assignFingerChain({
    required String prefix,
    required List<int> indices,
    required List<dynamic> handLandmarks,
    required MixamoPoint? wristFallback,
    required MixamoPoint? tipFallback,
  }) {
    final points = indices
        .map((i) => _getHandPoint(handLandmarks, i))
        .toList(growable: false);
    if (points.every((p) => p == null)) {
      final chain = _createFingerChain(wristFallback, tipFallback);
      for (int i = 0; i < chain.length && i < 4; i++) {
        final p = chain[i];
        mixamoPose['$prefix${i + 1}'] = MixamoPoint(
          position: Vec3.clone(p.position),
          visibility: p.visibility,
        );
      }
      return;
    }
    for (int i = 0; i < points.length && i < 4; i++) {
      final p = points[i];
      if (p == null) continue;
      mixamoPose['$prefix${i + 1}'] = MixamoPoint(
          position: Vec3.clone(p.position), visibility: p.visibility);
    }
  }

  // Hands and fingers with holistic data (fallback to pose wrist + tips).
  // Palm orientation is handled in retargeter via different cross product order per hand side
  final leftHandWrist =
      _getHandPoint(leftHandWorldLandmarks, HandLandmarkIndex.wrist) ??
          leftWrist;
  final rightHandWrist =
      _getHandPoint(rightHandWorldLandmarks, HandLandmarkIndex.wrist) ??
          rightWrist;

  if (leftHandWrist != null)
    mixamoPose['LeftHand'] = _clonePoint(leftHandWrist)!;
  if (rightHandWrist != null) {
    mixamoPose['RightHand'] = _clonePoint(rightHandWrist)!;
  }

  assignFingerChain(
    prefix: 'LeftHandThumb',
    indices: const [
      HandLandmarkIndex.thumbCMC,
      HandLandmarkIndex.thumbMCP,
      HandLandmarkIndex.thumbIP,
      HandLandmarkIndex.thumbTip,
    ],
    handLandmarks: leftHandWorldLandmarks,
    wristFallback: leftWrist,
    tipFallback: leftThumb,
  );
  assignFingerChain(
    prefix: 'LeftHandIndex',
    indices: const [
      HandLandmarkIndex.indexMCP,
      HandLandmarkIndex.indexPIP,
      HandLandmarkIndex.indexDIP,
      HandLandmarkIndex.indexTip,
    ],
    handLandmarks: leftHandWorldLandmarks,
    wristFallback: leftWrist,
    tipFallback: leftIndex,
  );
  assignFingerChain(
    prefix: 'LeftHandMiddle',
    indices: const [
      HandLandmarkIndex.middleMCP,
      HandLandmarkIndex.middlePIP,
      HandLandmarkIndex.middleDIP,
      HandLandmarkIndex.middleTip,
    ],
    handLandmarks: leftHandWorldLandmarks,
    wristFallback: leftWrist,
    tipFallback: _averagePoints([leftIndex, leftPinky]),
  );
  assignFingerChain(
    prefix: 'LeftHandRing',
    indices: const [
      HandLandmarkIndex.ringMCP,
      HandLandmarkIndex.ringPIP,
      HandLandmarkIndex.ringDIP,
      HandLandmarkIndex.ringTip,
    ],
    handLandmarks: leftHandWorldLandmarks,
    wristFallback: leftWrist,
    tipFallback: _averagePoints([leftIndex, leftPinky]),
  );
  assignFingerChain(
    prefix: 'LeftHandPinky',
    indices: const [
      HandLandmarkIndex.pinkyMCP,
      HandLandmarkIndex.pinkyPIP,
      HandLandmarkIndex.pinkyDIP,
      HandLandmarkIndex.pinkyTip,
    ],
    handLandmarks: leftHandWorldLandmarks,
    wristFallback: leftWrist,
    tipFallback: leftPinky,
  );

  // Right hand finger chains
  // Palm orientation is handled in retargeter via different cross product order
  assignFingerChain(
    prefix: 'RightHandThumb',
    indices: const [
      HandLandmarkIndex.thumbCMC,
      HandLandmarkIndex.thumbMCP,
      HandLandmarkIndex.thumbIP,
      HandLandmarkIndex.thumbTip,
    ],
    handLandmarks: rightHandWorldLandmarks,
    wristFallback: rightWrist,
    tipFallback: rightThumb,
  );
  assignFingerChain(
    prefix: 'RightHandIndex',
    indices: const [
      HandLandmarkIndex.indexMCP,
      HandLandmarkIndex.indexPIP,
      HandLandmarkIndex.indexDIP,
      HandLandmarkIndex.indexTip,
    ],
    handLandmarks: rightHandWorldLandmarks,
    wristFallback: rightWrist,
    tipFallback: rightIndex,
  );
  assignFingerChain(
    prefix: 'RightHandMiddle',
    indices: const [
      HandLandmarkIndex.middleMCP,
      HandLandmarkIndex.middlePIP,
      HandLandmarkIndex.middleDIP,
      HandLandmarkIndex.middleTip,
    ],
    handLandmarks: rightHandWorldLandmarks,
    wristFallback: rightWrist,
    tipFallback: _averagePoints([rightIndex, rightPinky]),
  );
  assignFingerChain(
    prefix: 'RightHandRing',
    indices: const [
      HandLandmarkIndex.ringMCP,
      HandLandmarkIndex.ringPIP,
      HandLandmarkIndex.ringDIP,
      HandLandmarkIndex.ringTip,
    ],
    handLandmarks: rightHandWorldLandmarks,
    wristFallback: rightWrist,
    tipFallback: _averagePoints([rightIndex, rightPinky]),
  );
  assignFingerChain(
    prefix: 'RightHandPinky',
    indices: const [
      HandLandmarkIndex.pinkyMCP,
      HandLandmarkIndex.pinkyPIP,
      HandLandmarkIndex.pinkyDIP,
      HandLandmarkIndex.pinkyTip,
    ],
    handLandmarks: rightHandWorldLandmarks,
    wristFallback: rightWrist,
    tipFallback: rightPinky,
  );

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

/// Apply OneEuro filters to all pose points (world space smoothing).
/// Uses adaptive beta based on body part type and visibility.
/// Inspired by SystemAnimatorOnline's adaptive filtering approach.
void smoothMixamoPose(
  MixamoPose pose,
  double t,
  Map<String, OneEuroFilterVector3> filters,
) {
  // Beta values: higher = more responsive, lower = smoother
  const armBeta = 0.08; // Arms need faster response
  const handBeta = 0.1; // Hands need even faster response
  const bodyBeta = 0.04; // Body/torso can be smoother
  const legBeta = 0.05; // Legs moderate

  double getBetaForKey(String key) {
    if (key.contains('Hand') || key.contains('Finger')) return handBeta;
    if (key.contains('Arm') || key.contains('ForeArm')) return armBeta;
    if (key.contains('Leg') || key.contains('Foot') || key.contains('Toe')) {
      return legBeta;
    }
    return bodyBeta;
  }

  void smooth(String key) {
    final p = pose[key];
    if (p == null) return;

    final beta = getBetaForKey(key);

    filters.putIfAbsent(
      key,
      () => OneEuroFilterVector3(minCutoff: 0.001, beta: beta, dCutoff: 1.0),
    );
    final f = filters[key]!;

    // Adjust beta based on visibility (low visibility = smoother to avoid jitter)
    final visibilityFactor = p.visibility.clamp(0.3, 1.0);
    f.beta = beta * visibilityFactor;

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
