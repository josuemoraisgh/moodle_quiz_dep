import '../../core/config/quiz_runtime_config.dart';
import '../../domain/entities/app_settings_entity.dart';
import '../../domain/entities/local_user_entity.dart';
import '../../domain/entities/student_entity.dart';
import '../../domain/repositories/i_quiz_auth_repository.dart';
import '../datasources/local_datasource.dart';

class LocalAuthRepositoryImpl implements IQuizAuthRepository {
  final LocalDatasource _ds;
  LocalAuthRepositoryImpl(this._ds);

  @override
  QuizOperationMode get operationMode => QuizOperationMode.offline;

  @override
  bool get supportsLocalSetup => true;

  @override
  Future<AppSettingsEntity> getSettings() => _ds.loadSettings();

  @override
  Future<void> saveSettings(AppSettingsEntity settings) =>
      _ds.saveSettings(settings);

  @override
  Future<List<StudentEntity>> getStudents() => _ds.loadStudents();

  @override
  Future<void> saveStudents(List<String> names) =>
      _ds.replaceStudentList(names);

  @override
  Future<LocalUserEntity?> login({
    required String name,
    required String password,
    String? baseUrl,
  }) async {
    final settings = await _ds.loadSettings();
    final trimmed = name.trim();

    // ── Professor ──────────────────────────────────────────────────────────
    if (trimmed.toLowerCase() == 'professor') {
      if (password == settings.teacherPassword) {
        return const LocalUserEntity(id: 0, name: 'Professor', isTeacher: true);
      }
      return null;
    }

    // ── Aluno ──────────────────────────────────────────────────────────────
    if (password != settings.studentPassword) return null;
    final student = await _ds.getStudentByName(trimmed);
    if (student == null) return null;
    return LocalUserEntity(
        id: student.id, name: student.name, isTeacher: false);
  }

  @override
  Future<void> saveSession(LocalUserEntity user) => _ds.saveSession(user);

  @override
  Future<LocalUserEntity?> loadSession() => _ds.loadSession();

  @override
  Future<void> clearSession() => _ds.clearSession();
}
