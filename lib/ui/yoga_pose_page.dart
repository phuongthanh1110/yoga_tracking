import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

import '../scene/yoga_three_scene.dart';
import '../utils/device_info.dart';
import '../practice/practice_state.dart';

/// High–level screen widget (UI layer).
/// - Single Responsibility: only builds UI and passes callbacks/flags to the scene.
class YogaPosePage extends StatelessWidget {
  const YogaPosePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F0),
      appBar: AppBar(
        title: const Text('3D Yoga Simulator'),
      ),
      body: Container(
        color: Colors.white, // Set to white to match scene background
        child: YogaThreeScene(
          overlayBuilder: (ctx) => _buildControls(ctx),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final isMobile = DeviceInfo.isMobile(context);

    return SafeArea(
      top: true,
      bottom: false,
      child: Container(
        padding: EdgeInsets.all(isMobile ? 8 : 12),
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Practice mode indicator and controls
            _PracticeModeControls(isMobile: isMobile),
            SizedBox(height: isMobile ? 8 : 12),
            // Adaptive button layout
            _buildButtonRow(context, isMobile: isMobile),
            SizedBox(height: isMobile ? 8 : 12),
            // Model Scale Slider
            _ModelScaleSlider(isMobile: isMobile),
          ],
        ),
      ),
    );
  }

  Widget _buildButtonRow(BuildContext context, {required bool isMobile}) {
    final buttonSize = isMobile ? 44.0 : 48.0; // Minimum 44px for touch targets
    final iconSize = isMobile ? 20.0 : 24.0;

    // Mobile: Wrap buttons if needed, Tablet/Desktop: Single row
    if (isMobile) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: _buildControlButtons(context,
            buttonSize: buttonSize, iconSize: iconSize),
      );
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: _buildControlButtons(context,
            buttonSize: buttonSize, iconSize: iconSize),
      );
    }
  }

  List<Widget> _buildControlButtons(
    BuildContext context, {
    required double buttonSize,
    required double iconSize,
  }) {
    return [
      _buildControlButton(
        context,
        icon: Image.asset('assets/image/demo.png',
            width: iconSize, height: iconSize),
        onPressed: () => YogaThreeSceneCommands.of(context)?.playDemo(),
        buttonSize: buttonSize,
      ),
      _buildControlButton(
        context,
        icon: Image.asset('assets/image/video.png',
            width: iconSize, height: iconSize),
        onPressed: () async {
          final result =
              await FilePicker.platform.pickFiles(type: FileType.video);
          final path = result?.files.single.path;
          if (path != null) {
            YogaThreeSceneCommands.of(context)?.startVideoPose(File(path));
          }
        },
        buttonSize: buttonSize,
      ),
      _buildControlButton(
        context,
        icon: Image.asset('assets/image/camera.png',
            width: iconSize, height: iconSize),
        onPressed: () => YogaThreeSceneCommands.of(context)?.startWebcamPose(),
        buttonSize: buttonSize,
      ),
      _buildControlButton(
        context,
        icon: Icon(Icons.flip_camera_ios, size: iconSize),
        onPressed: () =>
            YogaThreeSceneCommands.of(context)?.toggleCameraFacing(),
        buttonSize: buttonSize,
      ),
      _buildControlButton(
        context,
        icon: Image.asset('assets/image/pause.png',
            width: iconSize, height: iconSize),
        onPressed: () => YogaThreeSceneCommands.of(context)?.togglePause(),
        buttonSize: buttonSize,
      ),
      _buildControlButton(
        context,
        icon: Icon(Icons.download, size: iconSize),
        onPressed: () => YogaThreeSceneCommands.of(context)?.downloadPoseJson(),
        buttonSize: buttonSize,
      ),
      _buildControlButton(
        context,
        icon: Icon(Icons.fitness_center, size: iconSize),
        onPressed: () {
          final commands = YogaThreeSceneCommands.of(context);
          final state = commands?.getPracticeState();
          if (state == PracticeState.idle) {
            // Show dialog to choose demo or video
            _showPracticeModeDialog(context);
          } else if (state == PracticeState.ready) {
            commands?.startUserPractice();
          } else if (state == PracticeState.practicing) {
            commands?.finishPractice();
          } else {
            commands?.resetPractice();
          }
        },
        buttonSize: buttonSize,
      ),
    ];
  }

  void _showPracticeModeDialog(BuildContext context) {
    // Save reference to commands before showing dialog
    final commands = YogaThreeSceneCommands.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Practice Mode'),
        content: const Text('Choose reference: Demo animation or Video?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              commands?.startPracticeWithDemo();
            },
            child: const Text('Demo'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final result =
                  await FilePicker.platform.pickFiles(type: FileType.video);
              final path = result?.files.single.path;
              if (path != null && commands != null) {
                commands.startPracticeWithVideo(File(path));
              }
            },
            child: const Text('Video'),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(
    BuildContext context, {
    required Widget icon,
    required VoidCallback onPressed,
    required double buttonSize,
  }) {
    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: icon,
      ),
    );
  }
}

class _ModelScaleSlider extends StatefulWidget {
  final bool isMobile;
  const _ModelScaleSlider({required this.isMobile});

  @override
  State<_ModelScaleSlider> createState() => _ModelScaleSliderState();
}

class _ModelScaleSliderState extends State<_ModelScaleSlider> {
  double _scale = 0.70;

  @override
  void initState() {
    super.initState();
    // Set initial scale when widget is created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      YogaThreeSceneCommands.of(context)?.updateModelScale(0.7);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Adaptive slider width: 80% screen width on mobile, fixed 300px on tablet/desktop
    final sliderWidth =
        widget.isMobile ? DeviceInfo.screenWidth(context) * 0.8 : 300.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isMobile ? 16 : 24,
        vertical: widget.isMobile ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: const Color.fromARGB(0, 255, 255, 255),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Model Size: ${_scale.toStringAsFixed(2)}x',
            style: TextStyle(
              color: Colors.black,
              fontSize: widget.isMobile ? 14 : 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: sliderWidth,
            child: Slider(
              value: _scale,
              min: 0.1,
              max: 3.0,
              divisions: 29,
              label: '${_scale.toStringAsFixed(2)}x',
              onChanged: (value) {
                if (!mounted) return;
                setState(() {
                  _scale = value;
                });
                YogaThreeSceneCommands.of(context)?.updateModelScale(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PracticeModeControls extends StatelessWidget {
  final bool isMobile;

  const _PracticeModeControls({required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final commands = YogaThreeSceneCommands.of(context);
    final state = commands?.getPracticeState() ?? PracticeState.idle;

    if (state == PracticeState.idle) {
      return const SizedBox.shrink();
    }

    Color stateColor;
    String stateText;
    Widget? actionButton;

    switch (state) {
      case PracticeState.watching:
        stateColor = Colors.blue;
        stateText = 'Watching Model...';
        break;
      case PracticeState.ready:
        stateColor = Colors.green;
        stateText = 'Ready to Practice';
        actionButton = ElevatedButton.icon(
          onPressed: () => commands?.startUserPractice(),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Practice'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        );
        break;
      case PracticeState.practicing:
        stateColor = Colors.orange;
        stateText = 'Practicing...';
        actionButton = ElevatedButton.icon(
          onPressed: () => commands?.finishPractice(),
          icon: const Icon(Icons.stop),
          label: const Text('Finish'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
        );
        break;
      case PracticeState.analyzing:
        stateColor = Colors.purple;
        stateText = 'Analyzing...';
        actionButton = const Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator(),
        );
        break;
      case PracticeState.completed:
        stateColor = Colors.teal;
        stateText = 'Completed!';
        actionButton = ElevatedButton.icon(
          onPressed: () => commands?.resetPractice(),
          icon: const Icon(Icons.refresh),
          label: const Text('Reset'),
        );
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.all(isMobile ? 8 : 12),
      decoration: BoxDecoration(
        color: stateColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: stateColor.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.fitness_center, color: stateColor, size: 20),
              const SizedBox(width: 8),
              Text(
                stateText,
                style: TextStyle(
                  color: stateColor,
                  fontWeight: FontWeight.bold,
                  fontSize: isMobile ? 14 : 16,
                ),
              ),
            ],
          ),
          if (actionButton != null) ...[
            const SizedBox(height: 8),
            actionButton,
          ],
        ],
      ),
    );
  }
}
