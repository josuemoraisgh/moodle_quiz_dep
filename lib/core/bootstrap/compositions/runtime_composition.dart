import '../../../domain/repositories/i_quiz_auth_repository.dart';
import '../../../domain/repositories/i_quiz_runtime_repository.dart';
import '../../../domain/services/quiz_sync_server.dart';

class RuntimeComposition {
  final IQuizAuthRepository authRepository;
  final IQuizRuntimeRepository quizRepository;
  final QuizSyncServer syncServer;

  const RuntimeComposition({
    required this.authRepository,
    required this.quizRepository,
    required this.syncServer,
  });
}
