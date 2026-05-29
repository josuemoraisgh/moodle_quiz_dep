import 'package:equatable/equatable.dart';

/// Pontuação de um estudante no quiz.
class ScoreEntity extends Equatable {
  final String studentId;
  final String studentName;
  final int correctCount;
  final int totalAnswered;
  final int score;
  final int rank;
  final List<int> answeredPages;
  final Map<int, String> answeredPageRounds;
  final int? previousRank; // para animar mudança de posição

  const ScoreEntity({
    required this.studentId,
    required this.studentName,
    required this.correctCount,
    required this.totalAnswered,
    required this.score,
    required this.rank,
    this.answeredPages = const [],
    this.answeredPageRounds = const {},
    this.previousRank,
  });

  /// Indica se subiu no ranking em relação à rodada anterior.
  bool get movedUp =>
      previousRank != null && rank < previousRank!;

  bool get movedDown =>
      previousRank != null && rank > previousRank!;

  String get initials {
    final parts = studentName.trim().split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  List<Object?> get props => [studentId, rank, score];
}
