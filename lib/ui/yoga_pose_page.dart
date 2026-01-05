import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

import '../scene/yoga_three_scene.dart';
import '../utils/device_info.dart';

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
    ];
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
