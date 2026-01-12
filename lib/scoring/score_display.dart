import 'package:flutter/material.dart';
import 'score_result.dart';

/// Widget to display score results.
class ScoreDisplayDialog extends StatelessWidget {
  final ScoreResult scoreResult;

  const ScoreDisplayDialog({
    super.key,
    required this.scoreResult,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Practice Score',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Overall Score
              _buildScoreCard(
                'Overall Score',
                scoreResult.overallScore,
                Colors.blue,
              ),
              const SizedBox(height: 16),
              // Metrics
              Row(
                children: [
                  Expanded(
                    child: _buildScoreCard(
                      'Angle Accuracy',
                      scoreResult.angleAccuracy,
                      Colors.green,
                      isSmall: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildScoreCard(
                      'Position Accuracy',
                      scoreResult.positionAccuracy,
                      Colors.orange,
                      isSmall: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildScoreCard(
                'Stability',
                scoreResult.stabilityScore,
                Colors.purple,
                isSmall: true,
              ),
              const SizedBox(height: 24),
              // Feedback
              if (scoreResult.feedback.isNotEmpty) ...[
                const Text(
                  'Feedback',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...scoreResult.feedback.map((fb) => _buildFeedbackItem(fb)),
              ],
              const SizedBox(height: 16),
              // Close button
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreCard(
    String label,
    double score,
    Color color, {
    bool isSmall = false,
  }) {
    return Container(
      padding: EdgeInsets.all(isSmall ? 12 : 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isSmall ? 12 : 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${score.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: isSmall ? 20 : 32,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackItem(FeedbackItem feedback) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Frame ${feedback.frameIndex + 1}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            feedback.message,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

