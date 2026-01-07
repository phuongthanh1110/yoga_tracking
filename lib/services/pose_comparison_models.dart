/// Pose Comparison Models (AQA - Action Quality Assessment)
///
/// These models represent the data structures for comparing user's yoga pose
/// against a trainer's reference pose.
///
/// Key concepts:
/// - Joint angles for scale-invariant comparison
/// - DTW (Dynamic Time Warping) for temporal alignment
/// - Weighted scoring based on joint importance

// =============================================================================
// Trainer Pose Models
// =============================================================================

/// Metadata for a trainer's reference pose
class TrainerPoseMetadata {
  final String id;
  final String name;
  final String? description;
  final String difficulty; // easy, medium, hard
  final double durationSeconds;
  final String createdAt;
  final String? category;

  const TrainerPoseMetadata({
    required this.id,
    required this.name,
    this.description,
    required this.difficulty,
    required this.durationSeconds,
    required this.createdAt,
    this.category,
  });

  factory TrainerPoseMetadata.fromJson(Map<String, dynamic> json) {
    return TrainerPoseMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      difficulty: json['difficulty'] as String? ?? 'medium',
      durationSeconds: (json['duration_seconds'] as num).toDouble(),
      createdAt: json['created_at'] as String,
      category: json['category'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'difficulty': difficulty,
        'duration_seconds': durationSeconds,
        'created_at': createdAt,
        'category': category,
      };
}

/// Item in trainer list (simplified for listing)
class TrainerListItem {
  final String id;
  final String name;
  final String? description;
  final String difficulty;
  final double durationSeconds;
  final String? category;

  const TrainerListItem({
    required this.id,
    required this.name,
    this.description,
    required this.difficulty,
    required this.durationSeconds,
    this.category,
  });

  factory TrainerListItem.fromJson(Map<String, dynamic> json) {
    return TrainerListItem(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      difficulty: json['difficulty'] as String? ?? 'medium',
      durationSeconds: (json['duration_seconds'] as num).toDouble(),
      category: json['category'] as String?,
    );
  }
}

/// Response from trainer list endpoint
class TrainerListResponse {
  final List<TrainerListItem> trainers;
  final int total;

  const TrainerListResponse({
    required this.trainers,
    required this.total,
  });

  factory TrainerListResponse.fromJson(Map<String, dynamic> json) {
    final trainersJson = json['trainers'] as List? ?? [];
    return TrainerListResponse(
      trainers: trainersJson
          .map((e) => TrainerListItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
    );
  }
}

/// Response from trainer upload endpoint
class TrainerUploadResponse {
  final bool success;
  final String trainerId;
  final String message;
  final TrainerPoseMetadata metadata;

  const TrainerUploadResponse({
    required this.success,
    required this.trainerId,
    required this.message,
    required this.metadata,
  });

  factory TrainerUploadResponse.fromJson(Map<String, dynamic> json) {
    return TrainerUploadResponse(
      success: json['success'] as bool,
      trainerId: json['trainer_id'] as String,
      message: json['message'] as String,
      metadata: TrainerPoseMetadata.fromJson(
          json['metadata'] as Map<String, dynamic>),
    );
  }
}

// =============================================================================
// Comparison Result Models
// =============================================================================

/// Score detail for a specific joint
class JointScoreDetail {
  final double score; // 0-100
  final double averageErrorDegrees;
  final double weight;

  const JointScoreDetail({
    required this.score,
    required this.averageErrorDegrees,
    required this.weight,
  });

  factory JointScoreDetail.fromJson(Map<String, dynamic> json) {
    return JointScoreDetail(
      score: (json['score'] as num).toDouble(),
      averageErrorDegrees: (json['average_error_degrees'] as num).toDouble(),
      weight: (json['weight'] as num).toDouble(),
    );
  }

  /// Get color based on score
  ScoreGrade get grade {
    if (score >= 85) return ScoreGrade.excellent;
    if (score >= 70) return ScoreGrade.good;
    if (score >= 50) return ScoreGrade.average;
    return ScoreGrade.needsWork;
  }
}

/// Grade enum for visual representation
enum ScoreGrade {
  excellent,
  good,
  average,
  needsWork,
}

/// A single feedback item with correction guidance
class FeedbackItem {
  final double timestamp; // seconds into the video
  final String joint;
  final String message;
  final double errorDegrees;
  final String severity; // low, medium, high

  const FeedbackItem({
    required this.timestamp,
    required this.joint,
    required this.message,
    required this.errorDegrees,
    required this.severity,
  });

  factory FeedbackItem.fromJson(Map<String, dynamic> json) {
    return FeedbackItem(
      timestamp: (json['timestamp'] as num).toDouble(),
      joint: json['joint'] as String,
      message: json['message'] as String,
      errorDegrees: (json['error_degrees'] as num).toDouble(),
      severity: json['severity'] as String,
    );
  }

  /// Format timestamp as MM:SS
  String get formattedTimestamp {
    final minutes = (timestamp / 60).floor();
    final seconds = (timestamp % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Information about DTW alignment
class AlignmentInfo {
  final int trainerFrames;
  final int userFrames;
  final int alignedPairs;

  const AlignmentInfo({
    required this.trainerFrames,
    required this.userFrames,
    required this.alignedPairs,
  });

  factory AlignmentInfo.fromJson(Map<String, dynamic> json) {
    return AlignmentInfo(
      trainerFrames: json['trainer_frames'] as int,
      userFrames: json['user_frames'] as int,
      alignedPairs: json['aligned_pairs'] as int,
    );
  }
}

/// Metadata about the comparison process
class ComparisonMetadata {
  final double trainerFps;
  final double userFps;
  final int jointsAnalyzed;

  const ComparisonMetadata({
    required this.trainerFps,
    required this.userFps,
    required this.jointsAnalyzed,
  });

  factory ComparisonMetadata.fromJson(Map<String, dynamic> json) {
    return ComparisonMetadata(
      trainerFps: (json['trainer_fps'] as num).toDouble(),
      userFps: (json['user_fps'] as num).toDouble(),
      jointsAnalyzed: json['joints_analyzed'] as int,
    );
  }
}

/// Complete result of pose comparison
class PoseComparisonResult {
  final bool success;
  final String? error;
  final double overallScore; // 0-100
  final double? dtwDistance;
  final double? averageAngleError;
  final Map<String, JointScoreDetail> jointScores;
  final List<FeedbackItem> feedback;
  final AlignmentInfo? alignmentInfo;
  final ComparisonMetadata? metadata;

  const PoseComparisonResult({
    required this.success,
    this.error,
    required this.overallScore,
    this.dtwDistance,
    this.averageAngleError,
    required this.jointScores,
    required this.feedback,
    this.alignmentInfo,
    this.metadata,
  });

  factory PoseComparisonResult.fromJson(Map<String, dynamic> json) {
    // Parse joint scores
    final jointScoresJson = json['joint_scores'] as Map<String, dynamic>? ?? {};
    final jointScores = jointScoresJson.map(
      (key, value) => MapEntry(
        key,
        JointScoreDetail.fromJson(value as Map<String, dynamic>),
      ),
    );

    // Parse feedback
    final feedbackJson = json['feedback'] as List? ?? [];
    final feedback = feedbackJson
        .map((e) => FeedbackItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return PoseComparisonResult(
      success: json['success'] as bool,
      error: json['error'] as String?,
      overallScore: (json['overall_score'] as num?)?.toDouble() ?? 0.0,
      dtwDistance: (json['dtw_distance'] as num?)?.toDouble(),
      averageAngleError: (json['average_angle_error'] as num?)?.toDouble(),
      jointScores: jointScores,
      feedback: feedback,
      alignmentInfo: json['alignment_info'] != null
          ? AlignmentInfo.fromJson(json['alignment_info'] as Map<String, dynamic>)
          : null,
      metadata: json['metadata'] != null
          ? ComparisonMetadata.fromJson(json['metadata'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Get overall grade
  ScoreGrade get grade {
    if (overallScore >= 85) return ScoreGrade.excellent;
    if (overallScore >= 70) return ScoreGrade.good;
    if (overallScore >= 50) return ScoreGrade.average;
    return ScoreGrade.needsWork;
  }

  /// Get feedback sorted by severity (high first)
  List<FeedbackItem> get sortedFeedback {
    final sorted = List<FeedbackItem>.from(feedback);
    sorted.sort((a, b) {
      final severityOrder = {'high': 0, 'medium': 1, 'low': 2};
      return (severityOrder[a.severity] ?? 3)
          .compareTo(severityOrder[b.severity] ?? 3);
    });
    return sorted;
  }

  /// Get unique feedback messages (deduplicated)
  List<FeedbackItem> get uniqueFeedback {
    final seen = <String>{};
    return feedback.where((f) => seen.add(f.message)).toList();
  }
}

// =============================================================================
// Helper Extensions
// =============================================================================

/// Extension for readable joint names
extension JointNameExtension on String {
  String get readableJointName {
    const names = {
      'left_elbow': 'Left Elbow',
      'right_elbow': 'Right Elbow',
      'left_knee': 'Left Knee',
      'right_knee': 'Right Knee',
      'left_hip': 'Left Hip',
      'right_hip': 'Right Hip',
      'left_shoulder': 'Left Shoulder',
      'right_shoulder': 'Right Shoulder',
      'spine_upper': 'Upper Spine',
      'left_ankle': 'Left Ankle',
      'right_ankle': 'Right Ankle',
    };
    return names[this] ?? replaceAll('_', ' ').toTitleCase();
  }
}

/// Extension for title case
extension StringExtension on String {
  String toTitleCase() {
    return split(' ')
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }
}

