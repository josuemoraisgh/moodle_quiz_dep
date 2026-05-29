/// Configurações globais carregadas de assets/config.json.
/// S: Responsabilidade única – apenas armazena config.
class AppConfig {
  static const String appName = 'MoodleQuiz Live';
  static const String version = '1.0.0';

  // ── Infraestrutura ──────────────────────────────────────────────────────
  static String studentUrl = 'https://lasec-ufu.github.io/MoodleQuiz/';

  // ── Configurações do quiz (vindas do config.json) ───────────────────────
  static String moodleBaseUrl = '';
  static String quizTitle = 'Quiz Interativo';
  static int defaultQuestionTime = 30;
  static List<int> questionTimeOptions = [15, 20, 30, 45, 60, 90, 120];

  // ── Modo local (S23 com Ethernet + 3G) ──────────────────────────────────
  // Quando true: professor sobe servidor HTTP local; alunos usam esse servidor
  // para estado/pontuações em vez de chamar o Moodle a cada segundo.
  static bool localMode = false;
  static int localServerPort = 8080;

  /// Carrega todos os campos do mapa (config.json).
  static void loadFromMap(Map<String, dynamic> config) {
    studentUrl = (config['student_url'] as String?)?.trim() ?? studentUrl;
    moodleBaseUrl = (config['moodle_url'] as String?)?.trim() ?? moodleBaseUrl;
    quizTitle = (config['quiz_title'] as String?) ?? quizTitle;
    defaultQuestionTime =
        int.tryParse(config['default_question_time']?.toString() ?? '') ??
            defaultQuestionTime;

    final raw = config['question_time_options']?.toString() ?? '';
    if (raw.isNotEmpty) {
      final parsed = raw
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();
      if (parsed.isNotEmpty) questionTimeOptions = parsed;
    }

    localMode = config['local_mode'] == true;
    localServerPort =
        int.tryParse(config['local_server_port']?.toString() ?? '') ??
            localServerPort;
  }

  static bool get isConfigured => true;
  static bool get isMoodleConfigured => moodleBaseUrl.isNotEmpty;
}
