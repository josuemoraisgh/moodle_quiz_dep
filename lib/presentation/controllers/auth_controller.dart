import 'package:flutter/foundation.dart';

import '../../domain/entities/app_settings_entity.dart';
import '../../domain/entities/local_user_entity.dart';
import '../../domain/entities/student_entity.dart';
import '../../domain/repositories/i_quiz_auth_repository.dart';

/// Gerencia autenticação local – sem Moodle ou internet.
class AuthController extends ChangeNotifier {
  final IQuizAuthRepository _repo;

  LocalUserEntity? _user;
  AppSettingsEntity _settings = AppSettingsEntity.defaults();
  List<StudentEntity> _students = [];
  bool _isLoading = false;
  String? _error;

  AuthController(this._repo);

  LocalUserEntity? get user => _user;
  AppSettingsEntity get settings => _settings;
  List<StudentEntity> get students => _students;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;
  bool get needsTeacherPassword => _settings.teacherPassword.trim().isEmpty;
  bool get needsStudentPassword => _settings.studentPassword.trim().isEmpty;
  bool get needsQuizTitle => _settings.quizTitle.trim().isEmpty;
  bool get needsStudents => _students.isEmpty;
  bool get requiresSetup =>
      _repo.supportsLocalSetup &&
      (needsTeacherPassword ||
          needsStudentPassword ||
          needsQuizTitle ||
          needsStudents);
  bool get isOnlineMode => !_repo.supportsLocalSetup;

  /// Inicialização: carrega configurações, lista de alunos e sessão salva.
  Future<void> init() async {
    _settings = await _repo.getSettings();
    _students = await _repo.getStudents();
    _user = await _repo.loadSession();
    notifyListeners();
  }

  Future<void> login({
    required String name,
    required String password,
    String? baseUrl,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      final user = await _repo.login(
        name: name,
        password: password,
        baseUrl: baseUrl,
      );
      if (user == null) {
        _error = 'Usuário ou senha incorretos.';
      } else {
        _user = user;
        await _repo.saveSession(user);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    await _repo.clearSession();
    _user = null;
    notifyListeners();
  }

  Future<void> saveSettings(AppSettingsEntity settings) async {
    await _repo.saveSettings(settings);
    _settings = settings;
    notifyListeners();
  }

  Future<void> saveStudents(List<String> names) async {
    await _repo.saveStudents(names);
    _students = await _repo.getStudents();
    notifyListeners();
  }

  /// Recarrega dados do banco (após setup).
  Future<void> reload() async {
    _settings = await _repo.getSettings();
    _students = await _repo.getStudents();
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
