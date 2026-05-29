import 'dart:typed_data';

import '../entities/local_quiz_entity.dart';
import '../entities/local_user_entity.dart';
import '../entities/question_entity.dart';
import '../entities/quiz_state_entity.dart';
import '../entities/score_entity.dart';

abstract class ILocalQuizRepository {
  // ── Quizzes ────────────────────────────────────────────────────────────────
  Future<List<LocalQuizEntity>> getQuizzes();
  Future<LocalQuizEntity?> getQuiz(int quizId);
  Future<LocalQuizEntity> importFromXml(Uint8List bytes, String fileName);
  Future<void> deleteQuiz(int quizId);

  // ── Estado do quiz ─────────────────────────────────────────────────────────
  Future<QuizStateEntity> getQuizState();
  Future<void> setSelectedQuiz(int quizId, String quizName);
  Future<void> releaseQuestion({
    required int page,
    required int slot,
    required int duration,
    required bool startOnFirstResponse,
    required int totalPages,
    required String quizName,
    required int quizId,
  });
  Future<QuizStateEntity> startQuestionTimerIfNeeded();
  Future<void> closeQuestion();
  Future<void> setFinished();
  Future<void> resetQuiz();

  // ── Pontuações ─────────────────────────────────────────────────────────────
  Future<List<ScoreEntity>> getScores();

  /// Submete a resposta do aluno e retorna true se correta.
  Future<bool> submitAnswer({
    required LocalUserEntity student,
    required QuestionEntity question,
    required Map<String, String> answers,
    required String roundId,
    required int sessionId,
    required int secondsRemaining,
    required int totalDuration,
  });

  /// Persiste a pontuação no servidor local (para exibição em tempo real).
  Future<void> submitScore({
    required LocalUserEntity student,
    required int score,
    required bool correct,
    required int page,
  });
}
