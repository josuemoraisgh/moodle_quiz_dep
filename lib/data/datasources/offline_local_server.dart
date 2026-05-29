import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../core/utils/local_ip.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/quiz_state_entity.dart';
import '../../domain/entities/score_entity.dart';
import '../../domain/entities/student_entity.dart';
import '../../domain/services/quiz_sync_server.dart';

/// Servidor HTTP local que substitui o Moodle no modo presencial offline.
///
/// O professor executa este servidor no próprio dispositivo.
/// Alunos conectam via Wi-Fi usando o IP exibido no QR code.
///
/// Endpoints:
///   GET  /api/state          → estado atual do quiz
///   GET  /api/question/:slot → dados da questão (JSON)
///   GET  /api/students       → lista de nomes para o dropdown de login
///   POST /api/score          → registrar resposta de aluno
///   GET  /api/scores         → ranking atual
///   POST /api/reset          → reiniciar sessão
class OfflineLocalServer implements QuizSyncServer {
  final int port;
  HttpServer? _server;
  String _localIp = '0.0.0.0';

  // Callbacks que o ProfessorController injeta
  QuizStateEntity Function()? _onGetState;
  QuestionEntity? Function(int slot)? _onGetQuestion;
  List<StudentEntity> Function()? _onGetStudents;
  List<ScoreEntity> Function()? _onGetScores;
  Future<void> Function(Map<String, dynamic> body)? _onScore;
  Future<void> Function()? _onReset;

  OfflineLocalServer({this.port = 8080});

  String get localIp => _localIp;
  @override
  String get serverUrl => 'http://$_localIp:$port';

  @override
  set onGetState(QuizStateEntity Function()? callback) =>
      _onGetState = callback;

  @override
  set onGetQuestion(QuestionEntity? Function(int slot)? callback) =>
      _onGetQuestion = callback;

  @override
  set onGetStudents(List<StudentEntity> Function()? callback) =>
      _onGetStudents = callback;

  @override
  set onGetScores(List<ScoreEntity> Function()? callback) =>
      _onGetScores = callback;

  @override
  set onScore(Future<void> Function(Map<String, dynamic> body)? callback) =>
      _onScore = callback;

  @override
  set onReset(Future<void> Function()? callback) => _onReset = callback;

  @override
  Future<void> start() async {
    _localIp = (await getLocalIp()) ?? '0.0.0.0';

    final router = Router();

    router.get('/api/state', _handleState);
    router.get('/api/question/<slot>', _handleQuestion);
    router.get('/api/students', _handleStudents);
    router.get('/api/scores', _handleScores);
    router.post('/api/score', _handleScore);
    router.post('/api/reset', _handleReset);

    // Arquivos estáticos (página web simples para alunos via browser)
    router.get('/', _handleWebRoot);
    router.get('/<path|.*>', _handle404);

    final pipeline =
        const Pipeline().addMiddleware(_cors()).addHandler(router.call);

    _server = await shelf_io.serve(pipeline, InternetAddress.anyIPv4, port);
  }

  @override
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  @override
  bool get isRunning => _server != null;

  // ── Handlers ─────────────────────────────────────────────────────────────

  Response _handleState(Request req) {
    final state = _onGetState?.call() ?? QuizStateEntity.empty();
    return _json(_stateToMap(state));
  }

  Response _handleQuestion(Request req, String slot) {
    final slotNum = int.tryParse(slot);
    if (slotNum == null) return Response.badRequest();
    final q = _onGetQuestion?.call(slotNum);
    if (q == null) {
      return Response.notFound('{"error":"Questão não encontrada"}');
    }
    return _json(_questionToMap(q));
  }

  Response _handleStudents(Request req) {
    final students = _onGetStudents?.call() ?? [];
    return _json({'students': students.map((s) => s.name).toList()});
  }

  Response _handleScores(Request req) {
    final scores = _onGetScores?.call() ?? [];
    return _json({'scores': scores.map(_scoreToMap).toList()});
  }

  Future<Response> _handleScore(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      await _onScore?.call(body);
      return _json({'ok': true});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': '$e'}));
    }
  }

  Future<Response> _handleReset(Request req) async {
    await _onReset?.call();
    return _json({'ok': true});
  }

  Response _handleWebRoot(Request req) {
    return Response.ok(
      _studentWebPage(),
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }

  Response _handle404(Request req, String path) =>
      Response.notFound('Not found: $path');

  // ── Serialização ──────────────────────────────────────────────────────────

  Map<String, dynamic> _stateToMap(QuizStateEntity s) => {
        'status': s.status.name,
        'currentSlot': s.currentSlot,
        'currentPage': s.currentPage,
        'totalPages': s.totalPages,
        'quizId': s.quizId,
        'quizTitle': s.quizTitle,
        'roundId': s.roundId,
        'durationSeconds': s.durationSeconds,
        'startOnFirstResponse': s.startOnFirstResponse,
        'timerStarted': s.timerStarted,
        'startedAt': s.startedAt?.millisecondsSinceEpoch,
        'endsAt': s.endsAt?.millisecondsSinceEpoch,
      };

  Map<String, dynamic> _questionToMap(QuestionEntity q) => {
        'slot': q.slot,
        'page': q.page,
        'text': q.text,
        'htmlText': q.htmlText,
        'type': q.type,
        'generalFeedback': q.generalFeedback,
        'inputBaseName': q.inputBaseName,
        'seqCheck': q.seqCheck,
        'answerInputName': q.answerInputName,
        'choices': q.choices
            .map((c) => {
                  'value': c.value,
                  'text': c.text,
                  'htmlText': c.htmlText,
                  'isCorrect': c.isCorrect,
                })
            .toList(),
      };

  Map<String, dynamic> _scoreToMap(ScoreEntity s) => {
        'studentId': s.studentId,
        'studentName': s.studentName,
        'score': s.score,
        'correctCount': s.correctCount,
        'totalAnswered': s.totalAnswered,
        'rank': s.rank,
      };

  // ── Helpers ───────────────────────────────────────────────────────────────

  Response _json(Map<String, dynamic> body) => Response.ok(
        jsonEncode(body),
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'access-control-allow-origin': '*',
        },
      );

  Middleware _cors() => (Handler inner) {
        return (Request req) async {
          if (req.method == 'OPTIONS') {
            return Response.ok('', headers: {
              'access-control-allow-origin': '*',
              'access-control-allow-methods': 'GET, POST, OPTIONS',
              'access-control-allow-headers': 'content-type',
            });
          }
          final res = await inner(req);
          return res.change(headers: {'access-control-allow-origin': '*'});
        };
      };

  /// Página web mínima para alunos que preferirem usar o browser.
  String _studentWebPage() => '''
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Quiz Presencial</title>
  <style>
    body { font-family: sans-serif; background:#0D0D2B; color:#fff; margin:0; padding:20px; }
    h1   { color:#6C63FF; }
    p    { color:#aaa; }
    .card { background:#1A1A3E; border-radius:12px; padding:20px; max-width:480px; margin:0 auto; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Quiz Presencial</h1>
    <p>Servidor ativo. Use o aplicativo Flutter no seu dispositivo para participar.</p>
    <p>IP do professor: <strong>$localIp:$port</strong></p>
  </div>
</body>
</html>
''';
}
