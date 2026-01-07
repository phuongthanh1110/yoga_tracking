import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/comparison_service.dart';
import '../services/pose_comparison_models.dart';
import 'video_recorder_page.dart';

/// Page for selecting a trainer pose to compare against
///
/// Features:
/// - List of available trainer poses
/// - Filter by difficulty/category
/// - Upload new trainer videos
/// - Navigate to video recording for comparison
class TrainerSelectionPage extends StatefulWidget {
  const TrainerSelectionPage({
    super.key,
    required this.baseUrl,
  });

  final String baseUrl;

  @override
  State<TrainerSelectionPage> createState() => _TrainerSelectionPageState();
}

class _TrainerSelectionPageState extends State<TrainerSelectionPage> {
  late final ComparisonService _service;
  List<TrainerListItem> _trainers = [];
  bool _isLoading = true;
  String? _error;
  String? _selectedDifficulty;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _service = ComparisonService(baseUrl: widget.baseUrl);
    _loadTrainers();
  }

  Future<void> _loadTrainers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _service.listTrainers(
        difficulty: _selectedDifficulty,
      );
      setState(() {
        _trainers = response.trainers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load trainers: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _uploadTrainer() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path == null) return;

    // Show dialog to get trainer details
    final details = await showDialog<_TrainerDetails>(
      context: context,
      builder: (ctx) => _TrainerDetailsDialog(),
    );

    if (details == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
      await _service.uploadTrainerVideo(
        videoFile: File(path),
        name: details.name,
        description: details.description,
        difficulty: details.difficulty,
      );

      // Reload trainers
      await _loadTrainers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Trainer "${details.name}" uploaded successfully!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  void _selectTrainer(TrainerListItem trainer) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoRecorderPage(
          trainer: trainer,
          baseUrl: widget.baseUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Select Trainer Pose'),
        actions: [
          // Filter button
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _selectedDifficulty = value;
              });
              _loadTrainers();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: null,
                child: Text('All Difficulties'),
              ),
              const PopupMenuItem(
                value: 'easy',
                child: Text('Easy'),
              ),
              const PopupMenuItem(
                value: 'medium',
                child: Text('Medium'),
              ),
              const PopupMenuItem(
                value: 'hard',
                child: Text('Hard'),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : _uploadTrainer,
        backgroundColor: Colors.teal,
        icon: _isUploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add),
        label: Text(_isUploading ? 'Uploading...' : 'Add Trainer'),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.teal),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadTrainers,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_trainers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.self_improvement,
                color: Colors.white.withOpacity(0.3),
                size: 80,
              ),
              const SizedBox(height: 24),
              Text(
                'No trainer poses yet',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Upload a trainer video to get started',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTrainers,
      color: Colors.teal,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _trainers.length,
        itemBuilder: (context, index) {
          final trainer = _trainers[index];
          return _buildTrainerCard(trainer);
        },
      ),
    );
  }

  Widget _buildTrainerCard(TrainerListItem trainer) {
    return GestureDetector(
      onTap: () => _selectTrainer(trainer),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _getDifficultyColor(trainer.difficulty).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.self_improvement,
                color: _getDifficultyColor(trainer.difficulty),
                size: 28,
              ),
            ),
            const SizedBox(width: 16),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trainer.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (trainer.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      trainer.description!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Difficulty badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getDifficultyColor(trainer.difficulty)
                              .withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          trainer.difficulty.toUpperCase(),
                          style: TextStyle(
                            color: _getDifficultyColor(trainer.difficulty),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Duration
                      Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: Colors.white.withOpacity(0.4),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(trainer.durationSeconds),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Arrow
            Icon(
              Icons.chevron_right,
              color: Colors.white.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return const Color(0xFF3FB950);
      case 'hard':
        return const Color(0xFFF85149);
      default:
        return const Color(0xFFD29922);
    }
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    if (minutes > 0) {
      return '${minutes}m ${secs}s';
    }
    return '${secs}s';
  }
}

// =============================================================================
// Dialog for entering trainer details
// =============================================================================

class _TrainerDetails {
  final String name;
  final String? description;
  final String difficulty;

  _TrainerDetails({
    required this.name,
    this.description,
    required this.difficulty,
  });
}

class _TrainerDetailsDialog extends StatefulWidget {
  @override
  State<_TrainerDetailsDialog> createState() => _TrainerDetailsDialogState();
}

class _TrainerDetailsDialogState extends State<_TrainerDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _difficulty = 'medium';

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Trainer Details',
        style: TextStyle(color: Colors.white),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Name field
            TextFormField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Pose Name *',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Description field
            TextFormField(
              controller: _descriptionController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Difficulty dropdown
            DropdownButtonFormField<String>(
              value: _difficulty,
              dropdownColor: const Color(0xFF21262D),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Difficulty',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'easy', child: Text('Easy')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'hard', child: Text('Hard')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _difficulty = value;
                  });
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_TrainerDetails(
                name: _nameController.text.trim(),
                description: _descriptionController.text.trim().isNotEmpty
                    ? _descriptionController.text.trim()
                    : null,
                difficulty: _difficulty,
              ));
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
          ),
          child: const Text('Upload'),
        ),
      ],
    );
  }
}

