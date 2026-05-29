import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/quiz_state_entity.dart';
import '../../domain/entities/score_entity.dart';
import '../../domain/entities/student_entity.dart';

/// Cliente HTTP que o aluno usa para comunicar com o servidor do professor.
class OfflineLocalClient {
  String serverUrl; // ex: "http://192.168.0.10:8080"

  OfflineLocalClient({required this.serverUrl});

  // ── Estado do quiz ────────────────────────────────────────────────────────

  Future<QuizStateEntity> getState() async {
    final res = await http
        .get(Uri.parse('$serverUrl/api/state'))
        .timeout(const Duration(seconds: 5));
    _checkStatus(res);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return _parseState(m);
  }

  // ── Lista de alunos ───────────────────────────────────────────────────────

  Future<List<StudentEntity>> getStudents() async {
    final res = await http
        .get(Uri.parse('$serverUrl/api/students'))
        .timeout(const Duration(seconds: 5));
    _checkStatus(res);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final names = (m['students'] as List<dynamic>? ?? [])
        .map((n) => n as String)
        .toList();
    return names
        .asMap()
        .entries
        .map((e) => StudentEntity(id: e.key + 1, name: e.value))
        .toList();
  }

  // ── Dados de questão ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getQuestion(int slot) async {
    final res = await http
        .get(Uri.parse('$serverUrl/api/question/$slot'))
        .timeout(const Duration(seconds: 5));
    _checkStatus(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Pontuações ────────────────────────────────────────────────────────────

  Future<List<ScoreEntity>> getScores() async {
    final res = await http
        .get(Uri.parse('$serverUrl/api/scores'))
        .timeout(const Duration(seconds: 5));
    _checkStatus(res);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (m['scores'] as List<dynamic>? ?? []);
    return list.asMap().entries.map((e) {
      final r = e.value as Map<String, dynamic>;
      return ScoreEntity(
        studentId: r['studentId'] as String? ?? '',
        studentName: r['studentName'] as String? ?? '',
        score: (r['score'] as num?)?.toInt() ?? 0,
        correctCount: (r['correctCount'] as num?)?.toInt() ?? 0,
        totalAnswered: (r['totalAnswered'] as num?)?.toInt() ?? 0,
        rank: (r['rank'] as num?)?.toInt() ?? (e.key + 1),
      );
    }).toList();
  }

  // ── Enviar score ──────────────────────────────────────────────────────────

  Future<void> submitScore({
    required String studentId,
    required String studentName,
    required int questionSlot,
    required String roundId,
    required Map<String, String> answers,
    required bool isCorrect,
    required int score,
  }) async {
    final res = await http
        .post(
          Uri.parse('$serverUrl/api/score'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'studentId': studentId,
            'studentName': studentName,
            'questionSlot': questionSlot,
            'roundId': roundId,
            'answers': answers,
            'isCorrect': isCorrect,
            'score': score,
          }),
        )
        .timeout(const Duration(seconds: 5));
    _checkStatus(res);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _checkStatus(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Erro HTTP ${res.statusCode}: ${res.body}');
    }
  }

  QuizStateEntity _parseState(Map<String, dynamic> m) {
    final startedMs = m['startedAt'] as int?;
    final endsMs = m['endsAt'] as int?;
    return QuizStateEntity(
      status: _parseStatus(m['status'] as String? ?? 'waiting'),
      currentSlot: (m['currentSlot'] as num?)?.toInt() ?? 0,
      currentPage: (m['currentPage'] as num?)?.toInt() ?? -1,
      totalPages: (m['totalPages'] as num?)?.toInt() ?? 0,
      quizId: (m['quizId'] as num?)?.toInt() ?? 0,
      courseId: 0,
      quizTitle: m['quizTitle'] as String? ?? '',
      roundId: m['roundId'] as String? ?? '',
      durationSeconds: (m['durationSeconds'] as num?)?.toInt() ?? 0,
      startOnFirstResponse: m['startOnFirstResponse'] as bool? ?? false,
      timerStarted: m['timerStarted'] as bool? ?? false,
      startedAt: startedMs != null
          ? DateTime.fromMillisecondsSinceEpoch(startedMs)
          : null,
      endsAt:
          endsMs != null ? DateTime.fromMillisecondsSinceEpoch(endsMs) : null,
    );
  }

  QuizStatus _parseStatus(String s) => switch (s) {
        'active' => QuizStatus.active,
        'closed' => QuizStatus.closed,
        'finished' => QuizStatus.finished,
        _ => QuizStatus.waiting,
      };
}
