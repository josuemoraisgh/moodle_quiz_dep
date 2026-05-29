import '../../../data/datasources/moodle_datasource.dart';
import '../../../data/datasources/moodle_state_datasource.dart';
import '../../../data/repositories/auth_repository_impl.dart' as moodle_auth;
import '../../../data/repositories/moodle_runtime_auth_repository.dart';
import '../../../data/repositories/moodle_runtime_quiz_repository.dart';
import '../../../data/repositories/quiz_repository_impl.dart' as moodle_quiz;
import '../../../domain/services/quiz_sync_server.dart';
import '../../config/quiz_runtime_config.dart';
import 'runtime_composition.dart';

Future<RuntimeComposition> buildOnlineRuntimeComposition(
  QuizRuntimeConfig config,
) async {
  final moodleDatasource = MoodleDatasource();
  final moodleStateDatasource = MoodleStateDatasource(moodleDatasource);

  return RuntimeComposition(
    authRepositoryFactory: () => MoodleRuntimeAuthRepository(
      moodleAuth: moodle_auth.AuthRepositoryImpl(moodleDatasource),
      config: config,
    ),
    quizRepositoryFactory: (_) => MoodleRuntimeQuizRepository(
      moodleQuiz: moodle_quiz.QuizRepositoryImpl(
        moodleStateDatasource,
        moodleDatasource,
      ),
      config: config,
    ),
    syncServerFactory: () => HostedQuizSyncServer(
      serverUrl:
          config.studentUrl.isEmpty ? config.moodleBaseUrl : config.studentUrl,
    ),
  );
}
