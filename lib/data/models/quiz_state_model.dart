import '../../domain/entities/quiz_state_entity.dart';

/// Deserializa o estado do quiz vindo do GSheets/Apps Script.
class QuizStateModel extends QuizStateEntity {
  const QuizStateModel({
    required super.status,
    super.currentPage,
    super.currentSlot,
    super.totalPages,
    super.quizId,
    super.courseId,
    super.quizTitle,
    super.roundId,
    super.durationSeconds,
    super.startOnFirstResponse,
    super.timerStarted,
    super.startedAt,
    super.endsAt,
  });

  factory QuizStateModel.fromJson(Map<String, dynamic> json) {
    final statusStr = (json['state'] as String? ?? 'waiting').toLowerCase();
    final status = _parseStatus(statusStr);

    DateTime? endsAt;
    final endsAtStr = json['ends_at']?.toString();
    if (endsAtStr != null && endsAtStr.isNotEmpty) {
      endsAt = DateTime.tryParse(endsAtStr)?.toLocal();
    }

    DateTime? startedAt;
    final startedAtStr = json['started_at']?.toString();
    if (startedAtStr != null && startedAtStr.isNotEmpty) {
      startedAt = DateTime.tryParse(startedAtStr)?.toLocal();
    }

    return QuizStateModel(
      status: status,
      currentPage: int.tryParse(json['current_page']?.toString() ?? '') ?? -1,
      currentSlot: int.tryParse(json['current_slot']?.toString() ?? '') ?? 0,
      totalPages: int.tryParse(json['total_pages']?.toString() ?? '') ?? 0,
      quizId: int.tryParse(json['quiz_id']?.toString() ?? '') ?? 0,
      courseId: int.tryParse(json['course_id']?.toString() ?? '') ?? 0,
      quizTitle: json['quiz_name']?.toString() ?? 'Quiz',
      roundId: json['round_id']?.toString() ?? '',
      durationSeconds:
          int.tryParse(json['duration_seconds']?.toString() ?? '') ?? 0,
      startOnFirstResponse: json['start_on_first_response'] == true ||
          json['start_on_first_response']?.toString().toLowerCase() == 'true',
      timerStarted: json['timer_started'] == true ||
          json['timer_started']?.toString().toLowerCase() == 'true',
      startedAt: startedAt,
      endsAt: endsAt,
    );
  }

  static QuizStatus _parseStatus(String s) => switch (s) {
        'active' => QuizStatus.active,
        'closed' => QuizStatus.closed,
        'finished' => QuizStatus.finished,
        _ => QuizStatus.waiting,
      };
}
