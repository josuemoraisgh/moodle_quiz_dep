import 'package:flutter/widgets.dart';

import '../../app/moodle_quiz_app.dart';
import '../../data/repositories/in_memory_auth_repository.dart';
import '../../data/repositories/in_memory_quiz_repository.dart';
import '../../domain/services/quiz_sync_server.dart';
import '../config/app_config.dart';
import '../config/quiz_runtime_config.dart';
import 'compositions/offline_runtime_composition.dart';
import 'compositions/online_runtime_composition.dart';
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
  final composition = config.isOnline
      ? await buildOnlineRuntimeComposition(config)
      : await buildOfflineRuntimeComposition(config, stateService);

  return MoodleQuizApp.create(
    config: config,
    authRepository: composition.authRepository,
    quizRepository: composition.quizRepository,
    stateService: stateService,
    syncServer: composition.syncServer,
  );
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
