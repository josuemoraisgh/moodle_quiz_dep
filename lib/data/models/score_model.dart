import '../../domain/entities/score_entity.dart';

/// Deserializa pontuações vindas do GSheets.
class ScoreModel extends ScoreEntity {
  const ScoreModel({
    required super.studentId,
    required super.studentName,
    required super.correctCount,
    required super.totalAnswered,
    required super.score,
    required super.rank,
    super.answeredPages,
    super.answeredPageRounds,
    super.previousRank,
  });

  factory ScoreModel.fromJson(Map<String, dynamic> json,
      {int? previousRank}) {
    final answeredPages = <int>[];
    final answeredPageRounds = <int, String>{};
    final rawPages = json['answered_pages'];
    if (rawPages is List) {
      for (final page in rawPages) {
        final parsed = int.tryParse(page.toString());
        if (parsed != null) {
          answeredPages.add(parsed);
        }
      }
    }
    final rawPageRounds = json['answered_page_rounds'];
    if (rawPageRounds is Map) {
      for (final entry in rawPageRounds.entries) {
        final parsed = int.tryParse(entry.key.toString());
        if (parsed != null) {
          answeredPageRounds[parsed] = entry.value?.toString() ?? '';
        }
      }
    }

    return ScoreModel(
      studentId: json['student_id']?.toString() ?? '',
      studentName: json['student_name']?.toString() ?? 'Desconhecido',
      correctCount:
          int.tryParse(json['correct_count']?.toString() ?? '') ?? 0,
      totalAnswered:
          int.tryParse(json['total_answered']?.toString() ?? '') ?? 0,
      score: int.tryParse(json['score']?.toString() ?? '') ?? 0,
      rank: int.tryParse(json['rank']?.toString() ?? '') ?? 99,
      answeredPages: answeredPages,
      answeredPageRounds: answeredPageRounds,
      previousRank: previousRank,
    );
  }
}
