import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/debug_logger.dart';
import '../../core/utils/moodle_html_parser.dart';
import '../../core/utils/moodle_xml_quiz_parser.dart';
import '../../domain/entities/moodle_course.dart';
import '../../domain/entities/moodle_quiz.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/quiz_state_entity.dart';
import '../../domain/entities/score_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/i_quiz_repository.dart';
import '../../domain/usecases/close_question_usecase.dart';
import '../../domain/usecases/release_question_usecase.dart';

/// Gerencia estado do professor: seleção de curso/quiz + controle do quiz.
class ProfessorController extends ChangeNotifier {
  final IQuizRepository _quizRepo;
  final ReleaseQuestionUseCase _releaseQuestion;
  final CloseQuestionUseCase _closeQuestion;

  // ── Usuário autenticado ────────────────────────────────────────────────────────────────
  UserEntity? _user;

  // ── Seleção ────────────────────────────────────────────────────────────────
  List<MoodleCourse> _courses = [];
  List<MoodleQuiz> _quizzes = [];
  MoodleCourse? _selectedCourse;
  MoodleQuiz? _selectedQuiz;
  int? _revealQuestionSlot;

  // ── Lista de questões carregadas do Moodle ─────────────────────────────────
  List<QuestionEntity> _questions = [];
  int? _attemptId; // tentativa usada para preview das questões

  // ── Estado do quiz ─────────────────────────────────────────────────────────
  QuizStateEntity _quizState = QuizStateEntity.empty();
  List<ScoreEntity> _scores = [];
  int _selectedDuration = 30;
  bool _startTimerOnFirstResponse = true;
  bool _isLoading = false;
  bool _isXmlPreviewMode = false;
  bool _isRefreshing = false; // guard contra chamadas simultâneas ao GSheets
  int _selectedQuestionIndex = 0;
  bool _showQuestionThumbnails = false;
  String? _error;
  List<String> _log = [];
  Timer? _pollTimer;

  ProfessorController({
    required IQuizRepository quizRepo,
    required ReleaseQuestionUseCase releaseQuestion,
    required CloseQuestionUseCase closeQuestion,
  })  : _quizRepo = quizRepo,
        _releaseQuestion = releaseQuestion,
        _closeQuestion = closeQuestion;

  // ── Getters ────────────────────────────────────────────────────────────────
  List<MoodleCourse> get courses => _courses;
  List<MoodleQuiz> get quizzes => _quizzes;
  MoodleCourse? get selectedCourse => _selectedCourse;
  MoodleQuiz? get selectedQuiz => _selectedQuiz;
  int? get revealQuestionSlot => _revealQuestionSlot;
  List<QuestionEntity> get questions => _questions;
  int? get attemptId => _attemptId;
  QuizStateEntity get quizState => _quizState;
  List<ScoreEntity> get scores => _scores;
  int get selectedDuration => _selectedDuration;
  bool get startTimerOnFirstResponse => _startTimerOnFirstResponse;
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<String> get log => List.unmodifiable(_log);
  bool get isSetup => _selectedQuiz != null && _questions.isNotEmpty;
  bool get isXmlPreviewMode => _isXmlPreviewMode;
  int get selectedQuestionIndex => _selectedQuestionIndex;
  bool get showQuestionThumbnails => _showQuestionThumbnails;

  void setSelectedQuestionIndex(int index) {
    if (_questions.isEmpty) {
      _selectedQuestionIndex = 0;
      return;
    }
    _selectedQuestionIndex = index.clamp(0, _questions.length - 1);
  }

  void setShowQuestionThumbnails(bool value) {
    _showQuestionThumbnails = value;
  }

  void setRevealQuestion(QuestionEntity question) {
    _revealQuestionSlot = question.slot;
  }

  Future<void> runConnectionDiagnostics({
    QuestionEntity? question,
    int? index,
  }) async {
    final user = _user;
    final course = _selectedCourse;
    final quiz = _selectedQuiz;

    _addLog('━━ Diagnóstico de conexão e questão ━━');
    _addLog('Usuário: ${user?.fullname ?? "(não autenticado)"}');
    _addLog('Curso: ${course?.fullname ?? "(não selecionado)"} '
        'id=${course?.id ?? "-"}');
    _addLog('Quiz: ${quiz?.name ?? "(não selecionado)"} '
        'id=${quiz?.id ?? "-"} attempt=${_attemptId ?? "-"}');
    _addLog('Questões carregadas: ${_questions.length}');

    if (user == null || course == null) {
      _addLog('Conexão: não testada porque usuário/curso não estão prontos.');
      return;
    }

    try {
      final quizzes = await _quizRepo.getQuizzesByCourse(user, course.id);
      _addLog('Moodle OK: ${quizzes.length} quiz(es) retornado(s) no curso.');
    } catch (e) {
      _addLog('Moodle ERRO: $e');
    }

    try {
      final state = await _quizRepo.getQuizState(user, course.id);
      _addLog('Estado compartilhado OK: status=${state.status.name} '
          'slot=${state.currentSlot} page=${state.currentPage} '
          'round=${state.roundId}');
    } catch (e) {
      _addLog('Estado compartilhado ERRO: $e');
    }

    try {
      final scores = await _quizRepo.getScores(user, course.id);
      _addLog('Pontuações OK: ${scores.length} registro(s).');
    } catch (e) {
      _addLog('Pontuações ERRO: $e');
    }

    if (question != null) {
      logQuestionDiagnostics(question, index ?? _questions.indexOf(question));
    }
  }

  void logQuestionDiagnostics(QuestionEntity question, int index) {
    final displayIndex = index >= 0 ? index + 1 : '?';
    final gap = question.gapInputData;
    final ddMarker = question.ddMarkerData;
    final dlog = DebugLogger.instance;

    _addLog(
        '━━ Diagnóstico da questão $displayIndex / slot ${question.slot} ━━');
    _addLog('Tipo=${question.type} page=${question.page} '
        'choices=${question.choices.length} controls=${question.answerControls.length} '
        'gapCount=${gap?.gapCount ?? 0} gapPrefix=${gap?.inputNamePrefix ?? "-"} '
        'gapOptions=${gap?.options.length ?? 0} gapGroups=${gap?.optionsByGap.length ?? 0} '
        'ddMarkers=${ddMarker?.choices.length ?? 0} '
        'seq=${question.seqCheck}');
    _addLog('text len=${question.text.length} '
        'flags=${_diagnosticFlags(question.text)} '
        'snip="${_diagnosticSnippet(question.text)}"');
    _addLog('htmlText len=${question.htmlText.length} '
        'flags=${_diagnosticFlags(question.htmlText)} '
        'plain="${_diagnosticSnippet(_plainDiagnostic(question.htmlText))}"');
    _addLog('displayHtml len=${question.displayHtml.length} '
        'flags=${_diagnosticFlags(question.displayHtml)} '
        'plain="${_diagnosticSnippet(_plainDiagnostic(question.displayHtml))}"');
    _addLog('rightAnswer len=${question.rightAnswerHtml.length} '
        'flags=${_diagnosticFlags(question.rightAnswerHtml)} '
        'plain="${_diagnosticSnippet(_plainDiagnostic(question.rightAnswerHtml))}"');

    if (question.isGapSelect || question.isDdwtos) {
      _logGapPromptCandidate('htmlText', question.htmlText);
      _logGapPromptCandidate('displayHtml', question.displayHtml);
    }

    dlog.log('PROF_QUESTION_DIAG', 'Questão selecionada para diagnóstico',
        data: {
          'index': displayIndex,
          'slot': question.slot,
          'page': question.page,
          'type': question.type,
          'textLen': question.text.length,
          'htmlTextLen': question.htmlText.length,
          'displayHtmlLen': question.displayHtml.length,
          'rightAnswerLen': question.rightAnswerHtml.length,
          'gapCount': gap?.gapCount ?? 0,
          'flagsText': _diagnosticFlags(question.text),
          'flagsHtml': _diagnosticFlags(question.htmlText),
          'flagsDisplay': _diagnosticFlags(question.displayHtml),
        });
  }

  // ── Seleção de curso / quiz ────────────────────────────────────────────────

  Future<void> loadCourses(UserEntity user) async {
    _user = user;
    _setLoading(true);
    _error = null;
    try {
      _courses = await _quizRepo.getCourses(user);
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> selectCourse(UserEntity user, MoodleCourse course) async {
    _selectedCourse = course;
    _selectedQuiz = null;
    _quizzes = [];
    _questions = [];
    _selectedQuestionIndex = 0;
    _isXmlPreviewMode = false;
    _setLoading(true);
    _error = null;
    try {
      _quizzes = await _quizRepo.getQuizzesByCourse(user, course.id);
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  /// Seleciona o quiz e carrega a lista de questões iniciando uma tentativa.
  Future<void> selectQuiz(UserEntity user, MoodleQuiz quiz) async {
    _selectedQuiz = quiz;
    _questions = [];
    _selectedQuestionIndex = 0;
    _isXmlPreviewMode = false;
    _setLoading(true);
    _error = null;
    _log = [];
    try {
      final courseId = _selectedCourse?.id;
      if (courseId != null) {
        await _quizRepo.setSelectedQuiz(
          user: user,
          courseId: courseId,
          quizId: quiz.id,
          quizName: quiz.name,
        );
      }

      _addLog('━━ Iniciando quiz ${quiz.name} (id=${quiz.id}) ━━');
      _addLog('Buscando/criando attempt…');
      _attemptId = await _quizRepo.startAttempt(user, quiz.id, onLog: _addLog);
      _addLog('Attempt ID: $_attemptId');
      await _loadAllQuestions(user, _attemptId!);
      _addLog('━━ Concluído: ${_questions.length} questão(ões) prontas ━━');
      await _refreshStateAfterWrite();
    } catch (e) {
      _error = e.toString();
      _addLog('ERRO: $_error');
    } finally {
      _setLoading(false);
    }
  }

  // ── Controle do quiz ───────────────────────────────────────────────────────

  Future<void> selectQuizFromXml(
    UserEntity user, {
    required Uint8List bytes,
    required String fileName,
  }) async {
    _user = user;
    _selectedCourse ??= const MoodleCourse(
      id: -1,
      shortname: 'XML',
      fullname: 'Pre-visualizacao local por XML',
    );
    _selectedQuiz = MoodleQuiz(
      id: -DateTime.now().millisecondsSinceEpoch,
      courseId: _selectedCourse?.id ?? -1,
      name: fileName,
      preferredBehaviour: 'immediatefeedback',
      reviewCorrectness: 0x10000,
    );
    _questions = [];
    _selectedQuestionIndex = 0;
    _attemptId = null;
    _isXmlPreviewMode = true;
    _setLoading(true);
    _error = null;
    _log = [];
    try {
      _addLog('━━ Carregando quiz local do XML "$fileName" ━━');
      _questions = MoodleXmlQuizParser.parseQuestions(
        bytes,
        token: user.token,
        baseUrl: user.baseUrl,
        onLog: _addLog,
      );
      _selectedQuestionIndex = 0;
      _quizState = QuizStateEntity.empty();
      _scores = [];
      _addLog('━━ Concluido: ${_questions.length} questao(oes) prontas ━━');
    } catch (e) {
      _error = e.toString();
      _addLog('ERRO ao ler XML: $_error');
    } finally {
      _setLoading(false);
    }
  }

  void setDuration(int seconds) {
    _selectedDuration = seconds;
    notifyListeners();
  }

  void setStartTimerOnFirstResponse(bool value) {
    _startTimerOnFirstResponse = value;
    notifyListeners();
  }

  Future<void> releaseQuestion(QuestionEntity q) async {
    final dlog = DebugLogger.instance;
    if (_isXmlPreviewMode) {
      final index = _questions.indexOf(q);
      final page = index >= 0 ? index : _questions.length;
      final now = DateTime.now();
      _quizState = QuizStateEntity(
        status: QuizStatus.active,
        currentPage: page,
        currentSlot: q.slot,
        totalPages: _questions.length,
        quizId: _selectedQuiz?.id ?? 0,
        courseId: _selectedCourse?.id ?? 0,
        quizTitle: _selectedQuiz?.name ?? 'Quiz XML',
        roundId: 'xml-${now.millisecondsSinceEpoch}',
        durationSeconds: _selectedDuration,
        startOnFirstResponse: _startTimerOnFirstResponse,
        timerStarted: !_startTimerOnFirstResponse,
        startedAt: _startTimerOnFirstResponse ? null : now,
        endsAt: _startTimerOnFirstResponse
            ? null
            : now.add(Duration(seconds: _selectedDuration)),
      );
      _addLog(
          'XML preview: questao ${page + 1} marcada como ativa localmente.');
      notifyListeners();
      return;
    }

    final user = _user;
    final courseId = _selectedCourse?.id;
    if (_selectedQuiz == null || user == null || courseId == null) {
      dlog.log('PROF_RELEASE', '✗ PRÉ-CONDIÇÃO FALHOU', data: {
        'selectedQuiz': _selectedQuiz?.name,
        'user': user?.fullname,
        'courseId': courseId,
      });
      _error = 'Não foi possível liberar: usuário/curso/quiz não selecionado.';
      notifyListeners();
      return;
    }
    final index = _questions.indexOf(q);
    final page = index >= 0 ? index : _questions.length;
    dlog.log('PROF_RELEASE', '★ Liberando questão', data: {
      'courseId': courseId,
      'quizId': _selectedQuiz!.id,
      'quizName': _selectedQuiz!.name,
      'page': page,
      'slot': q.slot,
      'duration': _selectedDuration,
      'startOnFirstResponse': _startTimerOnFirstResponse,
      'totalPages': _questions.length,
    });
    _setLoading(true);
    _error = null;
    try {
      await _releaseQuestion(
        user: user,
        courseId: courseId,
        page: page,
        slot: q.slot,
        duration: _selectedDuration,
        startOnFirstResponse: _startTimerOnFirstResponse,
        totalPages: _questions.length,
        quizName: _selectedQuiz!.name,
        quizId: _selectedQuiz!.id,
      );
      dlog.log('PROF_RELEASE', '✓ release escrito no mq_state');
      await _refreshStateAfterWrite();
      dlog.log('PROF_RELEASE', 'estado pós-write', data: {
        'status': _quizState.status.name,
        'slot': _quizState.currentSlot,
      });
    } catch (e, st) {
      _error = e.toString();
      dlog.log('PROF_RELEASE', '✗ ERRO ao liberar: $e');
      debugPrint(st.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> extendQuestion(int extraSeconds) async {
    if (_isXmlPreviewMode) {
      final state = quizState;
      if (!state.isActive) return;
      final remaining = state.endsAt?.difference(DateTime.now()).inSeconds ?? 0;
      final newDuration = (remaining < 0 ? 0 : remaining) + extraSeconds;
      _quizState = QuizStateEntity(
        status: QuizStatus.active,
        currentPage: state.currentPage,
        currentSlot: state.currentSlot,
        totalPages: state.totalPages,
        quizId: state.quizId,
        courseId: state.courseId,
        quizTitle: state.quizTitle,
        roundId: state.roundId,
        durationSeconds: newDuration,
        timerStarted: true,
        startedAt: DateTime.now(),
        endsAt: DateTime.now().add(Duration(seconds: newDuration)),
      );
      notifyListeners();
      return;
    }

    final user = _user;
    final courseId = _selectedCourse?.id;
    final state = quizState;
    if (!state.isActive ||
        state.endsAt == null ||
        user == null ||
        courseId == null) {
      return;
    }
    final remaining = state.endsAt!.difference(DateTime.now()).inSeconds;
    final newDuration = (remaining < 0 ? 0 : remaining) + extraSeconds;
    _setLoading(true);
    _error = null;
    try {
      await _releaseQuestion(
        user: user,
        courseId: courseId,
        page: state.currentPage,
        slot: state.currentSlot,
        duration: newDuration,
        startOnFirstResponse: false,
        totalPages: state.totalPages,
        quizName: state.quizTitle,
        quizId: _selectedQuiz?.id ?? 0,
      );
      await _refreshStateAfterWrite();
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> stopQuestion() async {
    if (_isXmlPreviewMode) {
      _quizState = QuizStateEntity(
        status: QuizStatus.closed,
        currentPage: _quizState.currentPage,
        currentSlot: _quizState.currentSlot,
        totalPages: _quizState.totalPages,
        quizId: _quizState.quizId,
        courseId: _quizState.courseId,
        quizTitle: _quizState.quizTitle,
        roundId: _quizState.roundId,
      );
      notifyListeners();
      return;
    }

    final user = _user;
    final courseId = _selectedCourse?.id;
    if (user == null || courseId == null) return;
    _setLoading(true);
    _error = null;
    try {
      await _closeQuestion(user, courseId);
      await _refreshStateAfterWrite();
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> finishQuiz() async {
    if (_isXmlPreviewMode) {
      _quizState = QuizStateEntity(
        status: QuizStatus.finished,
        currentPage: _quizState.currentPage,
        currentSlot: _quizState.currentSlot,
        totalPages: _quizState.totalPages,
        quizId: _quizState.quizId,
        courseId: _quizState.courseId,
        quizTitle: _quizState.quizTitle,
        roundId: _quizState.roundId,
      );
      notifyListeners();
      return;
    }

    final user = _user;
    final courseId = _selectedCourse?.id;
    if (user == null || courseId == null) return;
    _setLoading(true);
    _error = null;
    try {
      await _quizRepo.setFinished(user, courseId);
      await _refreshStateAfterWrite();
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> resetQuiz() async {
    if (_isXmlPreviewMode) {
      _quizState = QuizStateEntity.empty();
      _scores = [];
      notifyListeners();
      return;
    }

    final user = _user;
    final courseId = _selectedCourse?.id;
    final quiz = _selectedQuiz;
    if (user == null || courseId == null) return;
    _setLoading(true);
    try {
      await _quizRepo.resetQuiz(user, courseId);
      _scores = [];
      _attemptId = null;
      _log = [];
      if (_isXmlPreviewMode) {
        _quizState = QuizStateEntity.empty();
        await _refreshStateAfterWrite();
        return;
      }
      _questions = [];
      // Recria a tentativa e recarrega questões para resolver qualquer
      // tentativa travada (ex: preview do Moodle) ou attempt deletado
      if (quiz != null) {
        _addLog('━━ Recarregando questões após reiniciar ━━');
        _addLog('Buscando/criando attempt…');
        _attemptId =
            await _quizRepo.startAttempt(user, quiz.id, onLog: _addLog);
        _addLog('Attempt ID: $_attemptId');
        await _loadAllQuestions(user, _attemptId!);
        _addLog('━━ Concluído: ${_questions.length} questão(ões) prontas ━━');
      }
      await _refreshStateAfterWrite();
    } catch (e) {
      _error = e.toString();
      _addLog('ERRO ao reiniciar: $_error');
    } finally {
      _setLoading(false);
    }
  }

  // ── Polling ────────────────────────────────────────────────────────────────

  void startPolling() {
    if (_isXmlPreviewMode) return;
    _pollTimer?.cancel();
    _refreshState();
    // Polling mais curto para disparar rapidamente o cronômetro após a
    // primeira resposta dos alunos.
    _pollTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _refreshState());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ── Privado ────────────────────────────────────────────────────────────────

  void _addLog(String msg) {
    _log.add('[${DateTime.now().toIso8601String().substring(11, 19)}] $msg');
    notifyListeners();
  }

  void _logGapPromptCandidate(String label, String html) {
    if (html.trim().isEmpty) {
      _addLog('prompt($label): vazio');
      return;
    }

    try {
      final prompt = MoodleHtmlParser.extractTextWithGapMarkers(html, '', '');
      _addLog('prompt($label) len=${prompt.length} '
          'flags=${_diagnosticFlags(prompt)} '
          'plain="${_diagnosticSnippet(_plainDiagnostic(prompt), 900)}"');
    } catch (e) {
      _addLog('prompt($label) ERRO: $e');
    }
  }

  static String _diagnosticFlags(String value) {
    final checks = <String, bool>{
      'qno': value.contains('qno'),
      'Incompleto': value.contains('Incompleto'),
      'Vale': value.contains('Vale '),
      'Verificar': value.contains('Verificar'),
      'Em branco': value.contains('Em branco'),
      'spanClass': value.contains('<span class'),
      'alt': value.contains('alt='),
      'src': value.contains('src='),
      'texImg': value.contains('/filter/tex/') || value.contains('tex/pix.php'),
      'select': value.contains('<select'),
      'marker': RegExp(r'\[\d+\]').hasMatch(value),
    };

    final active = checks.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .join(',');
    return active.isEmpty ? 'ok' : active;
  }

  static String _plainDiagnostic(String html) {
    return html
        .replaceAll(
            RegExp(r'<script\b[^>]*>.*?</script>',
                caseSensitive: false, dotAll: true),
            ' ')
        .replaceAll(
            RegExp(r'<style\b[^>]*>.*?</style>',
                caseSensitive: false, dotAll: true),
            ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _diagnosticSnippet(String value, [int max = 600]) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= max) return normalized;
    return '${normalized.substring(0, max)}...';
  }

  Future<void> _loadAllQuestions(UserEntity user, int attemptId) async {
    try {
      final questions = await _quizRepo.loadQuestionsWithAnswers(
        user,
        attemptId,
        0,
        onLog: _addLog,
      );
      _questions = questions;
      _selectedQuestionIndex = 0;
      _addLog('Múltipla escolha prontas: ${questions.length}');
    } catch (e) {
      _addLog('ERRO em loadQuestionsWithAnswers: $e');
      rethrow;
    }
    notifyListeners();
  }

  Future<void> _refreshState() async {
    final user = _user;
    final courseId = _selectedCourse?.id;
    if (user == null || courseId == null) return;
    // Impede chamadas simultâneas ao Moodle
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      _quizState = await _quizRepo.getQuizState(user, courseId);
      _scores = await _quizRepo.getScores(user, courseId);
      if (_quizState.isTimerPending &&
          _hasAnyAnswerForPage(
            _quizState.currentPage,
            _quizState.roundId,
            _scores,
          )) {
        _quizState = await _quizRepo.startQuestionTimerIfNeeded(user, courseId);
      }
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _isRefreshing = false;
    }
  }

  /// Aguarda o GSheets confirmar a escrita antes de ler o novo estado.
  Future<void> _refreshStateAfterWrite() async {
    await Future.delayed(const Duration(milliseconds: 800));
    await _refreshState();
  }

  bool _hasAnyAnswerForPage(
      int page, String roundId, List<ScoreEntity> scores) {
    if (page < 0 || roundId.isEmpty) return false;
    for (final score in scores) {
      if (score.answeredPageRounds[page] == roundId) {
        return true;
      }
    }
    return false;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
