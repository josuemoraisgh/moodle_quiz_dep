import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/debug_logger.dart';
import '../../domain/entities/moodle_course.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/quiz_state_entity.dart';
import '../../domain/entities/score_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/i_quiz_repository.dart';

/// Gerencia estado do estudante: seleção de disciplina + tentativa Moodle + polling.
class StudentController extends ChangeNotifier {
  final IQuizRepository _quizRepo;

  // ── Seleção de disciplina ───────────────────────────────────────────────────
  List<MoodleCourse> _courses = [];
  int? _selectedCourseId;
  bool _isLoadingCourses = false;
  bool? _hasActivity;

  // ── Tentativa Moodle ───────────────────────────────────────────────────────
  int? _attemptId;
  int? _currentQuizId;
  QuestionEntity? _currentQuestion;

  // ── Estado do quiz ─────────────────────────────────────────────────────────
  QuizStateEntity _quizState = QuizStateEntity.empty();
  List<ScoreEntity> _scores = [];

  // Mapa unificado de respostas: inputName → value.
  // Para todos os tipos: multichoice, numerical, shortanswer, match, gapselect.
  Map<String, String> _selectedAnswers = {};

  String? _selectedChoiceText; // texto legível para exibição no feedback
  bool _hasAnswered = false;
  bool _isSubmitting = false;
  bool _lastAnswerCorrect = false;
  bool _lastAnswerGraded = true;
  bool _isLoadingQuestion = false;
  String? _error;
  String? _attemptError;
  Timer? _pollTimer;
  int _lastSeenSlot = 0;
  bool _autoSubmitted = false;
  bool _isRefreshingState = false;

  StudentController({required IQuizRepository quizRepo}) : _quizRepo = quizRepo;

  // ── Getters ─────────────────────────────────────────────────────────────────
  List<MoodleCourse> get courses => _courses;
  int? get selectedCourseId => _selectedCourseId;
  bool get isLoadingCourses => _isLoadingCourses;
  bool? get hasActivity => _hasActivity;
  int? get attemptId => _attemptId;
  QuizStateEntity get quizState => _quizState;
  QuestionEntity? get currentQuestion => _currentQuestion;
  List<ScoreEntity> get scores => _scores;

  /// Para retrocompatibilidade: valor selecionado no multichoice.
  String? get selectedChoice {
    final q = _currentQuestion;
    if (q == null) return null;
    return _selectedAnswers[q.inputBaseName];
  }

  /// Mapa completo de respostas (todos os tipos).
  Map<String, String> get selectedAnswers => Map.unmodifiable(_selectedAnswers);

  /// True se há pelo menos uma resposta parcial preenchida.
  bool get hasAnyAnswer => _selectedAnswers.isNotEmpty;

  String? get selectedChoiceText => _selectedChoiceText;
  bool get hasAnswered => _hasAnswered;
  bool get isSubmitting => _isSubmitting;
  bool get lastAnswerCorrect => _lastAnswerCorrect;
  bool get lastAnswerGraded => _lastAnswerGraded;
  bool get isLoadingQuestion => _isLoadingQuestion;
  String? get error => _error;
  String? get attemptError => _attemptError;

  ScoreEntity? myScore(String userId) {
    try {
      return _scores.firstWhere((s) => s.studentId == userId);
    } catch (_) {
      return null;
    }
  }

  // ── Seleção de disciplina ───────────────────────────────────────────────────

  Future<void> loadCourses(UserEntity user) async {
    _isLoadingCourses = true;
    _error = null;
    notifyListeners();
    try {
      _courses = await _quizRepo.getCourses(user);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingCourses = false;
      notifyListeners();
    }
  }

  void selectCourse(UserEntity user, int courseId) {
    stopPolling();
    _selectedCourseId = courseId;
    _hasActivity = null;
    _lastSeenSlot = 0;
    _quizState = QuizStateEntity.empty();
    _currentQuestion = null;
    _scores = [];
    _error = null;
    _attemptError = null;
    _selectedAnswers = {};
    _selectedChoiceText = null;
    _lastAnswerCorrect = false;
    _lastAnswerGraded = true;
    notifyListeners();
    _checkAndStartPolling(user);
  }

  Future<void> _checkAndStartPolling(UserEntity user) async {
    final courseId = _selectedCourseId;
    if (courseId == null) return;
    try {
      await _quizRepo.getQuizState(user, courseId);
      _hasActivity = true;
      notifyListeners();
      startPolling(user);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('mq_state') || msg.contains('não encontrada')) {
        _hasActivity = false;
      } else {
        _hasActivity = null;
        _error = msg;
      }
      notifyListeners();
    }
  }

  // ── Ciclo de tentativa ─────────────────────────────────────────────────────

  Future<void> ensureAttempt(UserEntity user, int quizId) async {
    if (_attemptId != null && _currentQuizId == quizId) return;
    try {
      _attemptId = await _quizRepo.startAttempt(user, quizId);
      _currentQuizId = quizId;
      _attemptError = null;
    } catch (e) {
      _attemptError = e.toString();
    }
  }

  Future<void> finishAttempt(UserEntity user) async {
    final id = _attemptId;
    if (id == null) return;
    try {
      await _quizRepo.finishAttempt(user, id);
      _attemptId = null;
      _currentQuizId = null;
      _currentQuestion = null;
    } catch (_) {}
  }

  // ── Resposta ───────────────────────────────────────────────────────────────

  /// Registra uma resposta para um campo específico.
  /// Unificado para todos os tipos:
  ///   - multichoice: selectAnswer(q.inputBaseName, choiceValue)
  ///   - match:       selectAnswer(subQuestion.inputName, selectedValue)
  ///   - numerical:   selectAnswer(q.answerInputName, typedText)
  ///   - gapselect:   selectAnswer(gapInputName, selectedValue)
  void selectAnswer(String inputName, String value) {
    if (_hasAnswered || !_quizState.isActive) return;
    if (value.isEmpty) {
      _selectedAnswers.remove(inputName);
    } else {
      _selectedAnswers[inputName] = value;
    }

    // Atualiza texto legível para exibição no feedback pós-resposta
    final q = _currentQuestion;
    if (q != null) {
      if (q.isMultiChoice && inputName == q.inputBaseName) {
        try {
          _selectedChoiceText =
              q.choices.firstWhere((c) => c.value == value).text;
        } catch (_) {
          _selectedChoiceText = value;
        }
      } else if (q.isNumerical || q.isShortAnswer) {
        _selectedChoiceText = value;
      } else if (q.isMatch) {
        _selectedChoiceText = 'Associação enviada';
      } else if (q.isGapSelect || q.isDdwtos) {
        _selectedChoiceText = 'Lacunas preenchidas';
      } else {
        _selectedChoiceText = 'Resposta registrada';
      }
    }
    notifyListeners();
  }

  /// Retrocompatibilidade: para multichoice usa selectAnswer com inputBaseName.
  void selectChoice(String value) {
    final inputName = _currentQuestion?.inputBaseName ?? '';
    if (inputName.isEmpty) return;
    selectAnswer(inputName, value);
  }

  Future<void> submitAnswer(UserEntity user) async {
    final dlog = DebugLogger.instance;
    final q = _currentQuestion;
    final id = _attemptId;
    final courseId = _selectedCourseId;

    if (q == null ||
        id == null ||
        _hasAnswered ||
        _isSubmitting ||
        courseId == null ||
        _selectedAnswers.isEmpty) {
      dlog.log('STUDENT', 'submitAnswer cancelado — pré-condição falhou',
          data: {
            'question': q != null ? 'slot=${q.slot}' : 'null',
            'attemptId': id,
            'hasAnswered': _hasAnswered,
            'isSubmitting': _isSubmitting,
            'courseId': courseId,
            'answersEmpty': _selectedAnswers.isEmpty,
          });
      return;
    }

    _isSubmitting = true;
    notifyListeners();
    try {
      final wasTimerPending = _quizState.isTimerPending;
      final bonus = wasTimerPending
          ? _quizState.durationSeconds * 10
          : _quizState.secondsRemaining * 10;
      final baseScore = 1000 + bonus;

      dlog.separator('STUDENT SUBMIT');
      dlog.log('STUDENT', 'Submetendo resposta', data: {
        'attemptId': id,
        'slot': q.slot,
        'page': q.page,
        'type': q.type,
        'answers': _selectedAnswers.toString(),
        'timerWasPending': wasTimerPending,
        'timeBonus': bonus,
        'baseScore': baseScore,
      });

      final correct =
          await _quizRepo.submitPage(user, id, q, Map.from(_selectedAnswers));

      dlog.log(
          'STUDENT', '★ Resultado: ${correct ? "CORRETO ✓" : "INCORRETO ✗"}',
          data: {'score_a_registrar': correct ? baseScore : 0});

      await _quizRepo.submitScore(
        user: user,
        courseId: courseId,
        score: correct ? baseScore : 0,
        correct: correct,
        page: q.page,
      );

      _lastAnswerCorrect = correct;
      _lastAnswerGraded = !q.isEssay;
      _hasAnswered = true;
    } catch (e) {
      dlog.log('STUDENT', '✗ ERRO ao submeter: $e');
      _error = e.toString();
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  // ── Polling ────────────────────────────────────────────────────────────────

  void startPolling(UserEntity user) {
    _pollTimer?.cancel();
    _refreshState(user);
    _pollTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _refreshState(user));
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ── Privado ────────────────────────────────────────────────────────────────

  Future<void> _refreshState(UserEntity user) async {
    final courseId = _selectedCourseId;
    if (courseId == null) return;
    if (_isRefreshingState) return;
    _isRefreshingState = true;
    final dlog = DebugLogger.instance;
    try {
      final newState = await _quizRepo.getQuizState(user, courseId);
      dlog.log('STUDENT_POLL', 'estado lido', data: {
        'status': newState.status.name,
        'slot': newState.currentSlot,
        'page': newState.currentPage,
        'quizId': newState.quizId,
        'lastSeenSlot': _lastSeenSlot,
        'attemptId': _attemptId,
        'hasQuestion': _currentQuestion != null,
      });

      _quizState = newState;

      if (newState.isWaiting && _lastSeenSlot > 0) {
        dlog.log('STUDENT_POLL', 'reset detectado (voltou para waiting)');
        _lastSeenSlot = 0;
        _selectedAnswers = {};
        _selectedChoiceText = null;
        _hasAnswered = false;
        _lastAnswerCorrect = false;
        _lastAnswerGraded = true;
        _autoSubmitted = false;
        _currentQuestion = null;
        _attemptId = null;
        _currentQuizId = null;
        _attemptError = null;
        _scores = [];
      }

      if (newState.isActive && newState.currentSlot != _lastSeenSlot) {
        dlog.log('STUDENT_POLL', '★ NOVA QUESTÃO LIBERADA', data: {
          'slot': newState.currentSlot,
          'quizId': newState.quizId,
        });
        _lastSeenSlot = newState.currentSlot;
        _selectedAnswers = {};
        _selectedChoiceText = null;
        _hasAnswered = false;
        _lastAnswerCorrect = false;
        _lastAnswerGraded = true;
        _autoSubmitted = false;
        _currentQuestion = null;

        if (newState.quizId > 0) {
          await ensureAttempt(user, newState.quizId);
        }

        final id = _attemptId;
        if (id != null && newState.currentSlot > 0) {
          _isLoadingQuestion = true;
          notifyListeners();
          try {
            _currentQuestion =
                await _quizRepo.getQuestion(user, id, newState.currentSlot);
            _error = null;
          } catch (e) {
            _error = e.toString();
            dlog.log('STUDENT_POLL', '✗ ERRO ao carregar questão: $e');
          } finally {
            _isLoadingQuestion = false;
          }
        }
      }

      // Retry: questão não carregada no ciclo anterior
      if (newState.isActive &&
          newState.currentSlot == _lastSeenSlot &&
          _currentQuestion == null &&
          !_isLoadingQuestion) {
        if (_attemptId == null && newState.quizId > 0) {
          await ensureAttempt(user, newState.quizId);
        }
        final id = _attemptId;
        if (id != null && newState.currentSlot > 0) {
          _isLoadingQuestion = true;
          notifyListeners();
          try {
            _currentQuestion =
                await _quizRepo.getQuestion(user, id, newState.currentSlot);
            _error = null;
          } catch (e) {
            _error = e.toString();
          } finally {
            _isLoadingQuestion = false;
          }
        }
      }

      // Auto-submit quando timer expirar e houver resposta parcial
      if (newState.isClosed &&
          !_hasAnswered &&
          !_isSubmitting &&
          !_autoSubmitted &&
          _selectedAnswers.isNotEmpty) {
        _autoSubmitted = true;
        await submitAnswer(user);
      }

      if (newState.isFinished && _attemptId != null) {
        await finishAttempt(user);
      }

      try {
        _scores = await _quizRepo.getScores(user, courseId);
      } catch (e) {
        dlog.log('STUDENT_POLL', 'getScores falhou: $e');
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      dlog.log('STUDENT_POLL', '✗ ERRO no polling: $e');
      notifyListeners();
    } finally {
      _isRefreshingState = false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
