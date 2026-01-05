import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Represents a single bone's rotation data for display and control.
class BoneRotationData {
  final String name;
  final String displayName;
  double x;
  double y;
  double z;

  BoneRotationData({
    required this.name,
    required this.displayName,
    this.x = 0,
    this.y = 0,
    this.z = 0,
  });

  /// Convert radians to degrees for display.
  double get xDeg => x * 180 / math.pi;
  double get yDeg => y * 180 / math.pi;
  double get zDeg => z * 180 / math.pi;

  /// Update from a Three.js bone object.
  void updateFromBone(dynamic bone) {
    if (bone == null) return;
    x = (bone.rotation.x as num).toDouble();
    y = (bone.rotation.y as num).toDouble();
    z = (bone.rotation.z as num).toDouble();
  }
}

/// Controller that manages bone data and provides access for UI.
class BoneDataController extends ChangeNotifier {
  final Map<String, dynamic> _bones = {};
  final Map<String, BoneRotationData> _boneData = {};
  bool _isPaused = false;

  bool get isPaused => _isPaused;

  /// Initialize with bone references from the model.
  void setBones(Map<String, dynamic> bones) {
    _bones.clear();
    _bones.addAll(bones);
    _initBoneData();
    notifyListeners();
  }

  void _initBoneData() {
    _boneData.clear();
    for (final entry in _boneDefinitions.entries) {
      if (_bones.containsKey(entry.key)) {
        _boneData[entry.key] = BoneRotationData(
          name: entry.key,
          displayName: entry.value,
        );
      }
    }
  }

  /// Update all bone data from current bone rotations.
  void updateFromBones() {
    for (final entry in _boneData.entries) {
      final bone = _bones[entry.key];
      entry.value.updateFromBone(bone);
    }
    notifyListeners();
  }

  /// Get rotation data for a specific bone.
  BoneRotationData? getBoneData(String name) => _boneData[name];

  /// Get all bone data grouped by category.
  Map<String, List<BoneRotationData>> get groupedBoneData {
    final result = <String, List<BoneRotationData>>{};
    for (final entry in _boneData.entries) {
      final category = _boneCategories[entry.key] ?? 'Other';
      result.putIfAbsent(category, () => []).add(entry.value);
    }
    return result;
  }

  /// Set bone rotation value.
  void setBoneRotation(String boneName, String axis, double value) {
    final bone = _bones[boneName];
    if (bone == null) return;
    switch (axis) {
      case 'x':
        bone.rotation.x = value;
        break;
      case 'y':
        bone.rotation.y = value;
        break;
      case 'z':
        bone.rotation.z = value;
        break;
    }
    _boneData[boneName]?.updateFromBone(bone);
    notifyListeners();
  }

  /// Toggle pause state.
  void togglePause() {
    _isPaused = !_isPaused;
    notifyListeners();
  }

  void setPaused(bool paused) {
    _isPaused = paused;
    notifyListeners();
  }

  /// Get list of all available bones.
  List<String> get availableBones => _bones.keys.toList();

  /// Check if bones are loaded.
  bool get hasBones => _bones.isNotEmpty;
}

/// Display names for bones.
const Map<String, String> _boneDefinitions = {
  // Head & Neck
  'Head': 'Head',
  'Neck': 'Neck',
  // Spine
  'Spine': 'Lower Spine',
  'Spine1': 'Mid Spine',
  'Spine2': 'Upper Spine',
  // Hips
  'Hips': 'Hips',
  // Left Arm
  'LeftArm': 'Left Shoulder',
  'LeftForeArm': 'Left Elbow',
  'LeftHand': 'Left Wrist',
  // Left Fingers
  'LeftHandThumb1': 'L Thumb 1',
  'LeftHandThumb2': 'L Thumb 2',
  'LeftHandThumb3': 'L Thumb 3',
  'LeftHandIndex1': 'L Index 1',
  'LeftHandIndex2': 'L Index 2',
  'LeftHandIndex3': 'L Index 3',
  'LeftHandMiddle1': 'L Middle 1',
  'LeftHandMiddle2': 'L Middle 2',
  'LeftHandMiddle3': 'L Middle 3',
  'LeftHandRing1': 'L Ring 1',
  'LeftHandRing2': 'L Ring 2',
  'LeftHandRing3': 'L Ring 3',
  'LeftHandPinky1': 'L Pinky 1',
  'LeftHandPinky2': 'L Pinky 2',
  'LeftHandPinky3': 'L Pinky 3',
  // Right Arm
  'RightArm': 'Right Shoulder',
  'RightForeArm': 'Right Elbow',
  'RightHand': 'Right Wrist',
  // Right Fingers
  'RightHandThumb1': 'R Thumb 1',
  'RightHandThumb2': 'R Thumb 2',
  'RightHandThumb3': 'R Thumb 3',
  'RightHandIndex1': 'R Index 1',
  'RightHandIndex2': 'R Index 2',
  'RightHandIndex3': 'R Index 3',
  'RightHandMiddle1': 'R Middle 1',
  'RightHandMiddle2': 'R Middle 2',
  'RightHandMiddle3': 'R Middle 3',
  'RightHandRing1': 'R Ring 1',
  'RightHandRing2': 'R Ring 2',
  'RightHandRing3': 'R Ring 3',
  'RightHandPinky1': 'R Pinky 1',
  'RightHandPinky2': 'R Pinky 2',
  'RightHandPinky3': 'R Pinky 3',
  // Left Leg
  'LeftUpLeg': 'Left Hip',
  'LeftLeg': 'Left Knee',
  'LeftFoot': 'Left Ankle',
  'LeftToeBase': 'Left Toe',
  // Right Leg
  'RightUpLeg': 'Right Hip',
  'RightLeg': 'Right Knee',
  'RightFoot': 'Right Ankle',
  'RightToeBase': 'Right Toe',
};

/// Category mapping for grouping bones in UI.
const Map<String, String> _boneCategories = {
  'Head': 'Head & Neck',
  'Neck': 'Head & Neck',
  'Spine': 'Spine',
  'Spine1': 'Spine',
  'Spine2': 'Spine',
  'Hips': 'Hips',
  'LeftArm': 'Left Arm',
  'LeftForeArm': 'Left Arm',
  'LeftHand': 'Left Hand',
  'LeftHandThumb1': 'Left Hand',
  'LeftHandThumb2': 'Left Hand',
  'LeftHandThumb3': 'Left Hand',
  'LeftHandIndex1': 'Left Hand',
  'LeftHandIndex2': 'Left Hand',
  'LeftHandIndex3': 'Left Hand',
  'LeftHandMiddle1': 'Left Hand',
  'LeftHandMiddle2': 'Left Hand',
  'LeftHandMiddle3': 'Left Hand',
  'LeftHandRing1': 'Left Hand',
  'LeftHandRing2': 'Left Hand',
  'LeftHandRing3': 'Left Hand',
  'LeftHandPinky1': 'Left Hand',
  'LeftHandPinky2': 'Left Hand',
  'LeftHandPinky3': 'Left Hand',
  'RightArm': 'Right Arm',
  'RightForeArm': 'Right Arm',
  'RightHand': 'Right Hand',
  'RightHandThumb1': 'Right Hand',
  'RightHandThumb2': 'Right Hand',
  'RightHandThumb3': 'Right Hand',
  'RightHandIndex1': 'Right Hand',
  'RightHandIndex2': 'Right Hand',
  'RightHandIndex3': 'Right Hand',
  'RightHandMiddle1': 'Right Hand',
  'RightHandMiddle2': 'Right Hand',
  'RightHandMiddle3': 'Right Hand',
  'RightHandRing1': 'Right Hand',
  'RightHandRing2': 'Right Hand',
  'RightHandRing3': 'Right Hand',
  'RightHandPinky1': 'Right Hand',
  'RightHandPinky2': 'Right Hand',
  'RightHandPinky3': 'Right Hand',
  'LeftUpLeg': 'Left Leg',
  'LeftLeg': 'Left Leg',
  'LeftFoot': 'Left Foot',
  'LeftToeBase': 'Left Foot',
  'RightUpLeg': 'Right Leg',
  'RightLeg': 'Right Leg',
  'RightFoot': 'Right Foot',
  'RightToeBase': 'Right Foot',
};

/// Widget that displays live bone metrics in a compact overlay.
class BoneMetricsPanel extends StatelessWidget {
  final BoneDataController controller;
  final List<String> visibleBones;

  const BoneMetricsPanel({
    super.key,
    required this.controller,
    this.visibleBones = const ['Hips', 'LeftHand', 'RightHand', 'Head'],
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.hasBones) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.analytics, color: Colors.cyan, size: 16),
                  const SizedBox(width: 4),
                  const Text(
                    'Bone Metrics',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildPauseIndicator(),
                ],
              ),
              const SizedBox(height: 4),
              ...visibleBones.map((name) => _buildBoneMetric(name)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPauseIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: controller.isPaused ? Colors.orange : Colors.green,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        controller.isPaused ? 'PAUSED' : 'LIVE',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBoneMetric(String boneName) {
    final data = controller.getBoneData(boneName);
    if (data == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              data.displayName,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ),
          _buildAxisValue('X', data.xDeg, Colors.red),
          _buildAxisValue('Y', data.yDeg, Colors.green),
          _buildAxisValue('Z', data.zDeg, Colors.blue),
        ],
      ),
    );
  }

  Widget _buildAxisValue(String axis, double value, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        '$axis:${value.toStringAsFixed(1)}°',
        style: TextStyle(color: color, fontSize: 9, fontFamily: 'monospace'),
      ),
    );
  }
}

/// Full bone controller panel with sliders for all bones.
class BoneControllerPanel extends StatefulWidget {
  final BoneDataController controller;
  final VoidCallback? onClose;

  const BoneControllerPanel({
    super.key,
    required this.controller,
    this.onClose,
  });

  @override
  State<BoneControllerPanel> createState() => _BoneControllerPanelState();
}

class _BoneControllerPanelState extends State<BoneControllerPanel> {
  final Set<String> _expandedCategories = {'Hips', 'Left Hand', 'Right Hand'};
  bool _showMetricsOnly = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return Container(
          width: 320,
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 10,
                offset: const Offset(-2, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHeader(),
              _buildPlaybackControls(),
              if (_showMetricsOnly) _buildMetricsView() else _buildSliderView(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune, color: Colors.cyan),
          const SizedBox(width: 8),
          const Text(
            'Bone Controller',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              _showMetricsOnly ? Icons.linear_scale : Icons.analytics,
              color: Colors.white70,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _showMetricsOnly = !_showMetricsOnly),
            tooltip: _showMetricsOnly ? 'Show Sliders' : 'Show Metrics Only',
          ),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  Widget _buildPlaybackControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.grey[800],
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    widget.controller.isPaused ? Colors.green : Colors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: widget.controller.togglePause,
              icon: Icon(
                widget.controller.isPaused ? Icons.play_arrow : Icons.pause,
              ),
              label: Text(widget.controller.isPaused ? 'Resume' : 'Pause'),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: widget.controller.isPaused
                  ? Colors.orange.withValues(alpha: 0.2)
                  : Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.controller.isPaused ? 'PAUSED' : 'LIVE',
              style: TextStyle(
                color:
                    widget.controller.isPaused ? Colors.orange : Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsView() {
    final grouped = widget.controller.groupedBoneData;
    return Expanded(
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: grouped.entries.map((entry) {
          return _buildMetricsCategory(entry.key, entry.value);
        }).toList(),
      ),
    );
  }

  Widget _buildMetricsCategory(String category, List<BoneRotationData> bones) {
    return Card(
      color: Colors.grey[850],
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              category,
              style: const TextStyle(
                color: Colors.cyan,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          ...bones.map((bone) => _buildMetricRow(bone)),
        ],
      ),
    );
  }

  Widget _buildMetricRow(BoneRotationData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              data.displayName,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAxisChip('X', data.xDeg, Colors.red),
                _buildAxisChip('Y', data.yDeg, Colors.green),
                _buildAxisChip('Z', data.zDeg, Colors.blue),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAxisChip(String axis, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$axis: ${value.toStringAsFixed(1)}°',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildSliderView() {
    final grouped = widget.controller.groupedBoneData;
    return Expanded(
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: grouped.entries.map((entry) {
          return _buildSliderCategory(entry.key, entry.value);
        }).toList(),
      ),
    );
  }

  Widget _buildSliderCategory(String category, List<BoneRotationData> bones) {
    final isExpanded = _expandedCategories.contains(category);
    return Card(
      color: Colors.grey[850],
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCategories.remove(category);
                } else {
                  _expandedCategories.add(category);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    category,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${bones.length} bones',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: bones.map((bone) => _buildBoneSliders(bone)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBoneSliders(BoneRotationData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.displayName,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          _buildAxisSlider(data, 'x', 'Pitch (X)', Colors.red),
          _buildAxisSlider(data, 'y', 'Yaw (Y)', Colors.green),
          _buildAxisSlider(data, 'z', 'Roll (Z)', Colors.blue),
          const Divider(color: Colors.white12, height: 16),
        ],
      ),
    );
  }

  Widget _buildAxisSlider(
    BoneRotationData data,
    String axis,
    String label,
    Color color,
  ) {
    final value = switch (axis) {
      'x' => data.x,
      'y' => data.y,
      'z' => data.z,
      _ => 0.0,
    };
    final valueDeg = value * 180 / math.pi;

    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(color: color, fontSize: 10),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.2),
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.1),
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(-math.pi, math.pi),
              min: -math.pi,
              max: math.pi,
              onChanged: (newValue) {
                widget.controller.setBoneRotation(data.name, axis, newValue);
              },
            ),
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            '${valueDeg.toStringAsFixed(0)}°',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
