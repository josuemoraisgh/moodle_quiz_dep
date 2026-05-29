import 'package:flutter/widgets.dart';

import '../../app/moodle_quiz_app.dart';
import '../../data/datasources/local_datasource.dart';
import '../../data/datasources/moodle_datasource.dart';
import '../../data/datasources/moodle_state_datasource.dart';
import '../../data/datasources/offline_local_server.dart';
import '../../data/repositories/auth_repository_impl.dart' as moodle_auth;
import '../../data/repositories/in_memory_auth_repository.dart';
import '../../data/repositories/in_memory_quiz_repository.dart';
import '../../data/repositories/local_auth_repository_impl.dart';
import '../../data/repositories/local_quiz_repository_impl.dart';
import '../../data/repositories/moodle_runtime_auth_repository.dart';
import '../../data/repositories/moodle_runtime_quiz_repository.dart';
import '../../data/repositories/quiz_repository_impl.dart' as moodle_quiz;
import '../../domain/repositories/i_quiz_auth_repository.dart';
import '../../domain/repositories/i_quiz_runtime_repository.dart';
import '../../domain/services/quiz_sync_server.dart';
import '../config/app_config.dart';
import '../config/quiz_runtime_config.dart';
import '../database/app_database.dart';
import '../services/quiz_state_service.dart';
import 'runtime_config_loader.dart';

Future<Widget> buildDefaultApp() async {
  final config = await loadRuntimeConfig();
  return buildAppFromConfig(config);
}

Future<Widget> buildAppFromConfig(QuizRuntimeConfig config) async {
  AppConfig.localServerPort = config.localServerPort;
  AppConfig.defaultQuestionTime = config.settings.defaultDurationSeconds;
  AppConfig.questionTimeOptions = config.settings.durationOptions;

  final stateService = QuizStateService();
  late final IQuizAuthRepository authRepository;
  late final IQuizRuntimeRepository quizRepository;
  late final QuizSyncServer syncServer;

  if (config.isOnline) {
    final moodleDatasource = MoodleDatasource();
    final moodleStateDatasource = MoodleStateDatasource(moodleDatasource);
    final moodleAuthRepository =
        moodle_auth.AuthRepositoryImpl(moodleDatasource);
    final moodleQuizRepository = moodle_quiz.QuizRepositoryImpl(
      moodleStateDatasource,
      moodleDatasource,
    );
    authRepository = MoodleRuntimeAuthRepository(
      moodleAuth: moodleAuthRepository,
      config: config,
    );
    quizRepository = MoodleRuntimeQuizRepository(
      moodleQuiz: moodleQuizRepository,
      config: config,
    );
    syncServer = HostedQuizSyncServer(
      serverUrl:
          config.studentUrl.isEmpty ? config.moodleBaseUrl : config.studentUrl,
    );
  } else {
    final db = AppDatabase.instance;
    final datasource = LocalDatasource(db);
    await _seedLocalData(config, datasource);
    authRepository = LocalAuthRepositoryImpl(datasource);
    quizRepository = LocalQuizRepository(datasource, stateService);
    if (config.startLocalServer) {
      final server = OfflineLocalServer(port: config.localServerPort);
      await server.start();
      syncServer = server;
    } else {
      syncServer = const HostedQuizSyncServer(serverUrl: '');
    }
  }

  return MoodleQuizApp.create(
    config: config,
    authRepository: authRepository,
    quizRepository: quizRepository,
    stateService: stateService,
    syncServer: syncServer,
  );
}

Future<void> _seedLocalData(
  QuizRuntimeConfig config,
  LocalDatasource datasource,
) async {
  if (!config.settings.isFirstRun) {
    final current = await datasource.loadSettings();
    if (current.isFirstRun) await datasource.saveSettings(config.settings);
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

Future<Widget> buildInMemoryApp(QuizRuntimeConfig config) async {
  final stateService = QuizStateService();
  return MoodleQuizApp.create(
    config: config,
    authRepository: InMemoryAuthRepository(
      settings: config.settings,
      students: config.students,
    ),
    quizRepository: InMemoryQuizRepository(
      stateService: stateService,
      students: config.students,
      quizzes: config.quizzes,
      questions: config.questions,
      initialQuizName: config.initialQuizName,
    ),
    stateService: stateService,
    syncServer: const HostedQuizSyncServer(serverUrl: ''),
  );
}
