import 'package:flutter/foundation.dart';

import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../../domain/usecases/login_usecase.dart';

/// Gerencia estado de autenticação – S: apenas auth.
class AuthController extends ChangeNotifier {
  final LoginUseCase _loginUseCase;
  final IAuthRepository _repository;

  UserEntity? _user;
  bool _isLoading = false;
  String? _error;

  AuthController({
    required LoginUseCase loginUseCase,
    required IAuthRepository repository,
  })  : _loginUseCase = loginUseCase,
        _repository = repository;

  UserEntity? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;

  /// Tenta restaurar sessão salva.
  Future<void> loadSavedSession() async {
    _user = await _repository.loadSession();
    notifyListeners();
  }

  Future<void> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      _user = await _loginUseCase(
        baseUrl: baseUrl,
        username: username,
        password: password,
      );
      await _repository.saveSession(_user!);
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    await _repository.clearSession();
    _user = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }
}
