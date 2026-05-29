import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/utils/debug_logger.dart';
import 'moodle_state_datasource.dart';

/// Cliente HTTP que implementa IStateDatasource lendo do servidor local do
/// professor. Usado pelo app Flutter Web quando rodando em rede local (S23).
///
/// Alunos chamam esta classe em vez do MoodleStateDatasource, eliminando todo
/// o tráfego de polling (estado + pontuação) para o Moodle via 3G.
class LocalStateClient implements IStateDatasource {
  /// Ex.: "http://192.168.1.100:8080/api"
  final String serverUrl;
  final http.Client _client;

  LocalStateClient({required this.serverUrl, http.Client? client})
      : _client = client ?? http.Client();

  // ── Leitura de estado ───────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>> getState(
      String baseUrl, String token, int courseId) async {
    try {
      final resp = await _client
          .get(Uri.parse('$serverUrl/state'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) {
        throw StateException('Servidor local retornou ${resp.statusCode}');
      }
      return Map<String, dynamic>.from(
          jsonDecode(resp.body) as Map);
    } catch (e) {
      DebugLogger.instance.log('LOCAL_CLIENT', 'getState erro: $e');
      rethrow;
    }
  }

  // ── Pontuação ───────────────────────────────────────────────────────────

  @override
  Future<void> submitScore({
    required String baseUrl,
    required String token,
    required int courseId,
    required String studentId,
    required String studentName,
    required int score,
    required bool correct,
    required int page,
  }) async {
    try {
      await _client
          .post(
            Uri.parse('$serverUrl/score'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'student_id': studentId,
              'student_name': studentName,
              'score': score,
              'correct': correct,
              'page': page,
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      DebugLogger.instance.log('LOCAL_CLIENT', 'submitScore erro: $e');
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getScores(
      String baseUrl, String token, int courseId) async {
    try {
      final resp = await _client
          .get(Uri.parse('$serverUrl/scores'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body) as List;
      return list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      DebugLogger.instance.log('LOCAL_CLIENT', 'getScores erro: $e');
      return [];
    }
  }

  // ── Operações apenas do professor (no-op no lado do aluno) ──────────────

  @override
  Future<void> setSelectedQuiz({
    required String baseUrl,
    required String token,
    required int courseId,
    required int quizId,
    required String quizName,
  }) async {}

  @override
  Future<void> releaseQuestion({
    required String baseUrl,
    required String token,
    required int courseId,
    required int page,
    required int slot,
    required int duration,
    required bool startOnFirstResponse,
    required int totalPages,
    required String quizName,
    required int quizId,
  }) async {}

  @override
  Future<Map<String, dynamic>> startQuestionTimerIfNeeded(
      String baseUrl, String token, int courseId) =>
      getState(baseUrl, token, courseId);

  @override
  Future<void> closeQuestion(
      String baseUrl, String token, int courseId) async {}

  @override
  Future<void> setFinished(
      String baseUrl, String token, int courseId) async {}

  @override
  Future<void> resetQuiz(
      String baseUrl, String token, int courseId) async {}
}
