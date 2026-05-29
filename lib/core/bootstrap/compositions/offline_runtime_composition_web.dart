import '../../../data/repositories/in_memory_auth_repository.dart';
import '../../../data/repositories/in_memory_quiz_repository.dart';
import '../../../domain/services/quiz_sync_server.dart';
import '../../config/quiz_runtime_config.dart';
import 'runtime_composition.dart';

Future<RuntimeComposition> buildOfflineRuntimeComposition(
  QuizRuntimeConfig config,
) async {
  return RuntimeComposition(
    authRepositoryFactory: () => InMemoryAuthRepository(
      settings: config.settings,
      students: config.students,
    ),
    quizRepositoryFactory: (stateService) => InMemoryQuizRepository(
      stateService: stateService,
      students: config.students,
      quizzes: config.quizzes,
      questions: config.questions,
      initialQuizName: config.initialQuizName,
    ),
    syncServerFactory: () => const HostedQuizSyncServer(serverUrl: ''),
  );
}
