import '../entities/question_entity.dart';
import '../entities/user_entity.dart';
import '../repositories/i_quiz_repository.dart';

/// S: Único propósito – submeter resposta ao Moodle e pontuação ao leaderboard.
class SubmitAnswerUseCase {
  final IQuizRepository _repository;

  const SubmitAnswerUseCase(this._repository);

  /// Retorna se a resposta foi correta.
  /// [answers] é o mapa unificado de inputName → value para todos os tipos.
  Future<bool> call({
    required UserEntity user,
    required int courseId,
    required int attemptId,
    required QuestionEntity question,
    required Map<String, String> answers,
    required int baseScore,
  }) async {
    final correct =
        await _repository.submitPage(user, attemptId, question, answers);

    await _repository.submitScore(
      user: user,
      courseId: courseId,
      score: correct ? baseScore : 0,
      correct: correct,
      page: question.page,
    );

    return correct;
  }
}
