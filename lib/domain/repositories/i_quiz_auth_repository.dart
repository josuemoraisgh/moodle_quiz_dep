import '../../core/config/quiz_runtime_config.dart';
import '../entities/app_settings_entity.dart';
import '../entities/local_user_entity.dart';
import '../entities/student_entity.dart';

abstract class IQuizAuthRepository {
  QuizOperationMode get operationMode;
  bool get supportsLocalSetup;

  Future<AppSettingsEntity> getSettings();
  Future<void> saveSettings(AppSettingsEntity settings);

  Future<List<StudentEntity>> getStudents();
  Future<void> saveStudents(List<String> names);

  Future<LocalUserEntity?> login({
    required String name,
    required String password,
    String? baseUrl,
  });

  Future<void> saveSession(LocalUserEntity user);
  Future<LocalUserEntity?> loadSession();
  Future<void> clearSession();
}
