/// Score result from pose comparison.
class ScoreResult {
  ScoreResult({
    required this.overallScore,
    required this.angleAccuracy,
    required this.positionAccuracy,
    required this.stabilityScore,
    required this.frameScores,
    required this.feedback,
  });

  final double overallScore;
  final double angleAccuracy;
  final double positionAccuracy;
  final double stabilityScore;
  final List<double> frameScores;
  final List<FeedbackItem> feedback;

  factory ScoreResult.fromJson(Map<String, dynamic> json) {
    return ScoreResult(
      overallScore: (json['overall_score'] as num).toDouble(),
      angleAccuracy: (json['angle_accuracy'] as num).toDouble(),
      positionAccuracy: (json['position_accuracy'] as num).toDouble(),
      stabilityScore: (json['stability_score'] as num).toDouble(),
      frameScores: (json['frame_scores'] as List)
          .map((e) => (e as num).toDouble())
          .toList(),
      feedback: (json['feedback'] as List)
          .map((e) => FeedbackItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Feedback item for a specific frame.
class FeedbackItem {
  FeedbackItem({
    required this.frameIndex,
    required this.joint,
    required this.error,
    required this.message,
  });

  final int frameIndex;
  final String joint;
  final double error;
  final String message;

  factory FeedbackItem.fromJson(Map<String, dynamic> json) {
    return FeedbackItem(
      frameIndex: json['frame_index'] as int,
      joint: json['joint'] as String,
      error: (json['error'] as num).toDouble(),
      message: json['message'] as String,
    );
  }
}

