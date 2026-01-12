import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'pose_source.dart';

/// Live camera preview source.
///
/// Note: This currently provides preview + frame size only.
/// Landmarks are empty until pose detection is integrated.
class CameraPoseSource implements PoseSource {
  final _controller = StreamController<PoseFrame>.broadcast();

  CameraController? _cameraController;
  bool _isStarted = false;
  List<CameraDescription> _cameras = const [];
  // Default to front camera for recording/practice.
  CameraLensDirection _lensDirection = CameraLensDirection.front;
  bool _isRecordingVideo = false;
  Timer? _previewInfoTimer;

  @override
  Stream<PoseFrame> get frames => _controller.stream;

  @override
  Widget? get preview {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized) {
      return const Center(
        child: Text(
          'Initializing camera...',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    return CameraPreview(c);
  }

  @override
  Future<void> start() async {
    if (kIsWeb) {
      // This app already disables web renderer in three_js path.
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    if (_isStarted) return;
    _isStarted = true;

    try {
      _cameras = await availableCameras().timeout(const Duration(seconds: 10),
          onTimeout: () {
        throw Exception('availableCameras timeout');
      });
      if (_cameras.isEmpty) {
        _isStarted = false;
        return;
      }

      // Prefer back camera if available; otherwise fallback to front/first.
      // Prefer front camera (practice mode requirement); otherwise fallback to back/first.
      if (_pickCamera(CameraLensDirection.front) != null) {
        _lensDirection = CameraLensDirection.front;
      } else if (_pickCamera(CameraLensDirection.back) != null) {
        _lensDirection = CameraLensDirection.back;
      }

      await _startWithLens(_lensDirection);
    } catch (e) {
      // allow retry
      _isStarted = false;
      rethrow;
    }
  }

  Future<void> _startWithLens(CameraLensDirection direction) async {
    final camera = _pickCamera(direction) ?? _cameras.first;
    _lensDirection = camera.lensDirection;

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _cameraController = controller;

    await controller.initialize().timeout(const Duration(seconds: 10),
        onTimeout: () {
      throw Exception('Camera initialize timeout');
    });

    // IMPORTANT (iOS stability):
    // Do NOT use startImageStream here. It can crash on iOS (camera_avfoundation)
    // when start/stop recording or switching cameras.
    // For our needs (Hướng B), preview is enough; we emit preview size via timer.
    _previewInfoTimer?.cancel();
    _previewInfoTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final c = _cameraController;
      if (c == null || !c.value.isInitialized) return;
      final size = c.value.previewSize;
      if (size == null) return;
      if (_controller.isClosed) return;
      _controller.add(
        PoseFrame(
          worldLandmarks: const [],
          imageLandmarks: const [],
          width: size.width.toInt(),
          height: size.height.toInt(),
        ),
      );
    });
  }

  CameraDescription? _pickCamera(CameraLensDirection direction) {
    for (final c in _cameras) {
      if (c.lensDirection == direction) return c;
    }
    return null;
  }

  @override
  Future<void> switchCamera() async {
    if (!_isStarted) {
      await start();
    }
    if (_isRecordingVideo) return;
    if (_cameras.isEmpty) return;

    final next = _lensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    // If the other lens doesn't exist, do nothing.
    if (_pickCamera(next) == null) return;

    // Restart camera controller with the new lens.
    final c = _cameraController;
    _cameraController = null;
    _previewInfoTimer?.cancel();
    try {
      await c?.dispose();
    } catch (_) {}

    await _startWithLens(next);
  }

  @override
  bool get canRecordVideo => true;

  @override
  Future<void> startVideoRecording() async {
    if (!_isStarted) {
      await start();
    }
    final c = _cameraController;
    if (c == null || !c.value.isInitialized) {
      throw Exception('Camera not initialized');
    }
    if (_isRecordingVideo) return;

    // iOS may require prepareForVideoRecording().
    try {
      await c.prepareForVideoRecording();
    } catch (_) {
      // ignore if not supported
    }

    await c.startVideoRecording().timeout(const Duration(seconds: 10),
        onTimeout: () {
      throw Exception('startVideoRecording timeout');
    });
    _isRecordingVideo = true;
  }

  @override
  Future<File?> stopVideoRecording() async {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized) return null;
    if (!_isRecordingVideo) return null;

    final xFile = await c.stopVideoRecording().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw Exception('stopVideoRecording timeout');
      },
    );
    _isRecordingVideo = false;
    return File(xFile.path);
  }

  @override
  Future<void> startFromVideo(File videoFile) async {
    // Not used for live camera source.
  }

  @override
  Future<void> stop() async {
    _isStarted = false;
    _isRecordingVideo = false;

    final c = _cameraController;
    _cameraController = null;
    _previewInfoTimer?.cancel();
    _previewInfoTimer = null;

    try {
      await c?.dispose();
    } catch (_) {
      // ignore
    }
    // Keep stream controller open for future start() calls.
  }

  @override
  Future<void> dispose() async {
    await stop();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
