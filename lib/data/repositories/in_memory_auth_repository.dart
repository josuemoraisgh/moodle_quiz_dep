import '../../core/config/quiz_runtime_config.dart';
import '../../domain/entities/app_settings_entity.dart';
import '../../domain/entities/local_user_entity.dart';
import '../../domain/entities/student_entity.dart';
import '../../domain/repositories/i_quiz_auth_repository.dart';

class InMemoryAuthRepository implements IQuizAuthRepository {
  // Sessão compartilhada entre todas as instâncias (navegação entre slides).
  // Zerada somente em clearSession() — logout explícito.
  static LocalUserEntity? _sharedSession;

  AppSettingsEntity _settings;
  List<StudentEntity> _students;

  InMemoryAuthRepository({
    required AppSettingsEntity settings,
    List<StudentEntity> students = const [],
  })  : _settings = settings,
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
    _sharedSession = user;
  }

  @override
  Future<LocalUserEntity?> loadSession() async => _sharedSession;

  @override
  Future<void> clearSession() async {
    _sharedSession = null;
  }
}
