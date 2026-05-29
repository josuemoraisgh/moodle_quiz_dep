import 'package:equatable/equatable.dart';

/// Registro de resposta de um aluno a uma questão específica.
class AnswerRecordEntity extends Equatable {
  final int id;
  final int sessionId;
  final int studentId;
  final String studentName;
  final int questionSlot;
  final String roundId;
  final Map<String, String> answerData;
  final bool isCorrect;
  final int score;
  final DateTime answeredAt;

  const AnswerRecordEntity({
    required this.id,
    required this.sessionId,
    required this.studentId,
    required this.studentName,
    required this.questionSlot,
    required this.roundId,
    required this.answerData,
    required this.isCorrect,
    required this.score,
    required this.answeredAt,
  });

  @override
  List<Object?> get props => [id, sessionId, studentId, questionSlot, roundId];
}
