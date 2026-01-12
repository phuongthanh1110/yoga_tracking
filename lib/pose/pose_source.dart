import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'camera_pose_source.dart';

/// Simple data model for one pose frame.
/// - S: separate data model from rendering and plugins (Single Responsibility).
class PoseFrame {
  final List<dynamic> worldLandmarks; // platform plugin raw objects
  final List<dynamic> imageLandmarks;
  final int width;
  final int height;

  PoseFrame({
    required this.worldLandmarks,
    required this.imageLandmarks,
    required this.width,
    required this.height,
  });
}

/// Abstraction for any pose source (webcam, video file, etc.).
/// - O: open for extension (new sources) without changing existing code.
abstract class PoseSource {
  Stream<PoseFrame> get frames;

  /// Start live camera pose.
  Future<void> start();

  /// Process a local video file for pose extraction (e.g., user-uploaded).
  Future<void> startFromVideo(File videoFile);

  /// Switch between front/back camera if supported.
  /// Default: no-op.
  Future<void> switchCamera() async {}

  /// Video recording (Direction B): record user video then send to backend.
  /// Default: not supported.
  bool get canRecordVideo => false;
  Future<void> startVideoRecording() async {}
  Future<File?> stopVideoRecording() async => null;

  Future<void> stop();

  /// Dispose resources permanently. After this, the instance should not be reused.
  /// Default: just stop.
  Future<void> dispose() async {
    await stop();
  }

  /// Optional platform preview widget (e.g., camera texture).
  /// Return null if not available.
  Widget? get preview => null;
}

/// Temporary no-op source so the app can run before native pose is wired.
class DummyPoseSource implements PoseSource {
  final _controller = StreamController<PoseFrame>.broadcast();

  @override
  Stream<PoseFrame> get frames => _controller.stream;

  @override
  Future<void> start() async {
    // emits nothing
  }

  @override
  Future<void> startFromVideo(File videoFile) async {
    // no-op until MediaPipe integration is added
  }

  @override
  Future<void> switchCamera() async {
    // no-op
  }

  @override
  bool get canRecordVideo => false;

  @override
  Future<void> startVideoRecording() async {
    // no-op
  }

  @override
  Future<File?> stopVideoRecording() async {
    return null;
  }

  @override
  Future<void> stop() async {
    // no-op: keep stream alive so caller can start() again
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  @override
  Widget? get preview => Container(
        color: Colors.black12,
        child: const Center(
          child: Text(
            'Camera preview not implemented',
            style: TextStyle(color: Colors.black54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
}

/// Factory that selects default mobile implementation.
/// Replace with platform-specific MediaPipe implementations.
PoseSource createDefaultPoseSource() {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    return CameraPoseSource();
  }
  return DummyPoseSource();
}
