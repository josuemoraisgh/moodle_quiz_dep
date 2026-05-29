import 'package:flutter/widgets.dart';

import '../../data/repositories/in_memory_auth_repository.dart';
import '../../data/repositories/in_memory_quiz_repository.dart';
import '../../domain/services/quiz_sync_server.dart';
import '../config/app_config.dart';
import '../config/quiz_runtime_config.dart';
import 'compositions/offline_runtime_composition.dart';
import 'compositions/online_runtime_composition.dart';
import 'quiz_core.dart';
import 'runtime_config_loader.dart';

Future<Widget> buildDefaultApp() async {
  final config = await loadRuntimeConfig();
  return buildAppFromConfig(config);
}

Future<Widget> buildAppFromConfig(QuizRuntimeConfig config) async {
  final core = await buildCoreFromConfig(config);
  return core.createQuizScreen();
}

Future<QuizCore> buildCoreFromConfig(QuizRuntimeConfig config) async {
  AppConfig.localServerPort = config.localServerPort;
  AppConfig.defaultQuestionTime = config.settings.defaultDurationSeconds;
  AppConfig.questionTimeOptions = config.settings.durationOptions;

  final composition = config.isOnline
      ? await buildOnlineRuntimeComposition(config)
      : await buildOfflineRuntimeComposition(config);

  return QuizCore(
    baseConfig: config,
    authRepositoryFactory: composition.createAuthRepository,
    quizRepositoryFactory: composition.createQuizRepository,
    syncServerFactory: composition.createSyncServer,
  );
}

Future<Widget> buildInMemoryApp(QuizRuntimeConfig config) async {
  final core = QuizCore(
    baseConfig: config,
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
  return core.createQuizScreen();
}
