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

  Map<String, dynamic> toJson() {
    // Round to 4 decimal places to reduce file size (Option 6B)
    final map = <String, dynamic>{
      'x': double.parse(x.toStringAsFixed(4)),
      'y': double.parse(y.toStringAsFixed(4)),
      'z': double.parse(z.toStringAsFixed(4)),
    };
    if (visibility != null) {
      map['visibility'] = double.parse(visibility!.toStringAsFixed(4));
    }
    return map;
  }
}

class FramePose {
  FramePose({
    required this.frameIndex,
    required this.landmarks,
    required this.landmarksWorld,
    this.segmentationMask,
    this.faceLandmarks,
    this.leftHandLandmarks,
    this.rightHandLandmarks,
  });

  final int frameIndex;
  final List<LandmarkPoint> landmarks;
  final List<LandmarkPoint> landmarksWorld;
  final String? segmentationMask;
  final List<LandmarkPoint>? faceLandmarks;
  final List<LandmarkPoint>? leftHandLandmarks;
  final List<LandmarkPoint>? rightHandLandmarks;

  factory FramePose.fromJson(Map<String, dynamic> json) {
    List<LandmarkPoint> parseLandmarks(List<dynamic>? data) {
      if (data == null || data.isEmpty) return [];
      return data
          .map((e) => LandmarkPoint.fromJson(e as Map<String, dynamic>))
          .toList();
    }

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
      segmentationMask: json['segmentationMask'] as String?,
      faceLandmarks: parseLandmarks(json['faceLandmarks'] as List?),
      leftHandLandmarks: parseLandmarks(json['leftHandLandmarks'] as List?),
      rightHandLandmarks: parseLandmarks(json['rightHandLandmarks'] as List?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'frame_index': frameIndex,
      // Option 6B: Commented out poseLandmarks (image coordinates) to reduce file size
      // Uncomment below if needed for 2D visualization/overlay on video
      // 'poseLandmarks': landmarks.map((p) => p.toJson()).toList(),
      'poseWorldLandmarks': landmarksWorld.map((p) => p.toJson()).toList(),
      'faceLandmarks': faceLandmarks?.map((p) => p.toJson()).toList(),
      'leftHandLandmarks': leftHandLandmarks?.map((p) => p.toJson()).toList(),
      'rightHandLandmarks': rightHandLandmarks?.map((p) => p.toJson()).toList(),
      if (segmentationMask != null) 'segmentationMask': segmentationMask,
    };
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
  });

  final List<FramePose> frames;
  final int frameCount;
  final double fps;
  final int width;
  final int height;
  final Map<String, dynamic>? metadata;
  final Map<String, dynamic>? landmarkIndices;

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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'metadata': metadata,
      'landmarkIndices': landmarkIndices,
      'frames': frames.map((f) => f.toJson()).toList(),
      'frame_count': frameCount,
      'fps': fps,
      'width': width,
      'height': height,
    };
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

  /// Upload video with SSE progress updates
  /// Returns Stream of progress updates (0.0 to 100.0)
  /// Throws exception if processing fails
  Stream<double> uploadVideoWithProgress({
    required File videoFile,
    int stride = 1,
  }) async* {
    final uri = Uri.parse('$baseUrl/pose/extract/stream?stride=$stride');
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
    if (streamed.statusCode != 200) {
      final errorBody = await http.Response.fromStream(streamed);
      throw Exception(
          'Pose extraction failed (${streamed.statusCode}): ${errorBody.body}');
    }

    // Parse SSE stream
    final responseStream = streamed.stream.transform(utf8.decoder);
    String buffer = '';

    await for (final chunk in responseStream) {
      buffer += chunk;

      // Parse SSE messages (separated by \n\n)
      final lines = buffer.split('\n\n');
      buffer = lines.removeLast(); // Keep incomplete line

      for (final line in lines) {
        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6); // Remove "data: "
          try {
            final data = json.decode(jsonStr) as Map<String, dynamic>;

            if (data['type'] == 'progress') {
              final progress = (data['progress'] as num).toDouble();
              yield progress.clamp(0.0, 100.0);
            } else if (data['type'] == 'complete') {
              // Final progress
              yield 100.0;
              return; // Stream complete
            } else if (data['type'] == 'error') {
              throw Exception(data['error'] ?? 'Processing failed');
            }
          } catch (e) {
            if (e is Exception) {
              rethrow;
            }
            // JSON decode error - skip this message
            continue;
          }
        }
      }
    }
  }

  /// Upload video with SSE progress updates and return result
  /// onProgress callback is called with progress (0.0 to 100.0)
  Future<PoseExtractionResult> uploadVideoForPoseWithProgress({
    required File videoFile,
    int stride = 1,
    Function(double progress)? onProgress,
  }) async {
    final uri = Uri.parse('$baseUrl/pose/extract/stream?stride=$stride');
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
    if (streamed.statusCode != 200) {
      final errorBody = await http.Response.fromStream(streamed);
      throw Exception(
          'Pose extraction failed (${streamed.statusCode}): ${errorBody.body}');
    }

    // Parse SSE stream
    final responseStream = streamed.stream.transform(utf8.decoder);
    String buffer = '';
    PoseExtractionResult? result;

    await for (final chunk in responseStream) {
      buffer += chunk;

      // Parse SSE messages (separated by \n\n)
      // SSE format: "data: {...}\n\n"
      // Process all complete messages (those ending with \n\n)
      while (buffer.contains('\n\n')) {
        final index = buffer.indexOf('\n\n');
        final message = buffer.substring(0, index);
        buffer = buffer.substring(index + 2); // Remove processed message + \n\n

        final trimmed = message.trim();
        if (trimmed.isEmpty) continue;

        // Find "data: " line - in SSE, each message is "data: <json>\n\n"
        final lines = trimmed.split('\n');
        String? dataLine;
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            dataLine = line;
            break; // Take first data line
          }
        }

        if (dataLine == null) continue;

        final jsonStr = dataLine.substring(6).trim(); // Remove "data: "
        if (jsonStr.isEmpty) continue;

        try {
          final data = json.decode(jsonStr) as Map<String, dynamic>;
          final messageType = data['type'] as String?;

          if (messageType == 'progress') {
            final progress = (data['progress'] as num).toDouble();
            onProgress?.call(progress.clamp(0.0, 100.0));
          } else if (messageType == 'complete') {
            // Extract result
            final resultData = data['result'] as Map<String, dynamic>;
            result = PoseExtractionResult.fromJson(resultData);
            onProgress?.call(100.0);
            break;
          } else if (messageType == 'error') {
            final errorMsg = data['error'] ?? 'Processing failed';
            throw Exception(errorMsg);
          }
        } catch (e) {
          if (e is FormatException) {
            // FormatException with "Unexpected end of input" means JSON was cut off
            final errorMsg = e.toString();
            if (errorMsg.contains('Unexpected end of input')) {
              // Put message back into buffer and wait for more data
              buffer = message + '\n\n' + buffer;
              break; // Break while loop, continue outer loop to get more data
            }
            // Other FormatException - skip this message
            continue;
          }
          if (e is Exception &&
              (e.toString().contains('Processing failed') ||
                  e.toString().contains('error'))) {
            rethrow;
          }
          // Other error - skip
          continue;
        }

        if (result != null) {
          break;
        }
      }

      if (result != null) {
        break;
      }
    }

    if (result == null) {
      throw Exception('Stream ended without complete result');
    }

    return result;
  }
}
