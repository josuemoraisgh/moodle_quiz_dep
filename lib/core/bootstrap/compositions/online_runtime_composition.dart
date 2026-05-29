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
  final moodleAuthRepository = moodle_auth.AuthRepositoryImpl(moodleDatasource);
  final moodleQuizRepository = moodle_quiz.QuizRepositoryImpl(
    moodleStateDatasource,
    moodleDatasource,
  );

  return RuntimeComposition(
    authRepository: MoodleRuntimeAuthRepository(
      moodleAuth: moodleAuthRepository,
      config: config,
    ),
    quizRepository: MoodleRuntimeQuizRepository(
      moodleQuiz: moodleQuizRepository,
      config: config,
    ),
    syncServer: HostedQuizSyncServer(
      serverUrl:
          config.studentUrl.isEmpty ? config.moodleBaseUrl : config.studentUrl,
    ),
  );
}
