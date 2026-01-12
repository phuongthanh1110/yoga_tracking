/// Practice session state enum.
enum PracticeState {
  idle,        // Chưa bắt đầu
  watching,    // Đang xem model chạy
  ready,       // Model xong, sẵn sàng tập
  practicing,  // Đang tập (camera đang ghi)
  analyzing,   // Đang phân tích điểm
  completed,   // Hoàn thành, hiển thị điểm
}

extension PracticeStateExtension on PracticeState {
  String get displayName {
    switch (this) {
      case PracticeState.idle:
        return 'Idle';
      case PracticeState.watching:
        return 'Watching Model';
      case PracticeState.ready:
        return 'Ready to Practice';
      case PracticeState.practicing:
        return 'Practicing';
      case PracticeState.analyzing:
        return 'Analyzing';
      case PracticeState.completed:
        return 'Completed';
    }
  }
}

