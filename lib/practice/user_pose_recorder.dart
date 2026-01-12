import 'dart:async';
import '../pose/pose_source.dart';
import '../services/pose_api_client.dart';

/// Records user poses from camera.
class UserPoseRecorder {
  final List<FramePose> _recordedPoses = [];
  final PoseSource _poseSource;
  StreamSubscription<PoseFrame>? _subscription;
  bool _isRecording = false;
  int _frameIndex = 0;
  double _estimatedFps = 30.0;
  DateTime? _startTime;

  UserPoseRecorder(this._poseSource);

  /// Start recording user poses from camera.
  Future<void> startRecording() async {
    if (_isRecording) return;

    _recordedPoses.clear();
    _frameIndex = 0;
    _isRecording = true;
    _startTime = DateTime.now();

    await _poseSource.start();

    _subscription?.cancel();
    _subscription = _poseSource.frames.listen((poseFrame) {
      if (!_isRecording) return;
      // If pose detection is not integrated yet, landmarks lists can be empty.
      // Skip frames without landmarks so scoring doesn't become "always 0".
      if (poseFrame.worldLandmarks.isEmpty && poseFrame.imageLandmarks.isEmpty) {
        return;
      }

      // Convert PoseFrame to FramePose
      // PoseFrame.worldLandmarks and imageLandmarks are List<dynamic>
      // Each element should be a Map with x, y, z, visibility
      List<LandmarkPoint> parseLandmarks(List<dynamic> landmarks) {
        return landmarks
            .map((lm) {
              if (lm is Map) {
                return LandmarkPoint(
                  x: ((lm['x'] ?? 0.0) as num).toDouble(),
                  y: ((lm['y'] ?? 0.0) as num).toDouble(),
                  z: ((lm['z'] ?? 0.0) as num).toDouble(),
                  visibility: lm['visibility'] != null
                      ? ((lm['visibility'] as num).toDouble())
                      : null,
                );
              }
              // Fallback if structure is different
              return LandmarkPoint(x: 0.0, y: 0.0, z: 0.0);
            })
            .toList();
      }

      final framePose = FramePose(
        frameIndex: _frameIndex++,
        landmarks: parseLandmarks(poseFrame.imageLandmarks),
        landmarksWorld: parseLandmarks(poseFrame.worldLandmarks),
      );

      _recordedPoses.add(framePose);
    });
  }

  /// Stop recording.
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    _isRecording = false;
    await _subscription?.cancel();
    _subscription = null;

    // Calculate estimated FPS
    if (_startTime != null && _recordedPoses.isNotEmpty) {
      final duration = DateTime.now().difference(_startTime!);
      if (duration.inMilliseconds > 0) {
        _estimatedFps = _recordedPoses.length / (duration.inMilliseconds / 1000.0);
      }
    }

    await _poseSource.stop();
  }

  /// Get recorded poses.
  List<FramePose> get recordedPoses => List.unmodifiable(_recordedPoses);

  /// Get estimated FPS.
  double get estimatedFps => _estimatedFps;

  /// Check if recording.
  bool get isRecording => _isRecording;

  /// Clear recorded poses.
  void clear() {
    _recordedPoses.clear();
    _frameIndex = 0;
  }

  /// Get frame count.
  int get frameCount => _recordedPoses.length;
}

