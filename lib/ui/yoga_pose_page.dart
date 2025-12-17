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
        color: const Color(0xFFF0F0F0),
        child: YogaThreeScene(
          overlayBuilder: (ctx) => _buildControls(ctx),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: () {
                YogaThreeSceneCommands.of(context)?.playDemo();
              },
              child: const Text('Play 10s Demo'),
            ),
            FilledButton.tonal(
              onPressed: () {
                YogaThreeSceneCommands.of(context)?.startWebcamPose();
              },
              child: const Text('Use Camera Pose'),
            ),
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
            FilledButton.tonal(
              onPressed: () {
                YogaThreeSceneCommands.of(context)?.togglePause();
              },
              child: const Text('Pause / Resume'),
            ),
          ],
        ),
      ),
    );
  }
}
