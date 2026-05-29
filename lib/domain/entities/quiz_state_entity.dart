import 'package:equatable/equatable.dart';

/// Estados possíveis do quiz.
enum QuizStatus { waiting, active, closed, finished }

/// Snapshot do estado atual do quiz no servidor (Google Sheets).
class QuizStateEntity extends Equatable {
  final QuizStatus status;
  final int currentPage;
  final int currentSlot;
  final int totalPages;
  final int quizId;
  final int courseId;
  final String quizTitle;
  final String roundId;
  final int durationSeconds;
  final bool startOnFirstResponse;
  final bool timerStarted;
  final DateTime? startedAt;
  final DateTime? endsAt;

  const QuizStateEntity({
    required this.status,
    this.currentPage = -1,
    this.currentSlot = 0,
    this.totalPages = 0,
    this.quizId = 0,
    this.courseId = 0,
    this.quizTitle = 'Quiz',
    this.roundId = '',
    this.durationSeconds = 0,
    this.startOnFirstResponse = false,
    this.timerStarted = false,
    this.startedAt,
    this.endsAt,
  });

  /// Segundos restantes calculados localmente.
  int get secondsRemaining {
    if (endsAt == null || status != QuizStatus.active) return 0;
    final diff = endsAt!.difference(DateTime.now()).inSeconds;
    return diff < 0 ? 0 : diff;
  }

  bool get isActive => status == QuizStatus.active;
  bool get isWaiting => status == QuizStatus.waiting;
  bool get isClosed => status == QuizStatus.closed;
  bool get isFinished => status == QuizStatus.finished;
  bool get hasStarted => startedAt != null && endsAt != null;
  bool get isTimerPending =>
      isActive && startOnFirstResponse && durationSeconds > 0 && !timerStarted;

  static QuizStateEntity empty() =>
      const QuizStateEntity(status: QuizStatus.waiting);

  @override
  List<Object?> get props => [
        status,
        currentPage,
        currentSlot,
        roundId,
        durationSeconds,
        startOnFirstResponse,
        timerStarted,
        startedAt,
        endsAt,
      ];
}
