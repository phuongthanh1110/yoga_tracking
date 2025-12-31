import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

import '../scene/yoga_three_scene.dart';

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
    return SafeArea(
      top: true,
      bottom: false,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          // color: Colors.white.withValues(alpha: 0.9),
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
            // Row 1 - Action buttons (2 columns)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left column
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        onPressed: () {
                          YogaThreeSceneCommands.of(context)?.playDemo();
                        },
                        child: const Icon(Icons.play_arrow, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: () {
                          YogaThreeSceneCommands.of(context)?.startWebcamPose();
                        },
                        child: const Text('Use Camera Pose'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Right column
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.tonal(
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.video,
                          );
                          final path = result?.files.single.path;
                          if (path != null) {
                            YogaThreeSceneCommands.of(context)
                                ?.startVideoPose(File(path));
                          }
                        },
                        child: const Text('Upload Video'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: () {
                          YogaThreeSceneCommands.of(context)?.togglePause();
                        },
                        child: const Text('Pause / Resume'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Row 2 - Model Scale Slider
            _ModelScaleSlider(),
          ],
        ),
      ),
    );
  }
}

class _ModelScaleSlider extends StatefulWidget {
  const _ModelScaleSlider();

  @override
  State<_ModelScaleSlider> createState() => _ModelScaleSliderState();
}

class _ModelScaleSliderState extends State<_ModelScaleSlider> {
  double _scale = 0.60;

  @override
  void initState() {
    super.initState();
    // Set initial scale when widget is created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      YogaThreeSceneCommands.of(context)?.updateModelScale(0.6);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color.fromARGB(0, 255, 255, 255),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // const Icon(Icons.aspect_ratio, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(
                'Model Size: ${_scale.toStringAsFixed(2)}x',
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 200,
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
