import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../app/moodle_quiz_app.dart';
import '../../domain/entities/local_quiz_entity.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/repositories/i_quiz_auth_repository.dart';
import '../../domain/repositories/i_quiz_runtime_repository.dart';
import '../../domain/services/quiz_sync_server.dart';
import '../config/quiz_runtime_config.dart';
import '../services/quiz_state_service.dart';
import '../utils/question_serializer.dart';
import '../utils/moodle_xml_quiz_parser.dart';

/// Core global da aplicacao.
///
/// Esta classe concentra apenas infraestrutura e factories compartilhadas.
/// O estado de execucao de uma tela de quiz (questao ativa, estado atual e
/// ranking em memoria) fica isolado em [QuizStateService] por tela.
class QuizCore {
  final QuizRuntimeConfig baseConfig;
  final IQuizAuthRepository Function() _authRepositoryFactory;
  final IQuizRuntimeRepository Function(QuizStateService stateService)
      _quizRepositoryFactory;
  final QuizSyncServer Function() _syncServerFactory;

  const QuizCore({
    required this.baseConfig,
    required IQuizAuthRepository Function() authRepositoryFactory,
    required IQuizRuntimeRepository Function(QuizStateService stateService)
        quizRepositoryFactory,
    required QuizSyncServer Function() syncServerFactory,
  })  : _authRepositoryFactory = authRepositoryFactory,
        _quizRepositoryFactory = quizRepositoryFactory,
        _syncServerFactory = syncServerFactory;

  IQuizAuthRepository createAuthRepository() => _authRepositoryFactory();

  IQuizRuntimeRepository createQuizRepository(QuizStateService stateService) {
    return _quizRepositoryFactory(stateService);
  }

  QuizSyncServer createSyncServer() => _syncServerFactory();

  /// Cria uma nova tela de quiz com contexto de execucao independente.
  ///
  /// Cada chamada gera uma nova instancia de [QuizStateService] e de
  /// [IQuizRuntimeRepository], permitindo N telas simultaneas sem
  /// compartilhamento acidental de estado de tela.
  Future<Widget> createQuizScreen({
    QuestionEntity? question,
    Map<String, dynamic>? questionMap,
    String? questionXml,
    int questionXmlIndex = 0,
    int? questionId,
    QuestionNavigationMode? navigationMode,
    List<LocalQuizEntity>? quizzes,
    List<QuestionEntity>? questions,
    String? initialQuizName,
    QuizStateService? stateService,
    IQuizAuthRepository? authRepository,
    IQuizRuntimeRepository? quizRepository,
    QuizSyncServer? syncServer,
    // Overrides por chamada — necessários quando o core é reutilizado entre slides
    int? slideDisplayIndex,
    bool? embeddedInPresentation,
  }) {
    final runtimeStateService = stateService ?? QuizStateService();
    final runtimeAuthRepository = authRepository ?? createAuthRepository();
    final runtimeQuizRepository =
        quizRepository ?? createQuizRepository(runtimeStateService);
    final runtimeSyncServer = syncServer ?? createSyncServer();
    final runtimeQuestion = _resolveRuntimeQuestion(
      question: question,
      questionMap: questionMap,
      questionXml: questionXml,
      questionXmlIndex: questionXmlIndex,
    );

    return MoodleQuizApp.createWithDependencies(
      mode: baseConfig.operationMode,
      users: baseConfig.students,
      settings: baseConfig.settings,
      defaultPassword: baseConfig.settings.teacherPassword,
      authRepository: runtimeAuthRepository,
      quizRepository: runtimeQuizRepository,
      stateService: runtimeStateService,
      syncServer: runtimeSyncServer,
      question: runtimeQuestion,
      questionId: questionId,
      navigationMode: navigationMode ?? baseConfig.navigationMode,
      quizzes: quizzes ?? baseConfig.quizzes,
      questions: questions ?? baseConfig.questions,
      initialQuizName: initialQuizName ?? baseConfig.initialQuizName,
      moodleBaseUrl: baseConfig.moodleBaseUrl,
      studentUrl: baseConfig.studentUrl,
      courseId: baseConfig.courseId,
      localServerPort: baseConfig.localServerPort,
      startLocalServer: baseConfig.startLocalServer,
      slideDisplayIndex: slideDisplayIndex ?? baseConfig.slideDisplayIndex,
      embeddedInPresentation:
          embeddedInPresentation ?? baseConfig.embeddedInPresentation,
    );
  }

  QuestionEntity? _resolveRuntimeQuestion({
    required QuestionEntity? question,
    required Map<String, dynamic>? questionMap,
    required String? questionXml,
    required int questionXmlIndex,
  }) {
    if (questionMap != null && questionMap.isNotEmpty) {
      // questionMap vem de QuestionSerializer.toJson → já é Map<String,dynamic>.
      return QuestionSerializer.fromJson(questionMap);
    }

    final xml = questionXml?.trim() ?? '';
    if (xml.isEmpty) return question;

    final parsed = MoodleXmlQuizParser.parseQuestions(
      Uint8List.fromList(utf8.encode(xml)),
      token: '',
      baseUrl: baseConfig.moodleBaseUrl,
    );

    if (parsed.isEmpty) {
      throw ArgumentError('O XML informado nao possui questoes validas.');
    }
    if (questionXmlIndex < 0 || questionXmlIndex >= parsed.length) {
      throw RangeError.range(
        questionXmlIndex,
        0,
        parsed.length - 1,
        'questionXmlIndex',
        'Indice de questao fora do intervalo do XML.',
      );
    }

    return parsed[questionXmlIndex];
  }

}
