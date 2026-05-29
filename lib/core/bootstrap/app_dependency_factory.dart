import 'package:flutter/widgets.dart';

import '../../domain/entities/app_settings_entity.dart';
import '../../domain/entities/local_quiz_entity.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/student_entity.dart';
import '../../domain/repositories/i_quiz_auth_repository.dart';
import '../../domain/repositories/i_quiz_runtime_repository.dart';
import '../../domain/services/quiz_sync_server.dart';
import '../config/quiz_runtime_config.dart';
import '../services/quiz_state_service.dart';
import 'quiz_core.dart';

/// Cria um Core global a partir de factories.
///
/// Use uma unica instancia desta classe por aplicacao/projeto e crie
/// multiplas telas de quiz com [QuizCore.createQuizScreen].
QuizCore buildQuizCoreWithFactories({
  required QuizRuntimeConfig baseConfig,
  required IQuizAuthRepository Function() authRepositoryFactory,
  required IQuizRuntimeRepository Function(QuizStateService stateService)
      quizRepositoryFactory,
  required QuizSyncServer Function() syncServerFactory,
}) {
  return QuizCore(
    baseConfig: baseConfig,
    authRepositoryFactory: authRepositoryFactory,
    quizRepositoryFactory: quizRepositoryFactory,
    syncServerFactory: syncServerFactory,
  );
}

/// Cria um Core global a partir de instancias prontas.
///
/// Para multiplas telas independentes prefira [buildQuizCoreWithFactories],
/// pois reutilizar um mesmo repositorio de runtime pode acoplar estado.
QuizCore buildQuizCoreWithDependencies({
  required QuizRuntimeConfig baseConfig,
  required IQuizAuthRepository authRepository,
  required IQuizRuntimeRepository quizRepository,
  QuizSyncServer syncServer = const HostedQuizSyncServer(serverUrl: ''),
}) {
  return QuizCore(
    baseConfig: baseConfig,
    authRepositoryFactory: () => authRepository,
    quizRepositoryFactory: (_) => quizRepository,
    syncServerFactory: () => syncServer,
  );
}

/// API pública de DI para embed do pacote em apps Flutter.
///
/// Permite passar explicitamente modo, usuários, configurações, senha padrão,
/// repositórios/providers e demais dependências de runtime.
Future<Widget> buildQuizAppWithDependencies({
  required QuizOperationMode mode,
  required IQuizAuthRepository authRepository,
  required IQuizRuntimeRepository quizRepository,
  required List<StudentEntity> users,
  required AppSettingsEntity settings,
  required String defaultPassword,
  QuestionEntity? question,
  int? questionId,
  QuestionNavigationMode navigationMode = QuestionNavigationMode.list,
  List<LocalQuizEntity> quizzes = const [],
  List<QuestionEntity> questions = const [],
  String initialQuizName = 'Quiz',
  String moodleBaseUrl = '',
  String studentUrl = '',
  int courseId = 0,
  int localServerPort = 8080,
  bool startLocalServer = true,
  QuizStateService? stateService,
  QuizSyncServer? syncServer,
}) async {
  final effectiveSettings = settings.copyWith(
    teacherPassword: settings.teacherPassword.isEmpty
        ? defaultPassword
        : settings.teacherPassword,
    studentPassword: settings.studentPassword.isEmpty
        ? defaultPassword
        : settings.studentPassword,
  );

  final baseConfig = QuizRuntimeConfig(
    operationMode: mode,
    navigationMode: navigationMode,
    settings: effectiveSettings,
    students: users,
    quizzes: quizzes,
    questions: questions,
    initialQuizName: initialQuizName,
    moodleBaseUrl: moodleBaseUrl,
    studentUrl: studentUrl,
    courseId: courseId,
    localServerPort: localServerPort,
    startLocalServer: startLocalServer,
    singleQuestionByDependency: question != null,
  );

  final core = buildQuizCoreWithDependencies(
    baseConfig: baseConfig,
    authRepository: authRepository,
    quizRepository: quizRepository,
    syncServer: syncServer ?? const HostedQuizSyncServer(serverUrl: ''),
  );

  return core.createQuizScreen(
    question: question,
    questionId: questionId,
    navigationMode: navigationMode,
    quizzes: quizzes,
    questions: questions,
    initialQuizName: initialQuizName,
    stateService: stateService,
  );
}
