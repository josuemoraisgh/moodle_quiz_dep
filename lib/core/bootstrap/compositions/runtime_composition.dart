import '../../../domain/repositories/i_quiz_auth_repository.dart';
import '../../../domain/repositories/i_quiz_runtime_repository.dart';
import '../../../domain/services/quiz_sync_server.dart';
import '../../services/quiz_state_service.dart';

class RuntimeComposition {
  final IQuizAuthRepository Function() authRepositoryFactory;
  final IQuizRuntimeRepository Function(QuizStateService stateService)
      quizRepositoryFactory;
  final QuizSyncServer Function() syncServerFactory;

  const RuntimeComposition({
    required this.authRepositoryFactory,
    required this.quizRepositoryFactory,
    required this.syncServerFactory,
  });

  IQuizAuthRepository createAuthRepository() => authRepositoryFactory();

  IQuizRuntimeRepository createQuizRepository(QuizStateService stateService) {
    return quizRepositoryFactory(stateService);
  }

  QuizSyncServer createSyncServer() => syncServerFactory();
}
