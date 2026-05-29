import '../entities/user_entity.dart';
import '../repositories/i_auth_repository.dart';

/// S: Único propósito – efetuar login no Moodle.
class LoginUseCase {
  final IAuthRepository _repository;

  const LoginUseCase(this._repository);

  Future<UserEntity> call({
    required String baseUrl,
    required String username,
    required String password,
  }) {
    return _repository.login(baseUrl, username, password);
  }
}
