import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import '../retarget/mixamo_mapping.dart' as mapping;
import '../retarget/one_euro_filter.dart';
import '../services/pose_api_client.dart';
import '../retarget/mixamo_retargeter.dart';
import '../pose/pose_source.dart';
import 'package:three_js/three_js.dart' as three;
import 'package:three_js_advanced_loaders/three_js_advanced_loaders.dart';

/// Inherited widget to expose scene commands to UI layer.
/// Currently commands are stubs so the app can run without 3D engine wiring.
class YogaThreeSceneCommands extends InheritedWidget {
  final VoidCallback playDemo;
  final VoidCallback startWebcamPose;
  final VoidCallback togglePause;
  final void Function(File file) startVideoPose;
  final void Function(double) updateModelScale;
  final void Function(double) updatePlaybackSpeed;
  final VoidCallback downloadPoseJson;

  const YogaThreeSceneCommands({
    super.key,
    required super.child,
    required this.playDemo,
    required this.startWebcamPose,
    required this.togglePause,
    required this.startVideoPose,
    required this.updateModelScale,
    required this.updatePlaybackSpeed,
    required this.downloadPoseJson,
  });

  static YogaThreeSceneCommands? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<YogaThreeSceneCommands>();
  }

  @override
  bool updateShouldNotify(covariant YogaThreeSceneCommands oldWidget) => false;
}

/// Placeholder scene widget.
/// - Single Responsibility: show an area where 3D scene will live later.
class YogaThreeScene extends StatefulWidget {
  final Widget Function(BuildContext)? overlayBuilder;

  const YogaThreeScene({super.key, this.overlayBuilder});

  @override
  State<YogaThreeScene> createState() => _YogaThreeSceneState();
}

class _YogaThreeSceneState extends State<YogaThreeScene> {
  bool _isLoading = true;
  bool _isLoaded = false;
  String? _error;
  String _selectedModel = 'Xbot';

  double? _width;
  double? _height;

  three.ThreeJS? _threeJs;
  three.AnimationMixer? _mixer;
  three.Object3D? _model;
  three.AnimationClip? _demoClip;
  bool _loggedBones = false;
  bool _printedMixamo = false;
  MixamoRetargeter? _retargeter;
  final Map<String, OneEuroFilterVector3> _poseFilters = {};
  final mapping.PalmOrientationSmoother _palmSmoother =
      mapping.PalmOrientationSmoother();
  Timer? _poseTimer;
  List<FramePose> _poseFrames = const [];
  int _poseFrameIndex = 0;
  bool _isPosePlaying = false;
  PoseExtractionResult?
      _lastPoseResult; // Store last pose extraction result for download
  final PoseSource _livePoseSource = createDefaultPoseSource();
  StreamSubscription<PoseFrame>? _livePoseSub;
  Widget? _livePreview;
  final PoseApiClient _poseApi =
      PoseApiClient(baseUrl: poseApiBaseUrl); // adjust base URL as needed

  // SSE Progress tracking - Use ValueNotifier for reliable UI updates
  final ValueNotifier<double?> _processingProgressNotifier =
      ValueNotifier<double?>(null);

  // Model scale control
  double _modelScale = 0.7;

  // Playback speed multiplier (1.0 = normal, 2.0 = 2x speed, 0.5 = half speed)
  double _playbackSpeedMultiplier = 1.0;

  // Simple spherical-orbit camera controls (pan to rotate, pinch to zoom).
  double _radius = 4.0;
  double _theta = 0.0; // yaw: 0 = front view (chính diện)
  double _phi = 2 *
      math.pi /
      3; // pitch: 120° = looking up from below (hướng từ dưới lên)
  double _startRadius = 4.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mq = MediaQuery.of(context);
      _width = mq.size.width;
      _height = mq.size.height;
      _initThree();
    });
  }

  @override
  void dispose() {
    _poseTimer?.cancel();
    _livePoseSub?.cancel();
    _livePoseSource.stop();
    _threeJs?.dispose();
    _processingProgressNotifier.dispose();
    super.dispose();
  }

  void _initThree() {
    if (kIsWeb) {
      setState(() {
        _isLoading = false;
        _error =
            'Web renderer not configured for three_js; run on Android/iOS or add flutter_angle web canvas setup.';
      });
      return;
    }
    setState(() => _isLoading = true);
    _threeJs = three.ThreeJS(
      onSetupComplete: () async {
        setState(() {
          _isLoading = false;
        });
      },
      setup: () {
        final viewer = _threeJs;
        if (viewer == null) {
          return;
        }
        // Set white background - use Color constructor with r, g, b values (0-1 range)
        final whiteColor = three.Color(1.0, 1.0, 1.0);
        viewer.scene = three.Scene()..background = whiteColor;

        // Also set renderer clear color to white if available
        try {
          viewer.renderer?.setClearColor(whiteColor, 1.0);
        } catch (e) {
          // setClearColor might not be available, ignore
        }

        viewer.camera = three.PerspectiveCamera(
          45,
          (_width ?? 1) / (_height ?? 1),
          1,
          100,
        );
        _applyCameraOrbit();

        final hemi = three.HemisphereLight(0x1F2933, 0xffffff)
          ..position.setValues(0, 20, 0);
        viewer.scene.add(hemi);

        final dir = three.DirectionalLight(0xffffff)
          ..position.setValues(-3, 10, -10)
          ..castShadow = true;
        viewer.scene.add(dir);

        // White ground that receives shadows
        final groundMat = three.MeshPhongMaterial({
          three.MaterialProperty.color: 0xffffff,
          three.MaterialProperty.depthWrite: false,
        });
        final ground = three.Mesh(three.PlaneGeometry(200, 200), groundMat)
          ..rotation.x = -math.pi / 2
          ..position.y = 0;
        ground.receiveShadow = true;
        viewer.scene.add(ground);

        viewer.renderer?.shadowMap.enabled = true;

        // Render loop: update controls, mixer, then render.
        viewer.addAnimationEvent((dt) {
          // three.AnimationMixer expects seconds; incoming dt appears ms on some platforms.
          final deltaSec = dt > 5 ? dt / 1000.0 : dt;
          _mixer?.update(deltaSec);
          viewer.render();
        });

        _loadModelAsset(_selectedModel);
      },
    );
  }

  Future<void> _loadModelAsset(String key) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final asset = _modelAssets[key] ?? _modelAssets.values.first;
    debugPrint('[ModelLoad] Loading asset: $asset');
    _disposeModel();
    try {
      final loader = GLTFLoader();
      final result = await loader.fromAsset(asset);
      if (result != null) {
        final viewer = _threeJs;
        final model = result.scene;
        _model = model;
        viewer?.scene.add(model);
        model.traverse((obj) {
          if (obj is three.Mesh) {
            obj.castShadow = true;
            obj.receiveShadow = true;
          }
        });
        _logModelDiagnostics(result);
        _buildRetargeterFromModel(model);
        _applyModelScale();
        // Reset camera to front view when model loads
        _theta = 0.0; // Front view (chính diện)
        _phi = 1.75 * math.pi / 4; // Looking up from below (hướng từ dưới lên)
        _applyCameraOrbit();
        final animations = result.animations ?? <three.AnimationClip>[];
        if (animations.isNotEmpty) {
          _mixer = three.AnimationMixer(model);
          _mixer!.clipAction(animations.first)?.play();
        }
      }
      setState(() {
        _isLoaded = true;
        _isLoading = false;
      });
      debugPrint('[ModelLoad] GLB loaded and added to scene');
    } catch (e) {
      debugPrint('[ModelLoad] Error: $e');
      setState(() {
        _error = 'Model load failed: $e';
        _isLoading = false;
      });
    }
  }

  void _disposeModel() {
    _mixer?.stopAllAction();
    _mixer = null;
    if (_model != null) {
      try {
        _threeJs?.scene.remove(_model!);
      } catch (_) {}
    }
    _model = null;
    _retargeter = null;
  }

  void _applyModelScale() {
    final model = _model;
    if (model == null) return;
    model.scale.setValues(_modelScale, _modelScale, _modelScale);
    _threeJs?.render();
  }

  void updateModelScale(double scale) {
    setState(() {
      _modelScale = scale.clamp(0.1, 3.0);
    });
    _applyModelScale();
  }

  void updatePlaybackSpeed(double multiplier) {
    setState(() {
      _playbackSpeedMultiplier = multiplier.clamp(0.1, 4.0);
    });
    // Restart playback with new speed if currently playing
    if (_isPosePlaying && _poseFrames.isNotEmpty && _lastPoseResult != null) {
      _cancelPosePlayback();
      _poseFrameIndex = 0;
      final fps = _lastPoseResult!.fps > 0 ? _lastPoseResult!.fps : 30.0;
      final effectiveFps = fps * _playbackSpeedMultiplier;
      final stepMs = math.max(8, (1000 / effectiveFps).round());
      _isPosePlaying = true;
      _poseTimer = Timer.periodic(Duration(milliseconds: stepMs), (timer) {
        if (!_isPosePlaying) {
          timer.cancel();
          return;
        }
        if (_poseFrameIndex >= _poseFrames.length) {
          debugPrint('[PosePlayback] Completed video playback.');
          timer.cancel();
          _isPosePlaying = false;
          return;
        }
        final frame = _poseFrames[_poseFrameIndex];
        _poseFrameIndex++;
        _applyPoseFrame(frame, _lastPoseResult!);
      });
    }
  }

  Future<void> downloadPoseJson() async {
    if (_lastPoseResult == null) {
      debugPrint('[Download] No pose data to download');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pose data available to download')),
      );
      return;
    }

    try {
      // Convert PoseExtractionResult to JSON Map
      final jsonMap = _lastPoseResult!.toJson();
      // final jsonString = const JsonEncoder.withIndent('  ').convert(jsonMap);
      // Option 6B: Compact JSON (no indent) to reduce file size
      final jsonString = const JsonEncoder().convert(jsonMap);

      // Get temporary directory
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${directory.path}/pose_export_$timestamp.json');

      // Write JSON to file
      await file.writeAsString(jsonString);

      // Share/download the file
      final xFile = XFile(file.path);
      await Share.shareXFiles([xFile], text: 'Pose extraction result');

      debugPrint('[Download] JSON file saved: ${file.path}');
    } catch (e) {
      debugPrint('[Download] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return YogaThreeSceneCommands(
      playDemo: _playDemoYogaAnimation,
      startWebcamPose: () {
        _startLivePose();
      },
      togglePause: () {
        debugPrint('Toggle pause (stub)');
      },
      startVideoPose: (file) {
        _startVideoPose(file);
      },
      updateModelScale: updateModelScale,
      updatePlaybackSpeed: updatePlaybackSpeed,
      downloadPoseJson: downloadPoseJson,
      child: ValueListenableBuilder<double?>(
        valueListenable: _processingProgressNotifier,
        builder: (context, progress, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              if (_threeJs != null)
                _threeJs!.build()
              else
                const SizedBox.shrink(),
              // Gesture layer to capture drag/pinch atop the texture.
              if (_threeJs != null)
                Positioned.fill(
                  child: _withGestures(Container(color: Colors.transparent)),
                ),
              Offstage(
                offstage: !_isLoaded,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      'Loading...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(),
                ),
              if (_error != null && !_isLoading)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              if (_livePreview != null)
                Positioned(
                  left: 12,
                  bottom: 12 + (widget.overlayBuilder != null ? 90 : 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 160,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: _livePreview,
                    ),
                  ),
                ),
              Positioned(
                right: 12,
                bottom: 12,
                child: Card(
                  color: Colors.black54,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _modelAssets.keys.map((key) {
                        final isSelected = _selectedModel == key;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(key),
                            selected: isSelected,
                            onSelected: (val) {
                              if (val && key != _selectedModel) {
                                setState(() => _selectedModel = key);
                                _loadModelAsset(key);
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              // Progress indicator - Must be LAST in Stack to be on top
              if (progress != null)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.5),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Processing...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.overlayBuilder != null)
                Align(
                  alignment: Alignment.topCenter,
                  child: Builder(
                    builder: (innerContext) =>
                        widget.overlayBuilder!(innerContext),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _applyCameraOrbit() {
    final viewer = _threeJs;
    if (viewer == null) {
      return;
    }
    final cam = viewer.camera;
    final x = _radius * math.sin(_phi) * math.sin(_theta);
    final y = _radius * math.cos(_phi);
    final z = _radius * math.sin(_phi) * math.cos(_theta);
    cam.position.setValues(x, y, z);
    cam.lookAt(three.Vector3(0, 1, 0));
    viewer.render();
  }

  Widget _withGestures(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (details) {
        _startRadius = _radius;
      },
      onScaleUpdate: (details) {
        const double sensitivity = 0.005;
        if (details.pointerCount == 1) {
          final dx = details.focalPointDelta.dx;
          final dy = details.focalPointDelta.dy;
          // Drag left moves model left (camera right), subtract to follow finger.
          _theta -= dx * sensitivity;
          _phi -= dy * sensitivity;
          _phi = _phi.clamp(0.1, math.pi - 0.1);
        } else {
          _radius = (_startRadius / details.scale).clamp(1.5, 12.0);
        }
        _applyCameraOrbit();
      },
      child: child,
    );
  }

  void _playDemoYogaAnimation() {
    final model = _model;
    final viewer = _threeJs;
    if (model == null || viewer == null) {
      debugPrint('[Demo] Model not ready yet');
      return;
    }
    _mixer ??= three.AnimationMixer(model);

    // Stop any current actions before playing demo.
    _mixer!.stopAllAction();

    _demoClip ??= _buildYogaDemoClip();
    final action = _mixer!.clipAction(_demoClip!)
      ?..reset()
      ..play();
    action?.loop = three.LoopRepeat;
    action?.timeScale = 1.0;

    debugPrint(
        '[Demo] Playing yoga demo clip; mixer time=${_mixer!.time.toStringAsFixed(3)}');
  }

  Future<void> _startVideoPose(File videoFile) async {
    _stopLivePose();
    if (_model == null) {
      debugPrint('[PosePlayback] Model not ready.');
      return;
    }
    _cancelPosePlayback();
    _poseFilters.clear();
    _palmSmoother.reset(); // Reset palm orientation smoother for new video
    _retargeter?.resetSmoothing(); // Reset advanced smoothing
    _isPosePlaying = true;
    _mixer?.stopAllAction();
    debugPrint('[PosePlayback] Uploading video for pose extraction...');

    // Reset progress
    _processingProgressNotifier.value = 0.0;

    try {
      // Use SSE endpoint với progress updates
      final result = await _poseApi.uploadVideoForPoseWithProgress(
        videoFile: videoFile,
        stride: 1,
        onProgress: (progress) {
          debugPrint(
              '[PosePlayback] Processing progress callback: ${progress.toStringAsFixed(1)}%');
          // Use ValueNotifier - works from any thread/context
          _processingProgressNotifier.value = progress;
        },
      );

      // Reset progress when complete
      _processingProgressNotifier.value = null;

      if (result.frames.isEmpty) {
        debugPrint('[PosePlayback] No frames returned from backend.');
        _isPosePlaying = false;
        return;
      }
      // Store result for download
      setState(() {
        _lastPoseResult = result;
      });
      _poseFrames = result.frames;
      _poseFrameIndex = 0;
      final fps = result.fps > 0 ? result.fps : 30.0;
      // Apply playback speed multiplier: higher multiplier = faster playback = lower stepMs
      final effectiveFps = fps * _playbackSpeedMultiplier;
      final stepMs =
          math.max(8, (1000 / effectiveFps).round()); // Min 8ms for 120fps max
      debugPrint(
          '[PosePlayback] Playing ${_poseFrames.length} frames at ~$fps fps (effective ~${effectiveFps.toStringAsFixed(1)} fps, step ${stepMs}ms)');
      _poseTimer = Timer.periodic(Duration(milliseconds: stepMs), (timer) {
        if (!_isPosePlaying) {
          timer.cancel();
          return;
        }
        if (_poseFrameIndex >= _poseFrames.length) {
          debugPrint('[PosePlayback] Completed video playback.');
          timer.cancel();
          _isPosePlaying = false;
          return;
        }
        final frame = _poseFrames[_poseFrameIndex];
        _poseFrameIndex++;
        _applyPoseFrame(frame, result);
      });
    } catch (e) {
      debugPrint('[PosePlayback] Error: $e');
      _processingProgressNotifier.value = null;
      setState(() {
        _isPosePlaying = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video processing failed: $e')),
        );
      }
    }
  }

  void _applyPoseFrame(FramePose frame, PoseExtractionResult meta) {
    final retargeter = _retargeter;
    if (retargeter == null) {
      debugPrint('[PosePlayback] Retargeter not ready.');
      return;
    }
    // Convert hand landmarks to List<Map> for buildMixamoPose
    final leftHand = frame.leftHandLandmarks
        ?.map((p) => <String, dynamic>{
              'x': p.x,
              'y': p.y,
              'z': p.z,
              'visibility': p.visibility ?? 1.0,
            })
        .toList();
    final rightHand = frame.rightHandLandmarks
        ?.map((p) => <String, dynamic>{
              'x': p.x,
              'y': p.y,
              'z': p.z,
              'visibility': p.visibility ?? 1.0,
            })
        .toList();

    final pose = mapping.buildMixamoPose(
      landmarksWorld: frame.landmarksWorld,
      leftHandLandmarks: leftHand,
      rightHandLandmarks: rightHand,
      palmSmoother: _palmSmoother,
    );
    if (pose.isEmpty) return;
    final t = _poseFrameIndex /
        (meta.fps > 0 ? meta.fps : 30.0); // timeline in seconds
    mapping.smoothMixamoPose(pose, t, _poseFilters);
    retargeter.applyPose(
      pose: pose,
      poseLandmarks: frame.landmarks,
      videoWidth: meta.width.toDouble(),
      videoHeight: meta.height.toDouble(),
      timestamp: t,
    );
  }

  void _cancelPosePlayback() {
    _poseTimer?.cancel();
    _poseTimer = null;
    _poseFrameIndex = 0;
    _isPosePlaying = false;
  }

  Future<void> _startLivePose() async {
    if (_model == null) {
      debugPrint('[LivePose] Model not ready.');
      return;
    }
    _cancelPosePlayback();
    _poseFilters.clear();
    await _livePoseSource.stop();
    await _livePoseSource.start();
    setState(() {
      _livePreview = _livePoseSource.preview;
    });
    _livePoseSub?.cancel();
    _livePoseSub = _livePoseSource.frames.listen((frame) {
      _applyLivePoseFrame(frame);
    });
    debugPrint('[LivePose] Started live camera pose stream.');
  }

  void _stopLivePose() {
    _livePoseSub?.cancel();
    _livePoseSub = null;
    _livePoseSource.stop();
  }

  void _applyLivePoseFrame(PoseFrame frame) {
    final retargeter = _retargeter;
    if (retargeter == null) return;
    if (frame.worldLandmarks.isEmpty) return;

    final pose = mapping.buildMixamoPose(
      landmarksWorld: frame.worldLandmarks,
      palmSmoother: _palmSmoother,
    );
    if (pose.isEmpty) return;

    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    mapping.smoothMixamoPose(pose, t, _poseFilters);
    retargeter.applyPose(
      pose: pose,
      poseLandmarks: frame.imageLandmarks,
      videoWidth: frame.width.toDouble(),
      videoHeight: frame.height.toDouble(),
    );
  }

  three.AnimationClip _buildYogaDemoClip() {
    // Simple looping "tree pose" style animation:
    // - Hands come together overhead
    // - Left leg lifts toward right thigh
    // - Small breathing sway via hips
    double deg(double d) => d * math.pi / 180.0;

    three.Quaternion qAxis(String axis, double degrees) {
      final q = three.Quaternion();
      switch (axis) {
        case 'x':
          q.setFromAxisAngle(three.Vector3(1, 0, 0), deg(degrees));
          break;
        case 'y':
          q.setFromAxisAngle(three.Vector3(0, 1, 0), deg(degrees));
          break;
        case 'z':
          q.setFromAxisAngle(three.Vector3(0, 0, 1), deg(degrees));
          break;
      }
      return q;
    }

    List<double> quatValues(three.Quaternion q) => [q.x, q.y, q.z, q.w];

    // Times in seconds for a 4s loop.
    const times = [0.0, 1.5, 3.0, 4.0];

    // Hips subtle sway left/right.
    final hipsTrack = three.VectorKeyframeTrack(
      'mixamorigHips.position',
      times,
      [
        0,
        0,
        0,
        0.05,
        0,
        -0.05,
        -0.05,
        0,
        0.05,
        0,
        0,
        0,
      ],
    );

    // Spine gentle bend backward then neutral.
    final spineTrack = three.QuaternionKeyframeTrack(
      'mixamorigSpine2.quaternion',
      times,
      [
        ...quatValues(qAxis('x', 5)),
        ...quatValues(qAxis('x', 10)),
        ...quatValues(qAxis('x', 5)),
        ...quatValues(qAxis('x', 5)),
      ],
    );

    // Arms rise overhead into prayer.
    final leftArmTrack = three.QuaternionKeyframeTrack(
      'mixamorigLeftArm.quaternion',
      times,
      [
        ...quatValues(qAxis('z', -10)),
        ...quatValues(qAxis('z', -50)),
        ...quatValues(qAxis('z', -50)),
        ...quatValues(qAxis('z', -10)),
      ],
    );

    final rightArmTrack = three.QuaternionKeyframeTrack(
      'mixamorigRightArm.quaternion',
      times,
      [
        ...quatValues(qAxis('z', 10)),
        ...quatValues(qAxis('z', 50)),
        ...quatValues(qAxis('z', 50)),
        ...quatValues(qAxis('z', 10)),
      ],
    );

    // Left leg lifts into tree pose, then returns.
    final leftLegTrack = three.QuaternionKeyframeTrack(
      'mixamorigLeftUpLeg.quaternion',
      times,
      [
        ...quatValues(qAxis('x', 0)),
        ...quatValues(qAxis('x', 25)),
        ...quatValues(qAxis('x', 25)),
        ...quatValues(qAxis('x', 0)),
      ],
    );

    // Keep right leg mostly stable with slight counter-balance.
    final rightLegTrack = three.QuaternionKeyframeTrack(
      'mixamorigRightUpLeg.quaternion',
      times,
      [
        ...quatValues(qAxis('x', 0)),
        ...quatValues(qAxis('x', -5)),
        ...quatValues(qAxis('x', -5)),
        ...quatValues(qAxis('x', 0)),
      ],
    );

    return three.AnimationClip('YogaTreeDemo', -1, [
      hipsTrack,
      spineTrack,
      leftArmTrack,
      rightArmTrack,
      leftLegTrack,
      rightLegTrack,
    ]);
  }

  void _logModelDiagnostics(dynamic gltf) {
    if (_loggedBones) return;
    _loggedBones = true;
    final model = gltf.scene;
    if (model == null) {
      debugPrint('[ModelDiag] Scene is null');
      return;
    }
    debugPrint(
        '[ModelDiag] Animations: ${gltf.animations?.length ?? 0} clips -> ${(gltf.animations ?? []).map((a) => a.name).join(', ')}');
    debugPrint('[ModelDiag] Traversing bones:');
    _logBones(model, '');

    if (!_printedMixamo) {
      _printedMixamo = true;
      debugPrint('[ModelDiag] Mixamo bone names:');
      for (final name in _mixamoBoneNames) {
        debugPrint('  $name');
      }
    }
  }

  void _logBones(three.Object3D obj, String indent) {
    final isBone = obj.type.toLowerCase() == 'bone';
    final mark = isBone ? '[Bone]' : '[Node]';
    debugPrint('$indent$mark ${obj.name}');
    for (final child in obj.children) {
      _logBones(child, '$indent  ');
    }
  }

  void _buildRetargeterFromModel(three.Object3D model) {
    final boneMap = _collectBones(model);

    // Log all bones found in the model
    debugPrint('[Retarget] ===== BONES IN MODEL =====');
    debugPrint('[Retarget] Total bones found: ${boneMap.length}');
    final boneNames = boneMap.keys.toList()..sort();
    for (final name in boneNames) {
      debugPrint('[Retarget]   - $name');
    }
    debugPrint('[Retarget] =========================');

    final resolved = <String, dynamic>{};
    for (final canonical in _canonicalBones) {
      final bone = _resolveBone(boneMap, _nameVariants(canonical));
      if (bone != null) {
        resolved[canonical] = bone;
      } else {
        debugPrint('[Retarget] Missing bone for $canonical');
      }
    }
    if (resolved.isNotEmpty) {
      _retargeter = MixamoRetargeter(modelRoot: model, bones: resolved);
      debugPrint(
          '[Retarget] Built retargeter with ${resolved.length}/${_canonicalBones.length} bones');
    } else {
      debugPrint('[Retarget] Failed to build retargeter (no bones resolved)');
    }
  }

  Map<String, dynamic> _collectBones(three.Object3D root) {
    final bones = <String, dynamic>{};
    root.traverse((obj) {
      if (obj.type.toLowerCase() == 'bone') {
        bones[obj.name] = obj;
      }
    });
    return bones;
  }

  dynamic _resolveBone(Map<String, dynamic> boneMap, List<String> candidates) {
    // Try exact match first
    for (final candidate in candidates) {
      final direct = boneMap[candidate];
      if (direct != null) return direct;
      final lower = candidate.toLowerCase();
      final hit = boneMap.entries
          .firstWhere(
            (e) => e.key.toLowerCase() == lower,
            orElse: () => const MapEntry('', null),
          )
          .value;
      if (hit != null) return hit;
    }

    // Try fuzzy matching if no exact match found
    for (final candidate in candidates) {
      final fuzzyMatch = _fuzzyMatchBone(boneMap, candidate);
      if (fuzzyMatch != null) {
        debugPrint(
            '[Retarget] Fuzzy match: "$candidate" → "${fuzzyMatch.key}"');
        return fuzzyMatch.value;
      }
    }

    return null;
  }

  /// Fuzzy matching: Find bone with similar name using keyword matching
  MapEntry<String, dynamic>? _fuzzyMatchBone(
      Map<String, dynamic> boneMap, String canonical) {
    // Normalize: remove common prefixes and convert to lowercase
    final normalized = canonical
        .toLowerCase()
        .replaceAll('mixamorig', '')
        .replaceAll('_', '')
        .replaceAll('-', '')
        .replaceAll(' ', '');

    // Extract keywords from canonical name
    final keywords = _extractKeywords(normalized);
    if (keywords.isEmpty) return null;

    MapEntry<String, dynamic>? bestMatch;
    double bestScore = 0.5; // Minimum similarity threshold

    for (final entry in boneMap.entries) {
      final boneName = entry.key
          .toLowerCase()
          .replaceAll('mixamorig', '')
          .replaceAll('_', '')
          .replaceAll('-', '')
          .replaceAll(' ', '');

      // Check if bone name contains all keywords
      bool containsAllKeywords = true;
      int matchedKeywords = 0;
      for (final keyword in keywords) {
        if (boneName.contains(keyword)) {
          matchedKeywords++;
        } else {
          containsAllKeywords = false;
        }
      }

      if (containsAllKeywords && matchedKeywords > 0) {
        // Calculate similarity score
        final score = matchedKeywords / keywords.length;
        if (score > bestScore) {
          bestScore = score;
          bestMatch = entry;
        }
      }
    }

    return bestMatch;
  }

  /// Extract keywords from bone name (e.g., "leftarm" -> ["left", "arm"])
  List<String> _extractKeywords(String name) {
    final keywords = <String>[];

    // Common bone parts
    final parts = [
      'hip',
      'hips',
      'pelvis',
      'spine',
      'spine1',
      'spine2',
      'chest',
      'neck',
      'head',
      'shoulder',
      'arm',
      'forearm',
      'hand',
      'thumb',
      'index',
      'middle',
      'ring',
      'pinky',
      'leg',
      'upleg',
      'knee',
      'foot',
      'toe',
      'eye',
      'left',
      'right',
    ];

    // Find matching parts in name
    for (final part in parts) {
      if (name.contains(part)) {
        keywords.add(part);
      }
    }

    return keywords;
  }

  List<String> _nameVariants(String canonical) => [
        canonical,
        'mixamorig$canonical',
        'mixamorig_$canonical',
        'mixamorig:$canonical',
      ];
}

/// Model URL used by JS version; referenced for consistency.
const Map<String, String> _modelAssets = {
  'Xbot': 'assets/models/Xbot.glb',
  'Michelle': 'assets/models/Michelle.glb',
  'hiphop': 'assets/models/hiphop.glb',
};

const List<String> _mixamoBoneNames = [
  'mixamorigHips',
  'mixamorigSpine',
  'mixamorigSpine1',
  'mixamorigSpine2',
  'mixamorigNeck',
  'mixamorigHead',
  'mixamorigHeadTop_End',
  'mixamorigLeftEye',
  'mixamorigRightEye',
  'mixamorigLeftShoulder',
  'mixamorigLeftArm',
  'mixamorigLeftForeArm',
  'mixamorigLeftHand',
  'mixamorigLeftHandThumb1',
  'mixamorigLeftHandThumb2',
  'mixamorigLeftHandThumb3',
  'mixamorigLeftHandThumb4',
  'mixamorigLeftHandIndex1',
  'mixamorigLeftHandIndex2',
  'mixamorigLeftHandIndex3',
  'mixamorigLeftHandIndex4',
  'mixamorigLeftHandMiddle1',
  'mixamorigLeftHandMiddle2',
  'mixamorigLeftHandMiddle3',
  'mixamorigLeftHandMiddle4',
  'mixamorigLeftHandRing1',
  'mixamorigLeftHandRing2',
  'mixamorigLeftHandRing3',
  'mixamorigLeftHandRing4',
  'mixamorigLeftHandPinky1',
  'mixamorigLeftHandPinky2',
  'mixamorigLeftHandPinky3',
  'mixamorigLeftHandPinky4',
  'mixamorigRightShoulder',
  'mixamorigRightArm',
  'mixamorigRightForeArm',
  'mixamorigRightHand',
  'mixamorigRightHandThumb1',
  'mixamorigRightHandThumb2',
  'mixamorigRightHandThumb3',
  'mixamorigRightHandThumb4',
  'mixamorigRightHandIndex1',
  'mixamorigRightHandIndex2',
  'mixamorigRightHandIndex3',
  'mixamorigRightHandIndex4',
  'mixamorigRightHandMiddle1',
  'mixamorigRightHandMiddle2',
  'mixamorigRightHandMiddle3',
  'mixamorigRightHandMiddle4',
  'mixamorigRightHandRing1',
  'mixamorigRightHandRing2',
  'mixamorigRightHandRing3',
  'mixamorigRightHandRing4',
  'mixamorigRightHandPinky1',
  'mixamorigRightHandPinky2',
  'mixamorigRightHandPinky3',
  'mixamorigRightHandPinky4',
  'mixamorigLeftUpLeg',
  'mixamorigLeftLeg',
  'mixamorigLeftFoot',
  'mixamorigLeftToeBase',
  'mixamorigLeftToe_End',
  'mixamorigRightUpLeg',
  'mixamorigRightLeg',
  'mixamorigRightFoot',
  'mixamorigRightToeBase',
  'mixamorigRightToe_End',
];

const List<String> _canonicalBones = [
  'Hips',
  'Spine',
  'Spine1',
  'Spine2',
  'Neck',
  'Head',
  'HeadTop_End',
  'LeftEye',
  'RightEye',
  'LeftShoulder',
  'LeftArm',
  'LeftForeArm',
  'LeftHand',
  'LeftHandThumb1',
  'LeftHandThumb2',
  'LeftHandThumb3',
  'LeftHandThumb4',
  'LeftHandIndex1',
  'LeftHandIndex2',
  'LeftHandIndex3',
  'LeftHandIndex4',
  'LeftHandMiddle1',
  'LeftHandMiddle2',
  'LeftHandMiddle3',
  'LeftHandMiddle4',
  'LeftHandRing1',
  'LeftHandRing2',
  'LeftHandRing3',
  'LeftHandRing4',
  'LeftHandPinky1',
  'LeftHandPinky2',
  'LeftHandPinky3',
  'LeftHandPinky4',
  'RightShoulder',
  'RightArm',
  'RightForeArm',
  'RightHand',
  'RightHandThumb1',
  'RightHandThumb2',
  'RightHandThumb3',
  'RightHandThumb4',
  'RightHandIndex1',
  'RightHandIndex2',
  'RightHandIndex3',
  'RightHandIndex4',
  'RightHandMiddle1',
  'RightHandMiddle2',
  'RightHandMiddle3',
  'RightHandMiddle4',
  'RightHandRing1',
  'RightHandRing2',
  'RightHandRing3',
  'RightHandRing4',
  'RightHandPinky1',
  'RightHandPinky2',
  'RightHandPinky3',
  'RightHandPinky4',
  'LeftUpLeg',
  'LeftLeg',
  'LeftFoot',
  'LeftToeBase',
  'LeftToe_End',
  'RightUpLeg',
  'RightLeg',
  'RightFoot',
  'RightToeBase',
  'RightToe_End',
];

/// Default backend base URL. Replace with your LAN IP / emulator loopback as needed.
/// - iOS Simulator: use 'http://localhost:8000' or 'http://127.0.0.1:8000'
/// - Android Emulator: use 'http://10.0.2.2:8000'
/// - Real device on same network: use your machine's IP like 'http://192.168.1.65:8000'
/// - Make sure backend is running with: uvicorn main:app --host 0.0.0.0 --port 8000
const String poseApiBaseUrl =
    'http://192.168.1.20:8000'; // Change to your actual backend URL
