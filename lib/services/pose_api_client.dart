import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class LandmarkPoint {
  LandmarkPoint({
    required this.x,
    required this.y,
    required this.z,
    this.visibility,
  });

  final double x;
  final double y;
  final double z;
  final double? visibility;

  factory LandmarkPoint.fromJson(Map<String, dynamic> json) {
    return LandmarkPoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num).toDouble(),
      visibility: json['visibility'] == null
          ? null
          : (json['visibility'] as num).toDouble(),
    );
  }
}

class FramePose {
  FramePose({
    required this.frameIndex,
    required this.landmarks,
    required this.landmarksWorld,
    required this.leftHandLandmarks,
    required this.rightHandLandmarks,
    required this.leftHandWorldLandmarks,
    required this.rightHandWorldLandmarks,
    required this.faceLandmarks,
    this.segmentationMask,
  });

  final int frameIndex;
  final List<LandmarkPoint> landmarks;
  final List<LandmarkPoint> landmarksWorld;
  final List<LandmarkPoint> leftHandLandmarks;
  final List<LandmarkPoint> rightHandLandmarks;
  final List<LandmarkPoint> leftHandWorldLandmarks;
  final List<LandmarkPoint> rightHandWorldLandmarks;
  final List<LandmarkPoint> faceLandmarks;
  final String? segmentationMask;

  factory FramePose.fromJson(Map<String, dynamic> json) {
    List<dynamic> pick(String key, String alt) {
      if (json.containsKey(key)) return json[key] as List;
      if (json.containsKey(alt)) return json[alt] as List;
      return const [];
    }

    final img = pick('poseLandmarks', 'landmarks')
        .map((e) => LandmarkPoint.fromJson(e as Map<String, dynamic>))
        .toList();
    final world = pick('poseWorldLandmarks', 'pose_world_landmarks')
        .map((e) => LandmarkPoint.fromJson(e as Map<String, dynamic>))
        .toList();

    return FramePose(
      frameIndex: json['frame_index'] as int,
      landmarks: img,
      landmarksWorld: world.isNotEmpty ? world : img,
      leftHandLandmarks: pick('leftHandLandmarks', 'left_hand_landmarks')
          .map((e) => LandmarkPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      rightHandLandmarks: pick('rightHandLandmarks', 'right_hand_landmarks')
          .map((e) => LandmarkPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      leftHandWorldLandmarks:
          pick('leftHandWorldLandmarks', 'left_hand_world_landmarks')
              .map((e) => LandmarkPoint.fromJson(e as Map<String, dynamic>))
              .toList(),
      rightHandWorldLandmarks:
          pick('rightHandWorldLandmarks', 'right_hand_world_landmarks')
              .map((e) => LandmarkPoint.fromJson(e as Map<String, dynamic>))
              .toList(),
      faceLandmarks: pick('faceLandmarks', 'face_landmarks')
          .map((e) => LandmarkPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      segmentationMask: json['segmentationMask'] as String?,
    );
  }
}

class PoseExtractionResult {
  PoseExtractionResult({
    required this.frames,
    required this.frameCount,
    required this.fps,
    required this.width,
    required this.height,
    this.metadata,
    this.landmarkIndices,
    this.handLandmarkIndices,
    this.faceLandmarkIndices,
  });

  final List<FramePose> frames;
  final int frameCount;
  final double fps;
  final int width;
  final int height;
  final Map<String, dynamic>? metadata;
  final Map<String, dynamic>? landmarkIndices;
  final Map<String, dynamic>? handLandmarkIndices;
  final Map<String, dynamic>? faceLandmarkIndices;

  factory PoseExtractionResult.fromJson(Map<String, dynamic> json) {
    final framesJson = json['frames'] as List? ?? const [];
    final frames = framesJson
        .map((e) => FramePose.fromJson(e as Map<String, dynamic>))
        .toList();
    return PoseExtractionResult(
      frames: frames,
      frameCount: json['frame_count'] as int? ?? frames.length,
      fps: (json['fps'] as num?)?.toDouble() ?? 0.0,
      width: json['width'] as int? ?? 0,
      height: json['height'] as int? ?? 0,
      metadata: json['metadata'] as Map<String, dynamic>?,
      landmarkIndices: json['landmarkIndices'] as Map<String, dynamic>?,
      handLandmarkIndices: json['handLandmarkIndices'] as Map<String, dynamic>?,
      faceLandmarkIndices: json['faceLandmarkIndices'] as Map<String, dynamic>?,
    );
  }
}

/// Simple API client to call the backend pose extractor.
class PoseApiClient {
  PoseApiClient({required this.baseUrl});

  final String baseUrl; // e.g. http://localhost:8000

  Future<PoseExtractionResult> uploadVideoForPose({
    required File videoFile,
    int stride = 1,
  }) async {
    final uri = Uri.parse('$baseUrl/pose/extract?stride=$stride');
    final contentType = _guessContentType(videoFile.path);
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          videoFile.path,
          contentType: contentType,
        ),
      );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw Exception(
          'Pose extraction failed (${response.statusCode}): ${response.body}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return PoseExtractionResult.fromJson(data);
  }

  MediaType _guessContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp4')) return MediaType('video', 'mp4');
    if (lower.endsWith('.mov')) return MediaType('video', 'quicktime');
    if (lower.endsWith('.avi')) return MediaType('video', 'x-msvideo');
    if (lower.endsWith('.mkv')) return MediaType('video', 'x-matroska');
    if (lower.endsWith('.webm')) return MediaType('video', 'webm');
    return MediaType('application', 'octet-stream');
  }
}
