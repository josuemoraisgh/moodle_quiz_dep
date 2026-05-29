import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../core/utils/debug_logger.dart';
import 'moodle_state_datasource.dart';

/// Implementação local de IStateDatasource: guarda estado em memória e expõe
/// via HTTP na rede local. Roda no Android do professor (S23 com Ethernet).
///
/// Elimina o polling de 30 alunos × 1 req/s ao Moodle — todo o tráfego de
/// estado e pontuação fica dentro da LAN, sem consumir 3G.
class LocalStateDatasource implements IStateDatasource {
  final int port;

  static const Map<String, dynamic> _emptyState = {
    'state': 'waiting',
    'current_page': -1,
    'current_slot': 0,
    'total_pages': 0,
    'quiz_id': 0,
    'course_id': 0,
    'quiz_name': '',
    'round_id': '',
    'duration_seconds': 0,
    'start_on_first_response': false,
    'timer_started': false,
    'started_at': '',
    'ends_at': '',
  };

  Map<String, dynamic> _state = Map.from(_emptyState);

  // studentId → dados de pontuação
  final Map<String, Map<String, dynamic>> _scores = {};

  HttpServer? _server;

  LocalStateDatasource({this.port = 8080});

  bool get isRunning => _server != null;

  // ── Ciclo de vida do servidor ───────────────────────────────────────────

  Future<void> startServer() async {
    if (_server != null) return;

    final router = Router()
      ..get('/api/state', _handleGetState)
      ..post('/api/state', _handlePostState)
      ..get('/api/scores', _handleGetScores)
      ..post('/api/score', _handlePostScore)
      ..post('/api/reset', _handleReset)
      ..get('/api/health', _handleHealth);

    final handler = const Pipeline()
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    DebugLogger.instance
        .log('LOCAL_SERVER', 'Servidor local iniciado: 0.0.0.0:$port');
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
    DebugLogger.instance.log('LOCAL_SERVER', 'Servidor local encerrado');
  }

  // ── Handlers HTTP ───────────────────────────────────────────────────────

  Response _handleGetState(Request req) =>
      _json(jsonEncode(_state));

  Future<Response> _handlePostState(Request req) async {
    final body = jsonDecode(await req.readAsString());
    _state = Map<String, dynamic>.from(body as Map);
    return _json('{"ok":true}');
  }

  Response _handleGetScores(Request req) =>
      _json(jsonEncode(_scores.values.toList()));

  Future<Response> _handlePostScore(Request req) async {
    final body =
        Map<String, dynamic>.from(jsonDecode(await req.readAsString()) as Map);
    final studentId = body['student_id']?.toString() ?? '';
    if (studentId.isEmpty) return Response.badRequest(body: 'student_id required');
    _scores[studentId] = body;
    return _json('{"ok":true}');
  }

  Future<Response> _handleReset(Request req) async {
    _state = Map.from(_emptyState);
    _scores.clear();
    return _json('{"ok":true}');
  }

  Response _handleHealth(Request req) =>
      _json('{"status":"ok","port":$port}');

  Response _json(String body) => Response.ok(
        body,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  // Adiciona CORS para que o PWA (GitHub Pages ou local) possa chamar a API.
  static Middleware _corsMiddleware() {
    const corsHeaders = {
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'GET, POST, OPTIONS',
      'access-control-allow-headers': 'content-type, authorization',
    };
    return (handler) => (request) async {
          if (request.method == 'OPTIONS') {
            return Response.ok('', headers: corsHeaders);
          }
          final response = await handler(request);
          return response.change(headers: corsHeaders);
        };
  }

  // ── IStateDatasource (professor escreve direto na memória) ──────────────

  @override
  Future<Map<String, dynamic>> getState(
      String baseUrl, String token, int courseId) async {
    return Map.from(_state);
  }

  @override
  Future<void> setSelectedQuiz({
    required String baseUrl,
    required String token,
    required int courseId,
    required int quizId,
    required String quizName,
  }) async {
    _state = {
      ..._state,
      'state': 'waiting',
      'current_page': -1,
      'current_slot': 0,
      'quiz_id': quizId,
      'course_id': courseId,
      'quiz_name': quizName,
      'round_id': '',
      'duration_seconds': 0,
      'start_on_first_response': false,
      'timer_started': false,
      'started_at': '',
      'ends_at': '',
    };
  }

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
  }) async {
    final now = DateTime.now();
    final roundId = now.microsecondsSinceEpoch.toString();
    final startedAt =
        startOnFirstResponse ? '' : now.toUtc().toIso8601String();
    final endsAt = startOnFirstResponse
        ? ''
        : now.add(Duration(seconds: duration)).toUtc().toIso8601String();

    _state = {
      'state': 'active',
      'current_page': page,
      'current_slot': slot,
      'total_pages': totalPages,
      'quiz_id': quizId,
      'course_id': courseId,
      'quiz_name': quizName,
      'round_id': roundId,
      'duration_seconds': duration,
      'start_on_first_response': startOnFirstResponse,
      'timer_started': !startOnFirstResponse,
      'started_at': startedAt,
      'ends_at': endsAt,
    };
  }

  @override
  Future<Map<String, dynamic>> startQuestionTimerIfNeeded(
      String baseUrl, String token, int courseId) async {
    final isActive =
        _state['state']?.toString().toLowerCase() == 'active';
    final startOnFirst = _state['start_on_first_response'] == true ||
        _state['start_on_first_response']?.toString().toLowerCase() == 'true';
    final timerStarted = _state['timer_started'] == true ||
        _state['timer_started']?.toString().toLowerCase() == 'true';
    final duration =
        int.tryParse(_state['duration_seconds']?.toString() ?? '') ?? 0;
    final hasEndsAt =
        (_state['ends_at']?.toString().isNotEmpty ?? false);

    if (!isActive || !startOnFirst || timerStarted || hasEndsAt || duration <= 0) {
      return Map.from(_state);
    }

    final now = DateTime.now();
    _state = {
      ..._state,
      'timer_started': true,
      'started_at': now.toUtc().toIso8601String(),
      'ends_at':
          now.add(Duration(seconds: duration)).toUtc().toIso8601String(),
    };
    DebugLogger.instance.log(
        'LOCAL_SERVER', 'Timer iniciado pela primeira resposta');
    return Map.from(_state);
  }

  @override
  Future<void> closeQuestion(
      String baseUrl, String token, int courseId) async {
    _state = {..._state, 'state': 'closed'};
  }

  @override
  Future<void> setFinished(
      String baseUrl, String token, int courseId) async {
    _state = {..._state, 'state': 'finished'};
  }

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
    final roundId = _state['round_id']?.toString() ?? '';
    final existing = _scores[studentId] ?? {};

    Map<String, dynamic> pageData = {};
    try {
      final raw = existing['pages'] as String? ?? '{}';
      final decoded = jsonDecode(raw);
      if (decoded is Map) pageData = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    pageData[page.toString()] = {'s': score, 'c': correct ? 1 : 0, 'r': roundId};

    int totalScore = 0;
    int totalCorrect = 0;
    for (final v in pageData.values) {
      if (v is Map) {
        totalScore += (v['s'] as num? ?? 0).toInt();
        totalCorrect += (v['c'] as num? ?? 0).toInt();
      }
    }

    _scores[studentId] = {
      'type': 'score',
      'student_id': studentId,
      'student_name': studentName,
      'score': totalScore,
      'correct_count': totalCorrect,
      // Duplo encode igual ao MoodleStateDatasource para que o QuizRepositoryImpl
      // consiga parsear sem alterações.
      'pages': jsonEncode(jsonEncode(pageData)),
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getScores(
      String baseUrl, String token, int courseId) async {
    return _scores.values.toList();
  }

  @override
  Future<void> resetQuiz(
      String baseUrl, String token, int courseId) async {
    _state = Map.from(_emptyState);
    _scores.clear();
  }
}
