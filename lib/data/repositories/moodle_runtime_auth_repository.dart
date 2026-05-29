import '../../core/config/quiz_runtime_config.dart';
import '../../domain/entities/app_settings_entity.dart';
import '../../domain/entities/local_user_entity.dart';
import '../../domain/entities/student_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../../domain/repositories/i_quiz_auth_repository.dart';

class MoodleRuntimeAuthRepository implements IQuizAuthRepository {
  final IAuthRepository _moodleAuth;
  final QuizRuntimeConfig _config;

  MoodleRuntimeAuthRepository({
    required IAuthRepository moodleAuth,
    required QuizRuntimeConfig config,
  })  : _moodleAuth = moodleAuth,
        _config = config;

  @override
  QuizOperationMode get operationMode => QuizOperationMode.online;

  @override
  bool get supportsLocalSetup => false;

  @override
  Future<AppSettingsEntity> getSettings() async => _config.settings;

  @override
  Future<void> saveSettings(AppSettingsEntity settings) async {}

  @override
  Future<List<StudentEntity>> getStudents() async => const [];

  @override
  Future<void> saveStudents(List<String> names) async {}

  @override
  Future<LocalUserEntity?> login({
    required String name,
    required String password,
    String? baseUrl,
  }) async {
    final resolvedBaseUrl = (baseUrl == null || baseUrl.trim().isEmpty)
        ? _config.moodleBaseUrl
        : baseUrl.trim();
    if (resolvedBaseUrl.isEmpty) {
      throw Exception('URL do Moodle nao configurada.');
    }
    final user = await _moodleAuth.login(resolvedBaseUrl, name, password);
    return _toRuntimeUser(user);
  }

  @override
  Future<void> saveSession(LocalUserEntity user) async {
    await _moodleAuth.saveSession(_toMoodleUser(user));
  }

  @override
  Future<LocalUserEntity?> loadSession() async {
    final user = await _moodleAuth.loadSession();
    return user == null ? null : _toRuntimeUser(user);
  }

  @override
  Future<void> clearSession() => _moodleAuth.clearSession();

  LocalUserEntity _toRuntimeUser(UserEntity user) {
    return LocalUserEntity(
      id: user.id,
      name: user.fullname,
      isTeacher: user.isTeacher,
      username: user.username,
      token: user.token,
      baseUrl: user.baseUrl,
      courseId: _config.courseId,
      availableFunctions: user.availableFunctions,
    );
  }

  UserEntity _toMoodleUser(LocalUserEntity user) {
    return UserEntity(
      id: user.id,
      username: user.username.isEmpty ? user.name : user.username,
      fullname: user.name,
      token: user.token,
      baseUrl: user.baseUrl.isEmpty ? _config.moodleBaseUrl : user.baseUrl,
      isTeacher: user.isTeacher,
      availableFunctions: user.availableFunctions,
    );
  }
}
