import '../services/pose_api_client.dart';

/// Records reference poses from model animation/video.
class ReferencePoseRecorder {
  final List<FramePose> _recordedPoses = [];
  double _fps = 30.0;
  bool _isRecording = false;

  /// Start recording reference poses.
  void startRecording({double fps = 30.0}) {
    _recordedPoses.clear();
    _fps = fps;
    _isRecording = true;
  }

  /// Stop recording.
  void stopRecording() {
    _isRecording = false;
  }

  /// Record a pose frame.
  void recordFrame(FramePose frame) {
    if (!_isRecording) return;
    _recordedPoses.add(frame);
  }

  /// Get recorded poses.
  List<FramePose> get recordedPoses => List.unmodifiable(_recordedPoses);

  /// Get FPS.
  double get fps => _fps;

  /// Check if recording.
  bool get isRecording => _isRecording;

  /// Clear recorded poses.
  void clear() {
    _recordedPoses.clear();
  }

  /// Get frame count.
  int get frameCount => _recordedPoses.length;
}

