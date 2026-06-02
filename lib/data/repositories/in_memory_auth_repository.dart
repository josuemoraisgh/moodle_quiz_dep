import '../../core/config/quiz_runtime_config.dart';
import '../../core/utils/quiz_nav_notifier.dart';
import '../../domain/entities/app_settings_entity.dart';
import '../../domain/entities/local_user_entity.dart';
import '../../domain/entities/student_entity.dart';
import '../../domain/repositories/i_quiz_auth_repository.dart';

/// Garante que senhas nunca fiquem vazias — usa os defaults de fábrica.
AppSettingsEntity _withDefaults(AppSettingsEntity s) => s.copyWith(
      teacherPassword: s.teacherPassword.trim().isEmpty
          ? AppSettingsEntity.defaultTeacherPassword
          : null,
      studentPassword: s.studentPassword.trim().isEmpty
          ? AppSettingsEntity.defaultStudentPassword
          : null,
    );

class InMemoryAuthRepository implements IQuizAuthRepository {
  // A sessão é armazenada no notifier global, compartilhado entre todas as
  // instâncias. Assim o login feito no overlay de auth vale para todos os
  // slides de quiz sem exigir re-autenticação.

  AppSettingsEntity _settings;
  List<StudentEntity> _students;

  InMemoryAuthRepository({
    required AppSettingsEntity settings,
    List<StudentEntity> students = const [],
  })  : _settings = _withDefaults(settings),
        _students = List.of(students);

  @override
  QuizOperationMode get operationMode => QuizOperationMode.offline;

  @override
  bool get supportsLocalSetup => true;

  @override
  Future<AppSettingsEntity> getSettings() async => _settings;

  @override
  Future<void> saveSettings(AppSettingsEntity settings) async {
    _settings = settings;
  }

  @override
  Future<List<StudentEntity>> getStudents() async =>
      List.unmodifiable(_students);

  @override
  Future<void> saveStudents(List<String> names) async {
    _students = [
      for (final entry in names.where((n) => n.trim().isNotEmpty).indexed)
        StudentEntity(id: entry.$1 + 1, name: entry.$2.trim()),
    ];
  }

  @override
  Future<LocalUserEntity?> login({
    required String name,
    required String password,
    String? baseUrl,
  }) async {
    final trimmed = name.trim();
    if (trimmed.toLowerCase() == 'professor') {
      return password == _settings.teacherPassword
          ? const LocalUserEntity(id: 0, name: 'Professor', isTeacher: true)
          : null;
    }
    if (password != _settings.studentPassword) return null;
    for (final student in _students) {
      if (student.name == trimmed) {
        return LocalUserEntity(
          id: student.id,
          name: student.name,
          isTeacher: false,
        );
      }
    }
    return null;
  }

  @override
  Future<void> saveSession(LocalUserEntity user) async {
    quizGlobalUserNotifier.value = user;
  }

  @override
  Future<LocalUserEntity?> loadSession() async =>
      quizGlobalUserNotifier.value;

  @override
  Future<void> clearSession() async {
    quizGlobalUserNotifier.value = null;
  }
}
