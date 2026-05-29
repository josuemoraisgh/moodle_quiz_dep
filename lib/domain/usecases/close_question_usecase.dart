import '../entities/user_entity.dart';
import '../repositories/i_quiz_repository.dart';

/// S: Único propósito – encerrar a questão atual.
class CloseQuestionUseCase {
  final IQuizRepository _repository;

  const CloseQuestionUseCase(this._repository);

  Future<void> call(UserEntity user, int courseId) =>
      _repository.closeQuestion(user, courseId);
}
