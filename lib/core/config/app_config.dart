/// Configurações globais – sem dependência de Moodle ou internet.
class AppConfig {
  static const String appName = 'Quiz Presencial';
  static const String version = '2.0.0';

  /// Porta do servidor HTTP local do professor (Wi-Fi em sala).
  static int localServerPort = 8080;

  /// Opções de tempo por questão (segundos).
  static List<int> questionTimeOptions = [15, 20, 30, 45, 60, 90, 120];

  /// Tempo padrão por questão.
  static int defaultQuestionTime = 30;

  /// Carrega campos opcionais de assets/config.json (se presente).
  static void loadFromMap(Map<String, dynamic> config) {
    localServerPort =
        int.tryParse(config['server_port']?.toString() ?? '') ??
            localServerPort;
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
  }
}
