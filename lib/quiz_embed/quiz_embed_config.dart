/// Configuration for [MoodleQuizEmbed] — identifies the Moodle instance,
/// credentials, and the exact question to display.
class MoodleQuizConfig {
  /// Base URL of the Moodle instance (e.g. "https://moodle.ufu.br").
  final String moodleUrl;

  /// Pre-authenticated Moodle token. Must be paired with [userId].
  final String? token;

  /// Moodle user ID matching [token].
  final int? userId;

  /// Display name for the user (optional, used in UI).
  final String? fullname;

  /// Moodle username (optional, used in UI when [token] is supplied).
  final String? username;

  /// Moodle login username. Used when [token] is not supplied.
  final String? loginUsername;

  /// Moodle login password. Used when [token] is not supplied.
  final String? loginPassword;

  /// ID of the Moodle course (disciplina).
  final int courseId;

  /// ID of the Moodle quiz (questionário).
  final int quizId;

  /// Slot number of the question to display (1-based, as in Moodle).
  final int questionSlot;

  /// URL da API do servidor de estado local do professor
  /// (e.g. "http://192.168.1.100:8080/api").
  ///
  /// Pontuações são enviadas a este servidor e aparecem no ranking ao vivo.
  /// O botão "Resetar Quiz" do app do professor limpa esses dados.
  final String stateServerUrl;

  /// Pontuação para resposta correta. Padrão: 100.
  final int correctScore;

  const MoodleQuizConfig({
    required this.moodleUrl,
    this.token,
    this.userId,
    this.fullname,
    this.username,
    this.loginUsername,
    this.loginPassword,
    required this.courseId,
    required this.quizId,
    required this.questionSlot,
    required this.stateServerUrl,
    this.correctScore = 100,
  }) : assert(
          (token != null && userId != null) ||
              (loginUsername != null && loginPassword != null),
          'Provide either (token + userId) or (loginUsername + loginPassword)',
        );

  bool get hasToken => token != null && userId != null;
}
