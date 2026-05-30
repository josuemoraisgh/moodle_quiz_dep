/// Configurações da aplicação persistidas no banco local.
class AppSettingsEntity {
  final String teacherPassword;
  final String studentPassword;
  final String quizTitle;
  final int defaultDurationSeconds;
  final List<int> durationOptions;

  const AppSettingsEntity({
    required this.teacherPassword,
    required this.studentPassword,
    this.quizTitle = 'Quiz Presencial',
    this.defaultDurationSeconds = 30,
    this.durationOptions = const [15, 20, 30, 45, 60, 90, 120],
  });

  /// Senhas padrão de fábrica.
  static const String defaultTeacherPassword = 'Josue123456';
  static const String defaultStudentPassword = '123456';

  /// Primeira execução: senhas ainda não foram personalizadas.
  bool get isFirstRun =>
      teacherPassword == defaultTeacherPassword &&
      studentPassword == defaultStudentPassword;

  AppSettingsEntity copyWith({
    String? teacherPassword,
    String? studentPassword,
    String? quizTitle,
    int? defaultDurationSeconds,
    List<int>? durationOptions,
  }) {
    return AppSettingsEntity(
      teacherPassword: teacherPassword ?? this.teacherPassword,
      studentPassword: studentPassword ?? this.studentPassword,
      quizTitle: quizTitle ?? this.quizTitle,
      defaultDurationSeconds:
          defaultDurationSeconds ?? this.defaultDurationSeconds,
      durationOptions: durationOptions ?? this.durationOptions,
    );
  }

  static AppSettingsEntity defaults() => const AppSettingsEntity(
        teacherPassword: defaultTeacherPassword,
        studentPassword: defaultStudentPassword,
      );
}
