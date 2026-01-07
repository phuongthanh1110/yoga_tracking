import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'pose_comparison_models.dart';

/// Service for yoga pose comparison API calls
///
/// Handles:
/// - Uploading trainer reference videos
/// - Listing available trainer poses
/// - Comparing user videos against trainers
/// - Comparing pre-extracted pose JSON data
class ComparisonService {
  ComparisonService({required this.baseUrl});

  final String baseUrl;

  // ===========================================================================
  // Trainer Management
  // ===========================================================================

  /// Upload a trainer reference video
  ///
  /// [videoFile] - The trainer's reference video file
  /// [name] - Name for this pose (e.g., "Warrior II")
  /// [description] - Optional description
  /// [difficulty] - easy, medium, or hard
  /// [category] - Optional category (e.g., "standing", "balance")
  /// [stride] - Frame stride for processing (default: 1)
  /// [onProgress] - Optional callback for upload progress (0.0 to 1.0)
  Future<TrainerUploadResponse> uploadTrainerVideo({
    required File videoFile,
    required String name,
    String? description,
    String difficulty = 'medium',
    String? category,
    int stride = 1,
    Function(double)? onProgress,
  }) async {
    final uri = Uri.parse('$baseUrl/trainer/upload');
    final contentType = _guessContentType(videoFile.path);

    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          videoFile.path,
          contentType: contentType,
        ),
      )
      ..fields['name'] = name
      ..fields['difficulty'] = difficulty
      ..fields['stride'] = stride.toString();

    if (description != null) {
      request.fields['description'] = description;
    }
    if (category != null) {
      request.fields['category'] = category;
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception(
          'Trainer upload failed (${response.statusCode}): ${response.body}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return TrainerUploadResponse.fromJson(data);
  }

  /// List all available trainer poses
  ///
  /// [category] - Optional filter by category
  /// [difficulty] - Optional filter by difficulty
  Future<TrainerListResponse> listTrainers({
    String? category,
    String? difficulty,
  }) async {
    final queryParams = <String, String>{};
    if (category != null) queryParams['category'] = category;
    if (difficulty != null) queryParams['difficulty'] = difficulty;

    final uri = Uri.parse('$baseUrl/trainer/list').replace(
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to list trainers (${response.statusCode}): ${response.body}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return TrainerListResponse.fromJson(data);
  }

  /// Get detailed trainer pose data
  Future<Map<String, dynamic>> getTrainerDetails(String trainerId) async {
    final uri = Uri.parse('$baseUrl/trainer/$trainerId');
    final response = await http.get(uri);

    if (response.statusCode == 404) {
      throw Exception('Trainer pose not found');
    }

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to get trainer (${response.statusCode}): ${response.body}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Delete a trainer pose
  Future<void> deleteTrainer(String trainerId) async {
    final uri = Uri.parse('$baseUrl/trainer/$trainerId');
    final response = await http.delete(uri);

    if (response.statusCode == 404) {
      throw Exception('Trainer pose not found');
    }

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to delete trainer (${response.statusCode}): ${response.body}');
    }
  }

  // ===========================================================================
  // Pose Comparison
  // ===========================================================================

  /// Compare user's video against a trainer's reference
  ///
  /// This is the main comparison method that:
  /// 1. Uploads user's video
  /// 2. Extracts pose landmarks server-side
  /// 3. Compares against trainer using DTW
  /// 4. Returns detailed score and feedback
  ///
  /// [trainerId] - ID of the trainer pose to compare against
  /// [userVideoFile] - User's recorded video
  /// [stride] - Frame stride for processing (higher = faster but less accurate)
  Future<PoseComparisonResult> compareVideoToTrainer({
    required String trainerId,
    required File userVideoFile,
    int stride = 1,
  }) async {
    final uri =
        Uri.parse('$baseUrl/compare/$trainerId').replace(queryParameters: {
      'stride': stride.toString(),
    });

    final contentType = _guessContentType(userVideoFile.path);

    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          userVideoFile.path,
          contentType: contentType,
        ),
      );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 404) {
      throw Exception('Trainer pose not found');
    }

    if (response.statusCode != 200) {
      throw Exception(
          'Comparison failed (${response.statusCode}): ${response.body}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return PoseComparisonResult.fromJson(data);
  }

  /// Compare pre-extracted pose JSON against a trainer
  ///
  /// This is useful when:
  /// - User extracts poses locally on device
  /// - Saves bandwidth by not uploading the full video
  ///
  /// [trainerId] - ID of the trainer pose to compare against
  /// [userPoseData] - Map containing 'frames' and 'fps'
  Future<PoseComparisonResult> compareJsonToTrainer({
    required String trainerId,
    required Map<String, dynamic> userPoseData,
  }) async {
    final uri = Uri.parse('$baseUrl/compare/json/$trainerId');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(userPoseData),
    );

    if (response.statusCode == 404) {
      throw Exception('Trainer pose not found');
    }

    if (response.statusCode != 200) {
      throw Exception(
          'Comparison failed (${response.statusCode}): ${response.body}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return PoseComparisonResult.fromJson(data);
  }

  // ===========================================================================
  // Helper Methods
  // ===========================================================================

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

