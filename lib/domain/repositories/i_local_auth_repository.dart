import '../entities/app_settings_entity.dart';
import '../entities/local_user_entity.dart';
import '../entities/student_entity.dart';

abstract class ILocalAuthRepository {
  Future<AppSettingsEntity> getSettings();
  Future<void> saveSettings(AppSettingsEntity settings);

  Future<List<StudentEntity>> getStudents();
  Future<void> saveStudents(List<String> names);

  /// Autentica e retorna o usuário ou null se credenciais inválidas.
  Future<LocalUserEntity?> login({
    required String name,
    required String password,
  });

  Future<void> saveSession(LocalUserEntity user);
  Future<LocalUserEntity?> loadSession();
  Future<void> clearSession();
}
