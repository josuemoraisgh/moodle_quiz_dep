import '../../domain/entities/app_settings_entity.dart';
import '../../domain/entities/local_quiz_entity.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/student_entity.dart';

enum QuizOperationMode { online, offline }

enum QuestionNavigationMode { list, single }

class QuizRuntimeConfig {
  final QuizOperationMode operationMode;
  final QuestionNavigationMode navigationMode;
  final AppSettingsEntity settings;
  final List<StudentEntity> students;
  final List<LocalQuizEntity> quizzes;
  final List<QuestionEntity> questions;
  final String initialQuizName;
  final String moodleBaseUrl;
  final String studentUrl;
  final int courseId;
  final int localServerPort;
  final bool startLocalServer;
  final bool singleQuestionByDependency;
  // true quando o quiz está embedado dentro de um viewer externo (ex: PPTX).
  // Controles duplicados (fullscreen, login) ficam ocultos na tela guest.
  final bool embeddedInPresentation;
  final int slideDisplayIndex; // 1-based; 0 = não definido

  const QuizRuntimeConfig({
    this.operationMode = QuizOperationMode.offline,
    this.navigationMode = QuestionNavigationMode.list,
    this.settings = const AppSettingsEntity(
      teacherPassword: '',
      studentPassword: '',
    ),
    this.students = const [],
    this.quizzes = const [],
    this.questions = const [],
    this.initialQuizName = 'Quiz',
    this.moodleBaseUrl = '',
    this.studentUrl = '',
    this.courseId = 0,
    this.localServerPort = 8080,
    this.startLocalServer = true,
    this.singleQuestionByDependency = false,
    this.embeddedInPresentation = false,
    this.slideDisplayIndex = 0,
  });

  factory QuizRuntimeConfig.offline({
    QuestionNavigationMode navigationMode = QuestionNavigationMode.list,
    AppSettingsEntity? settings,
    List<StudentEntity> students = const [],
    List<LocalQuizEntity> quizzes = const [],
    List<QuestionEntity> questions = const [],
    String initialQuizName = 'Quiz',
    int localServerPort = 8080,
    bool startLocalServer = true,
  }) {
    return QuizRuntimeConfig(
      operationMode: QuizOperationMode.offline,
      navigationMode: navigationMode,
      settings: settings ??
          const AppSettingsEntity(
            teacherPassword: '',
            studentPassword: '',
          ),
      students: students,
      quizzes: quizzes,
      questions: questions,
      initialQuizName: initialQuizName,
      localServerPort: localServerPort,
      startLocalServer: startLocalServer,
    );
  }

  factory QuizRuntimeConfig.online({
    QuestionNavigationMode navigationMode = QuestionNavigationMode.list,
    String moodleBaseUrl = '',
    String studentUrl = '',
    int courseId = 0,
    String quizTitle = 'Quiz Interativo',
  }) {
    return QuizRuntimeConfig(
      operationMode: QuizOperationMode.online,
      navigationMode: navigationMode,
      settings: AppSettingsEntity(
        teacherPassword: '_moodle_',
        studentPassword: '_moodle_',
        quizTitle: quizTitle,
      ),
      moodleBaseUrl: moodleBaseUrl,
      studentUrl: studentUrl,
      courseId: courseId,
      startLocalServer: false,
    );
  }

  factory QuizRuntimeConfig.fromMap(Map<String, dynamic> map) {
    final mode = _parseOperationMode(map['mode']?.toString());
    final navigationMode =
        _parseNavigationMode(map['navigation_mode']?.toString());
    final title = map['quiz_title']?.toString().trim();
    final defaultDuration =
        int.tryParse(map['default_question_time']?.toString() ?? '') ?? 30;
    final durationOptions = _parseDurationOptions(
      map['question_time_options']?.toString() ?? '',
    );
    final settings = AppSettingsEntity(
      teacherPassword: map['teacher_password']?.toString() ?? '',
      studentPassword: map['student_password']?.toString() ??
          map['default_student_password']?.toString() ??
          '',
      quizTitle: title == null || title.isEmpty ? 'Quiz Presencial' : title,
      defaultDurationSeconds: defaultDuration,
      durationOptions: durationOptions,
    );

    return QuizRuntimeConfig(
      operationMode: mode,
      navigationMode: navigationMode,
      settings: mode == QuizOperationMode.online
          ? settings.copyWith(
              teacherPassword: settings.teacherPassword.isEmpty
                  ? '_moodle_'
                  : settings.teacherPassword,
              studentPassword: settings.studentPassword.isEmpty
                  ? '_moodle_'
                  : settings.studentPassword,
            )
          : settings,
      initialQuizName: map['initial_quiz_name']?.toString() ?? 'Quiz',
      moodleBaseUrl: map['moodle_url']?.toString().trim() ?? '',
      studentUrl: map['student_url']?.toString().trim() ?? '',
      courseId: int.tryParse(map['course_id']?.toString() ?? '') ?? 0,
      localServerPort:
          int.tryParse(map['server_port']?.toString() ?? '') ?? 8080,
      startLocalServer: map['start_local_server'] != false,
      singleQuestionByDependency: map['single_question_by_dependency'] == true,
      embeddedInPresentation: map['embedded_in_presentation'] == true,
      slideDisplayIndex:
          int.tryParse(map['slide_display_index']?.toString() ?? '') ?? 0,
    );
  }

  QuizRuntimeConfig copyWith({
    QuizOperationMode? operationMode,
    QuestionNavigationMode? navigationMode,
    AppSettingsEntity? settings,
    List<StudentEntity>? students,
    List<LocalQuizEntity>? quizzes,
    List<QuestionEntity>? questions,
    String? initialQuizName,
    String? moodleBaseUrl,
    String? studentUrl,
    int? courseId,
    int? localServerPort,
    bool? startLocalServer,
    bool? singleQuestionByDependency,
    bool? embeddedInPresentation,
    int? slideDisplayIndex,
  }) {
    return QuizRuntimeConfig(
      operationMode: operationMode ?? this.operationMode,
      navigationMode: navigationMode ?? this.navigationMode,
      settings: settings ?? this.settings,
      students: students ?? this.students,
      quizzes: quizzes ?? this.quizzes,
      questions: questions ?? this.questions,
      initialQuizName: initialQuizName ?? this.initialQuizName,
      moodleBaseUrl: moodleBaseUrl ?? this.moodleBaseUrl,
      studentUrl: studentUrl ?? this.studentUrl,
      courseId: courseId ?? this.courseId,
      localServerPort: localServerPort ?? this.localServerPort,
      startLocalServer: startLocalServer ?? this.startLocalServer,
      singleQuestionByDependency:
          singleQuestionByDependency ?? this.singleQuestionByDependency,
      embeddedInPresentation:
          embeddedInPresentation ?? this.embeddedInPresentation,
      slideDisplayIndex: slideDisplayIndex ?? this.slideDisplayIndex,
    );
  }

  bool get isOnline => operationMode == QuizOperationMode.online;
  bool get isOffline => operationMode == QuizOperationMode.offline;

  static QuizOperationMode _parseOperationMode(String? raw) {
    return switch ((raw ?? '').trim().toLowerCase()) {
      'online' || 'moodle' => QuizOperationMode.online,
      _ => QuizOperationMode.offline,
    };
  }

  static QuestionNavigationMode _parseNavigationMode(String? raw) {
    return switch ((raw ?? '').trim().toLowerCase()) {
      'single' ||
      'question' ||
      'questao_unica' ||
      'questao-unica' =>
        QuestionNavigationMode.single,
      _ => QuestionNavigationMode.list,
    };
  }

  static List<int> _parseDurationOptions(String raw) {
    final parsed = raw
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();
    return parsed.isEmpty ? const [15, 20, 30, 45, 60, 90, 120] : parsed;
  }
}
