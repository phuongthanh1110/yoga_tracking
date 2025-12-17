import 'package:flutter/material.dart';

import 'ui/yoga_pose_page.dart';

void main() {
  runApp(const YogaPoseApp());
}

class YogaPoseApp extends StatelessWidget {
  const YogaPoseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '3D Yoga Simulator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const YogaPosePage(),
    );
  }
}
