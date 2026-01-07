import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/comparison_service.dart';
import '../services/pose_comparison_models.dart';
import 'comparison_result_page.dart';

/// Page for recording user's yoga pose video
///
/// Features:
/// - Camera preview with countdown timer
/// - Recording indicator
/// - Switch between front/back camera
/// - Automatic comparison after recording
class VideoRecorderPage extends StatefulWidget {
  const VideoRecorderPage({
    super.key,
    required this.trainer,
    required this.baseUrl,
  });

  final TrainerListItem trainer;
  final String baseUrl;

  @override
  State<VideoRecorderPage> createState() => _VideoRecorderPageState();
}

class _VideoRecorderPageState extends State<VideoRecorderPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isProcessing = false;
  String? _error;
  int _selectedCameraIndex = 0;

  // Recording state
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  int _countdownSeconds = 0;
  Timer? _countdownTimer;

  // Countdown before recording starts
  static const int countdownDuration = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _countdownTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _error = 'No cameras available';
        });
        return;
      }

      // Prefer front camera for selfie recording
      _selectedCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (_selectedCameraIndex < 0) _selectedCameraIndex = 0;

      await _setupCamera(_cameras[_selectedCameraIndex]);
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize camera: $e';
      });
    }
  }

  Future<void> _setupCamera(CameraDescription camera) async {
    _controller?.dispose();

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false, // No audio needed for pose analysis
    );

    _controller = controller;

    try {
      await controller.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _error = null;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to setup camera: $e';
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;

    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _setupCamera(_cameras[_selectedCameraIndex]);
  }

  void _startCountdown() {
    setState(() {
      _countdownSeconds = countdownDuration;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdownSeconds--;
      });

      if (_countdownSeconds <= 0) {
        timer.cancel();
        _startRecording();
      }
    });
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      await controller.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingSeconds++;
        });
      });
    } catch (e) {
      _showError('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isRecordingVideo) return;

    _recordingTimer?.cancel();

    try {
      setState(() {
        _isProcessing = true;
      });

      final file = await controller.stopVideoRecording();
      setState(() {
        _isRecording = false;
      });

      // Process the recorded video
      await _processRecording(File(file.path));
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _isRecording = false;
      });
      _showError('Failed to stop recording: $e');
    }
  }

  Future<void> _processRecording(File videoFile) async {
    try {
      // Compare video with trainer
      final service = ComparisonService(baseUrl: widget.baseUrl);
      final result = await service.compareVideoToTrainer(
        trainerId: widget.trainer.id,
        userVideoFile: videoFile,
        stride: 2, // Use stride 2 for faster processing
      );

      if (!mounted) return;

      // Navigate to results page
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ComparisonResultPage(
            result: result,
            trainerName: widget.trainer.name,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      _showError('Comparison failed: $e');
    } finally {
      // Clean up temp file
      try {
        if (await videoFile.exists()) {
          await videoFile.delete();
        }
      } catch (_) {}
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          _buildCameraPreview(),

          // Overlay UI
          SafeArea(
            child: Column(
              children: [
                // Top bar
                _buildTopBar(),

                const Spacer(),

                // Countdown overlay
                if (_countdownSeconds > 0) _buildCountdownOverlay(),

                // Recording timer
                if (_isRecording) _buildRecordingIndicator(),

                // Processing overlay
                if (_isProcessing) _buildProcessingOverlay(),

                const Spacer(),

                // Bottom controls
                _buildBottomControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initializeCamera,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return CameraPreviewWidget(controller: controller);
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed:
                _isRecording || _isProcessing ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),

          const Spacer(),

          // Trainer name
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              widget.trainer.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const Spacer(),

          // Switch camera button
          IconButton(
            onPressed:
                _isRecording || _cameras.length < 2 ? null : _switchCamera,
            icon: Icon(
              Icons.flip_camera_ios,
              color: _cameras.length < 2 ? Colors.grey : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownOverlay() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '$_countdownSeconds',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 72,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'REC ${_formatDuration(_recordingSeconds)}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          CircularProgressIndicator(color: Colors.teal),
          SizedBox(height: 16),
          Text(
            'Analyzing your pose...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'This may take a moment',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Instructions
          if (!_isRecording && !_isProcessing && _countdownSeconds == 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Position yourself so your full body is visible',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // Record button
          GestureDetector(
            onTap: _isProcessing || _countdownSeconds > 0
                ? null
                : (_isRecording ? _stopRecording : _startCountdown),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: Center(
                child: Container(
                  width: _isRecording ? 32 : 64,
                  height: _isRecording ? 32 : 64,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius:
                        BorderRadius.circular(_isRecording ? 4 : 32),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Help text
          Text(
            _isRecording
                ? 'Tap to stop recording'
                : 'Tap to start recording',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Camera preview widget with proper aspect ratio handling
class CameraPreviewWidget extends StatelessWidget {
  const CameraPreviewWidget({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scale = 1 / (controller.value.aspectRatio * size.aspectRatio);

    return ClipRect(
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: Center(
          child: controller.buildPreview(),
        ),
      ),
    );
  }
}

