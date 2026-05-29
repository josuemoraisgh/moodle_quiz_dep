import 'package:flutter/widgets.dart';

import '../../app/moodle_quiz_app.dart';
import '../../domain/entities/app_settings_entity.dart';
import '../../domain/entities/local_quiz_entity.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/student_entity.dart';
import '../../domain/repositories/i_quiz_auth_repository.dart';
import '../../domain/repositories/i_quiz_runtime_repository.dart';
import '../../domain/services/quiz_sync_server.dart';
import '../config/quiz_runtime_config.dart';
import '../services/quiz_state_service.dart';

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
  final runtimeStateService = stateService ?? QuizStateService();
  final runtimeSyncServer =
      syncServer ?? const HostedQuizSyncServer(serverUrl: '');

  return MoodleQuizApp.createWithDependencies(
    mode: mode,
    users: users,
    settings: settings,
    defaultPassword: defaultPassword,
    authRepository: authRepository,
    quizRepository: quizRepository,
    stateService: runtimeStateService,
    syncServer: runtimeSyncServer,
    question: question,
    questionId: questionId,
    navigationMode: navigationMode,
    quizzes: quizzes,
    questions: questions,
    initialQuizName: initialQuizName,
    moodleBaseUrl: moodleBaseUrl,
    studentUrl: studentUrl,
    courseId: courseId,
    localServerPort: localServerPort,
    startLocalServer: startLocalServer,
  );
}
