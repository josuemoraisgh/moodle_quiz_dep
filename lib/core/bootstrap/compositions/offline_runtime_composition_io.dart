import '../../../data/datasources/local_datasource.dart';
import '../../../data/datasources/offline_local_server.dart';
import '../../../data/repositories/local_auth_repository_impl.dart';
import '../../../data/repositories/local_quiz_repository_impl.dart';
import '../../../domain/services/quiz_sync_server.dart';
import '../../config/quiz_runtime_config.dart';
import '../../database/app_database.dart';
import '../../services/quiz_state_service.dart';
import 'runtime_composition.dart';

Future<RuntimeComposition> buildOfflineRuntimeComposition(
  QuizRuntimeConfig config,
  QuizStateService stateService,
) async {
  final db = AppDatabase.instance;
  final datasource = LocalDatasource(db);
  await seedOfflineConfigData(config, datasource);

  QuizSyncServer syncServer;
  if (config.startLocalServer) {
    final server = OfflineLocalServer(port: config.localServerPort);
    await server.start();
    syncServer = server;
  } else {
    syncServer = const HostedQuizSyncServer(serverUrl: '');
  }

  return RuntimeComposition(
    authRepository: LocalAuthRepositoryImpl(datasource),
    quizRepository: LocalQuizRepository(datasource, stateService),
    syncServer: syncServer,
  );
}

Future<void> seedOfflineConfigData(
  QuizRuntimeConfig config,
  LocalDatasource datasource,
) async {
  if (!config.settings.isFirstRun) {
    final current = await datasource.loadSettings();
    if (current.isFirstRun) {
      await datasource.saveSettings(config.settings);
    }
  }

  if (config.students.isNotEmpty) {
    final current = await datasource.loadStudents();
    if (current.isEmpty) {
      await datasource.replaceStudentList(
        config.students.map((student) => student.name).toList(),
      );
    }
  }

  if (config.quizzes.isNotEmpty || config.questions.isNotEmpty) {
    final current = await datasource.loadQuizzes();
    if (current.isEmpty) {
      for (final quiz in config.quizzes) {
        await datasource.saveQuiz(quiz.name, quiz.questions);
      }
      if (config.questions.isNotEmpty) {
        await datasource.saveQuiz(config.initialQuizName, config.questions);
      }
    }
  }
}
