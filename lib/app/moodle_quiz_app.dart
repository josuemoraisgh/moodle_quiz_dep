import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
import '../core/config/quiz_runtime_config.dart';
import '../core/router/app_router.dart';
import '../core/services/quiz_state_service.dart';
import '../core/theme/app_theme.dart';
import '../domain/entities/app_settings_entity.dart';
import '../domain/entities/local_quiz_entity.dart';
import '../domain/entities/question_entity.dart';
import '../domain/entities/student_entity.dart';
import '../domain/repositories/i_quiz_auth_repository.dart';
import '../domain/repositories/i_quiz_runtime_repository.dart';
import '../domain/services/quiz_sync_server.dart';
import '../presentation/controllers/auth_controller.dart';
import '../presentation/controllers/professor_controller.dart';
import '../presentation/controllers/student_controller.dart';

class MoodleQuizApp extends StatelessWidget {
  final QuizRuntimeConfig config;
  final AuthController authController;
  final IQuizRuntimeRepository quizRepository;
  final QuizStateService stateService;
  final QuizSyncServer syncServer;

  const MoodleQuizApp({
    super.key,
    required this.config,
    required this.authController,
    required this.quizRepository,
    required this.stateService,
    required this.syncServer,
  });

  static Future<MoodleQuizApp> create({
    required QuizRuntimeConfig config,
    required IQuizAuthRepository authRepository,
    required IQuizRuntimeRepository quizRepository,
    required QuizStateService stateService,
    required QuizSyncServer syncServer,
  }) async {
    final authController = AuthController(authRepository);
    await authController.init();
    return MoodleQuizApp(
      config: config,
      authController: authController,
      quizRepository: quizRepository,
      stateService: stateService,
      syncServer: syncServer,
    );
  }

  /// Entrada explícita para embed: recebe modo, usuários, settings,
  /// senha padrão e repositórios/providers já resolvidos por DI externa.
  static Future<MoodleQuizApp> createWithDependencies({
    required QuizOperationMode mode,
    required List<StudentEntity> users,
    required AppSettingsEntity settings,
    required String defaultPassword,
    required IQuizAuthRepository authRepository,
    required IQuizRuntimeRepository quizRepository,
    required QuizStateService stateService,
    required QuizSyncServer syncServer,
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
  }) {
    final runtimeQuestion = question == null
        ? null
        : _withRuntimeQuestionId(
            question,
            forcedId: questionId,
          );
    final runtimeQuestions =
        runtimeQuestion == null ? questions : <QuestionEntity>[runtimeQuestion];
    final runtimeNavigation = runtimeQuestion == null
        ? navigationMode
        : QuestionNavigationMode.single;

    final effectiveSettings = settings.copyWith(
      teacherPassword: settings.teacherPassword.isEmpty
          ? defaultPassword
          : settings.teacherPassword,
      studentPassword: settings.studentPassword.isEmpty
          ? defaultPassword
          : settings.studentPassword,
    );

    final config = QuizRuntimeConfig(
      operationMode: mode,
      navigationMode: runtimeNavigation,
      settings: effectiveSettings,
      students: users,
      quizzes: quizzes,
      questions: runtimeQuestions,
      initialQuizName: initialQuizName,
      moodleBaseUrl: moodleBaseUrl,
      studentUrl: studentUrl,
      courseId: courseId,
      localServerPort: localServerPort,
      startLocalServer: startLocalServer,
      singleQuestionByDependency: runtimeQuestion != null,
    );

    return create(
      config: config,
      authRepository: authRepository,
      quizRepository: quizRepository,
      stateService: stateService,
      syncServer: syncServer,
    );
  }

  static QuestionEntity _withRuntimeQuestionId(
    QuestionEntity question, {
    int? forcedId,
  }) {
    final runtimeId =
        forcedId ?? DateTime.now().microsecondsSinceEpoch.remainder(2147483647);
    final safeId = runtimeId <= 0 ? 1 : runtimeId;

    return QuestionEntity(
      slot: safeId,
      page: 0,
      text: question.text,
      htmlText: question.htmlText,
      displayHtml: question.displayHtml,
      choices: question.choices,
      imageUrls: question.imageUrls,
      inputBaseName: question.inputBaseName,
      seqCheck: question.seqCheck,
      type: question.type,
      generalFeedback: question.generalFeedback,
      rightAnswerHtml: question.rightAnswerHtml,
      answerControls: question.answerControls,
      answerInputName: question.answerInputName,
      matchData: question.matchData,
      gapInputData: question.gapInputData,
      ddMarkerData: question.ddMarkerData,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<QuizRuntimeConfig>.value(value: config),
        ChangeNotifierProvider.value(value: stateService),
        ChangeNotifierProvider.value(value: authController),
        ChangeNotifierProvider(
          create: (_) => ProfessorController(
            quizRepo: quizRepository,
            stateService: stateService,
            server: syncServer,
            navigationMode: config.navigationMode,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => StudentController(
            quizRepo: quizRepository,
            stateService: stateService,
          ),
        ),
      ],
      child: const _MaterialShell(),
    );
  }
}

class _MaterialShell extends StatelessWidget {
  const _MaterialShell();

  @override
  Widget build(BuildContext context) {
    final router = AppRouter.build(context);
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
