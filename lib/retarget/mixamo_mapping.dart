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
MixamoPose buildMixamoPose({
  required List<dynamic> landmarksWorld,
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

  // Fingers
  final leftThumbChain = _createFingerChain(leftWrist, leftThumb);
  final leftIndexChain = _createFingerChain(leftWrist, leftIndex);
  final leftPinkyChain = _createFingerChain(leftWrist, leftPinky);
  final leftMiddleTip = _averagePoints([leftIndex, leftPinky]);
  final leftRingTip = _averagePoints([leftIndex, leftPinky]);
  final leftMiddleChain = _createFingerChain(leftWrist, leftMiddleTip);
  final leftRingChain = _createFingerChain(leftWrist, leftRingTip);

  void assignFinger(String prefix, List<MixamoPoint> chain) {
    for (int i = 0; i < chain.length && i < 4; i++) {
      final p = chain[i];
      mixamoPose['$prefix${i + 1}'] = MixamoPoint(
        position: Vec3.clone(p.position),
        visibility: p.visibility,
      );
    }
  }

  assignFinger('LeftHandThumb', leftThumbChain);
  assignFinger('LeftHandIndex', leftIndexChain);
  assignFinger('LeftHandMiddle', leftMiddleChain);
  assignFinger('LeftHandRing', leftRingChain);
  assignFinger('LeftHandPinky', leftPinkyChain);

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
      () => OneEuroFilterVector3(minCutoff: 0.01, beta: 0.1, dCutoff: 1.0),
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
