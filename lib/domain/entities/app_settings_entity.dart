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

  /// Primeira execução: nenhuma senha configurada ainda.
  bool get isFirstRun =>
      teacherPassword.trim().isEmpty && studentPassword.trim().isEmpty;

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
        teacherPassword: '',
        studentPassword: '',
      );
}
