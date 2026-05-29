import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config/quiz_runtime_config.dart';
import '../../core/services/quiz_state_service.dart';
import '../../domain/entities/local_quiz_entity.dart';
import '../../domain/entities/local_user_entity.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/quiz_state_entity.dart';
import '../../domain/entities/score_entity.dart';
import '../../domain/entities/student_entity.dart';
import '../../domain/repositories/i_quiz_runtime_repository.dart';
import '../../domain/services/quiz_sync_server.dart';

/// Gerencia o painel do professor – controle do quiz sem rede externa.
class ProfessorController extends ChangeNotifier {
  final IQuizRuntimeRepository _quizRepo;
  final QuizStateService _stateService;
  final QuizSyncServer _server;
  final QuestionNavigationMode navigationMode;

  List<LocalQuizEntity> _quizzes = [];
  LocalQuizEntity? _selectedQuiz;
  List<StudentEntity> _students = [];

  int _selectedQuestionIndex = 0;
  int _selectedDuration = 30;
  bool _startTimerOnFirstResponse = true;
  bool _showQuestionThumbnails = false;
  int? _revealQuestionSlot;

  bool _isLoading = false;
  String? _error;
  List<String> _log = [];

  Timer? _scoreRefreshTimer;
  bool _isRefreshingScores = false;

  ProfessorController({
    required IQuizRuntimeRepository quizRepo,
    required QuizStateService stateService,
    required QuizSyncServer server,
    this.navigationMode = QuestionNavigationMode.list,
  })  : _quizRepo = quizRepo,
        _stateService = stateService,
        _server = server;

  // ── Getters ────────────────────────────────────────────────────────────────
  List<LocalQuizEntity> get quizzes => _quizzes;
  LocalQuizEntity? get selectedQuiz => _selectedQuiz;
  List<QuestionEntity> get questions => _selectedQuiz?.questions ?? [];
  List<StudentEntity> get students => _students;
  QuizStateEntity get quizState => _stateService.quizState;
  List<ScoreEntity> get scores => _stateService.scores;
  int get selectedDuration => _selectedDuration;
  bool get startTimerOnFirstResponse => _startTimerOnFirstResponse;
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<String> get log => List.unmodifiable(_log);
  bool get isSetup => _selectedQuiz != null && questions.isNotEmpty;
  int get selectedQuestionIndex => _selectedQuestionIndex;
  bool get showQuestionThumbnails =>
      navigationMode == QuestionNavigationMode.list || _showQuestionThumbnails;
  bool get isListNavigation => navigationMode == QuestionNavigationMode.list;
  bool get isSingleQuestionNavigation =>
      navigationMode == QuestionNavigationMode.single;
  bool get supportsImport => _quizRepo.supportsImport;
  bool get supportsDelete => _quizRepo.supportsDelete;
  int? get revealQuestionSlot => _revealQuestionSlot;
  String get serverUrl => _server.serverUrl;
  bool get serverRunning => _server.isRunning;

  // ── Inicialização ─────────────────────────────────────────────────────────

  Future<void> init(LocalUserEntity user) async {
    _setLoading(true);
    try {
      await _quizRepo.initialize(user);
      _quizzes = await _quizRepo.loadQuizzes();
      _students = await _quizRepo.loadStudents();
      _bindServerCallbacks();
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  void _bindServerCallbacks() {
    _server.onGetState = () => _stateService.quizState;
    _server.onGetQuestion = (slot) {
      final q = _selectedQuiz?.questions;
      if (q == null) return null;
      try {
        return q.firstWhere((q) => q.slot == slot);
      } catch (_) {
        return null;
      }
    };
    _server.onGetStudents = () => _students;
    _server.onGetScores = () => _stateService.scores;
    _server.onScore = (body) async {
      // Persiste resposta remota no SQLite e atualiza ranking.
      await _quizRepo.saveRemoteAnswer(body);
      await _refreshScores();
    };
    _server.onReset = () async => await resetQuiz();
  }

  // ── Seleção de quiz ───────────────────────────────────────────────────────

  Future<void> selectQuiz(LocalQuizEntity quiz) async {
    _setLoading(true);
    _error = null;
    _log = [];
    try {
      final loaded = await _quizRepo.loadQuizWithQuestions(quiz.id);
      if (loaded == null) throw Exception('Quiz não encontrado.');
      _selectedQuiz = loaded;
      _selectedQuestionIndex = 0;
      final state = await _quizRepo.openSession(loaded);
      _stateService.updateState(state: state);
      final scores = await _quizRepo.loadScores();
      _stateService.updateScores(scores);
      _addLog(
          'Quiz "${loaded.name}" carregado (${loaded.questions.length} questões).');
      _startScorePolling();
    } catch (e) {
      _error = e.toString();
      _addLog('ERRO: $_error');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> deleteQuiz(int quizId) async {
    if (!_quizRepo.supportsDelete) return;
    _setLoading(true);
    try {
      await _quizRepo.deleteQuiz(quizId);
      _quizzes = await _quizRepo.loadQuizzes();
      if (_selectedQuiz?.id == quizId) {
        _selectedQuiz = null;
        _stateService.reset();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // ── Importação de XML ─────────────────────────────────────────────────────

  Future<void> importFromXml({
    required Uint8List bytes,
    required String fileName,
  }) async {
    _setLoading(true);
    _error = null;
    _log = [];
    try {
      if (!_quizRepo.supportsImport) {
        throw UnsupportedError('Importacao XML indisponivel neste modo.');
      }
      _addLog('Importando "$fileName"…');
      final quiz = await _quizRepo.importFromXml(bytes, fileName);
      _quizzes = await _quizRepo.loadQuizzes();
      _addLog('Importado: ${quiz.totalQuestions} questão(ões) salvas.');
      await selectQuiz(quiz);
    } catch (e) {
      _error = e.toString();
      _addLog('ERRO na importação: $_error');
    } finally {
      _setLoading(false);
    }
  }

  // ── Controle do quiz ──────────────────────────────────────────────────────

  Future<void> releaseQuestion(QuestionEntity q) async {
    final quiz = _selectedQuiz;
    if (quiz == null) return;
    final index = questions.indexOf(q);
    final page = index >= 0 ? index : questions.length;
    final now = DateTime.now();
    final roundId = 'r-${now.millisecondsSinceEpoch}';

    final newState = QuizStateEntity(
      status: QuizStatus.active,
      currentPage: page,
      currentSlot: q.slot,
      totalPages: questions.length,
      quizId: quiz.id,
      courseId: 0,
      quizTitle: quiz.name,
      roundId: roundId,
      durationSeconds: _selectedDuration,
      startOnFirstResponse: _startTimerOnFirstResponse,
      timerStarted: !_startTimerOnFirstResponse,
      startedAt: _startTimerOnFirstResponse ? null : now,
      endsAt: _startTimerOnFirstResponse
          ? null
          : now.add(Duration(seconds: _selectedDuration)),
    );

    await _quizRepo.updateState(newState);
    _stateService.updateState(state: newState, question: q);
    _addLog('Questão ${page + 1} liberada (slot=${q.slot}, round=$roundId).');
  }

  Future<void> extendQuestion(int extraSeconds) async {
    final state = quizState;
    if (!state.isActive) return;
    final remaining = state.endsAt?.difference(DateTime.now()).inSeconds ?? 0;
    final newDuration = (remaining < 0 ? 0 : remaining) + extraSeconds;
    final now = DateTime.now();
    final newState = QuizStateEntity(
      status: QuizStatus.active,
      currentPage: state.currentPage,
      currentSlot: state.currentSlot,
      totalPages: state.totalPages,
      quizId: state.quizId,
      courseId: 0,
      quizTitle: state.quizTitle,
      roundId: state.roundId,
      durationSeconds: newDuration,
      startOnFirstResponse: false,
      timerStarted: true,
      startedAt: now,
      endsAt: now.add(Duration(seconds: newDuration)),
    );
    await _quizRepo.updateState(newState);
    _stateService.updateState(state: newState);
  }

  Future<void> stopQuestion() async {
    final state = quizState;
    final newState = QuizStateEntity(
      status: QuizStatus.closed,
      currentPage: state.currentPage,
      currentSlot: state.currentSlot,
      totalPages: state.totalPages,
      quizId: state.quizId,
      courseId: 0,
      quizTitle: state.quizTitle,
      roundId: state.roundId,
    );
    await _quizRepo.updateState(newState);
    _stateService.updateState(state: newState);
    _addLog('Questão encerrada.');
    await _refreshScores();
  }

  Future<void> finishQuiz() async {
    final state = quizState;
    final newState = QuizStateEntity(
      status: QuizStatus.finished,
      currentPage: state.currentPage,
      currentSlot: state.currentSlot,
      totalPages: state.totalPages,
      quizId: state.quizId,
      courseId: 0,
      quizTitle: state.quizTitle,
      roundId: state.roundId,
    );
    await _quizRepo.updateState(newState);
    _stateService.updateState(state: newState);
    _stopScorePolling();
    _addLog('Quiz finalizado.');
  }

  Future<void> resetQuiz() async {
    final quiz = _selectedQuiz;
    if (quiz == null) return;
    _setLoading(true);
    try {
      await _quizRepo.resetSession(quiz.id, quiz.name);
      _stateService.reset();
      _addLog('Quiz reiniciado.');
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // ── Polling de scores (1 Hz) ──────────────────────────────────────────────

  void _startScorePolling() {
    _scoreRefreshTimer?.cancel();
    _scoreRefreshTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _refreshScores());
  }

  void _stopScorePolling() {
    _scoreRefreshTimer?.cancel();
    _scoreRefreshTimer = null;
  }

  Future<void> _refreshScores() async {
    if (_isRefreshingScores) return;
    _isRefreshingScores = true;
    try {
      final scores = await _quizRepo.loadScores();
      _stateService.updateScores(scores);

      // Verifica se timer deve iniciar (primeira resposta chegou)
      final state = quizState;
      if (state.isTimerPending && scores.any(_answeredCurrentRound(state))) {
        await _startTimer(state);
      }
    } finally {
      _isRefreshingScores = false;
    }
  }

  bool Function(ScoreEntity) _answeredCurrentRound(QuizStateEntity state) {
    return (s) => s.answeredPageRounds[state.currentPage] == state.roundId;
  }

  Future<void> _startTimer(QuizStateEntity state) async {
    final now = DateTime.now();
    final newState = QuizStateEntity(
      status: QuizStatus.active,
      currentPage: state.currentPage,
      currentSlot: state.currentSlot,
      totalPages: state.totalPages,
      quizId: state.quizId,
      courseId: 0,
      quizTitle: state.quizTitle,
      roundId: state.roundId,
      durationSeconds: state.durationSeconds,
      startOnFirstResponse: true,
      timerStarted: true,
      startedAt: now,
      endsAt: now.add(Duration(seconds: state.durationSeconds)),
    );
    await _quizRepo.updateState(newState);
    _stateService.updateState(state: newState);
  }

  // ── Setters de UI ─────────────────────────────────────────────────────────

  void setSelectedQuestionIndex(int index) {
    if (questions.isEmpty) return;
    _selectedQuestionIndex = index.clamp(0, questions.length - 1);
    notifyListeners();
  }

  void setDuration(int seconds) {
    _selectedDuration = seconds;
    notifyListeners();
  }

  void setStartTimerOnFirstResponse(bool value) {
    _startTimerOnFirstResponse = value;
    notifyListeners();
  }

  void setShowQuestionThumbnails(bool value) {
    if (navigationMode == QuestionNavigationMode.list) return;
    _showQuestionThumbnails = value;
    notifyListeners();
  }

  void setRevealQuestion(QuestionEntity question) {
    _revealQuestionSlot = question.slot;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _addLog(String msg) {
    _log.add('[${DateTime.now().toIso8601String().substring(11, 19)}] $msg');
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopScorePolling();
    super.dispose();
  }
}
