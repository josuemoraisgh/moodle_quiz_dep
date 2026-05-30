import '../entities/question_entity.dart';
import '../entities/quiz_state_entity.dart';
import '../entities/score_entity.dart';
import '../entities/student_entity.dart';

abstract class QuizSyncServer {
  String get serverUrl;
  bool get isRunning;

  set onGetState(QuizStateEntity Function()? callback);
  set onGetQuestion(QuestionEntity? Function(int slot)? callback);
  set onGetStudents(List<StudentEntity> Function()? callback);
  set onGetScores(List<ScoreEntity> Function()? callback);
  set onScore(Future<void> Function(Map<String, dynamic> body)? callback);
  set onReset(Future<void> Function()? callback);

  /// Autentica via browser (página web no servidor offline).
  /// Retorna Map com {name, role, studentId} em caso de sucesso, ou null.
  set onLogin(
      Future<Map<String, dynamic>?> Function(String name, String password)?
          callback);

  Future<void> start();
  Future<void> stop();
}

class HostedQuizSyncServer implements QuizSyncServer {
  @override
  final String serverUrl;

  const HostedQuizSyncServer({required this.serverUrl});

  @override
  bool get isRunning => serverUrl.isNotEmpty;

  @override
  set onGetState(QuizStateEntity Function()? callback) {}

  @override
  set onGetQuestion(QuestionEntity? Function(int slot)? callback) {}

  @override
  set onGetStudents(List<StudentEntity> Function()? callback) {}

  @override
  set onGetScores(List<ScoreEntity> Function()? callback) {}

  @override
  set onScore(Future<void> Function(Map<String, dynamic> body)? callback) {}

  @override
  set onReset(Future<void> Function()? callback) {}

  @override
  set onLogin(
      Future<Map<String, dynamic>?> Function(String name, String password)?
          callback) {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
