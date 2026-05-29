import '../entities/user_entity.dart';

/// I: Interface segregada – apenas métodos de autenticação.
/// D: Módulos de alto nível dependem desta abstração.
abstract class IAuthRepository {
  Future<UserEntity> login(
    String baseUrl,
    String username,
    String password,
  );

  Future<void> saveSession(UserEntity user);
  Future<UserEntity?> loadSession();
  Future<void> clearSession();
}
