import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/quiz_state_service.dart';
import '../../core/utils/moodle_html_parser.dart' show ParsedChoice;
import '../../data/datasources/offline_local_client.dart';
import '../../data/repositories/local_quiz_repository_impl.dart';
import '../../domain/entities/local_user_entity.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/quiz_state_entity.dart';
import '../../domain/entities/score_entity.dart';

/// Gerencia estado do aluno – sem rede externa, reage ao QuizStateService.
///
/// Modo local (mesmo dispositivo que o professor):
///   - Lê o estado do QuizStateService (memória compartilhada).
///   - Persiste resposta via LocalQuizRepository (SQLite).
///
/// Modo cliente Wi-Fi (dispositivo diferente do professor):
///   - Faz polling do servidor local do professor via OfflineLocalClient.
class StudentController extends ChangeNotifier {
  final LocalQuizRepository _quizRepo;
  final QuizStateService _stateService;

  OfflineLocalClient? _client;
  LocalUserEntity? _user;

  Map<String, String> _selectedAnswers = {};
  String? _selectedChoiceText;
  bool _hasAnswered = false;
  bool _isSubmitting = false;
  bool _lastAnswerCorrect = false;
  bool _lastAnswerGraded = true;
  bool _autoSubmitted = false;
  int _lastSeenSlot = 0;
  String? _error;

  Timer? _pollTimer;
  bool _isPolling = false;

  StudentController({
    required LocalQuizRepository quizRepo,
    required QuizStateService stateService,
  })  : _quizRepo = quizRepo,
        _stateService = stateService;

  // ── Getters ────────────────────────────────────────────────────────────────
  QuizStateEntity get quizState => _stateService.quizState;
  QuestionEntity? get currentQuestion => _stateService.currentQuestion;
  List<ScoreEntity> get scores => _stateService.scores;
  Map<String, String> get selectedAnswers => Map.unmodifiable(_selectedAnswers);
  bool get hasAnyAnswer => _selectedAnswers.isNotEmpty;
  String? get selectedChoiceText => _selectedChoiceText;
  bool get hasAnswered => _hasAnswered;
  bool get isSubmitting => _isSubmitting;
  bool get lastAnswerCorrect => _lastAnswerCorrect;
  bool get lastAnswerGraded => _lastAnswerGraded;
  String? get error => _error;
  bool get isClientMode => _client != null;

  // ── Inicialização ──────────────────────────────────────────────────────────

  /// Modo local – professor e aluno no mesmo processo.
  void initLocal(LocalUserEntity user) {
    _user = user;
    _client = null;
    _pollTimer?.cancel();
    _stateService.addListener(_onStateChanged);
  }

  /// Modo Wi-Fi – aluno num dispositivo separado.
  void initClient(LocalUserEntity user, String serverUrl) {
    _user = user;
    _client = OfflineLocalClient(serverUrl: serverUrl);
    _stateService.removeListener(_onStateChanged);
    _startPolling();
  }

  // ── Reação ao estado (modo local) ─────────────────────────────────────────

  void _onStateChanged() {
    _handleStateTransition(_stateService.quizState);
    notifyListeners();
  }

  void _handleStateTransition(QuizStateEntity state) {
    if (state.isWaiting && _lastSeenSlot > 0) {
      _resetForNewRound();
      return;
    }
    if (state.isActive && state.currentSlot != _lastSeenSlot) {
      _lastSeenSlot = state.currentSlot;
      _resetAnswerState();
    }
    if (state.isClosed &&
        !_hasAnswered &&
        !_autoSubmitted &&
        _selectedAnswers.isNotEmpty) {
      _autoSubmitted = true;
      _submitLocal();
    }
  }

  // ── Polling (modo Wi-Fi) ──────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _pollRemote());
  }

  Future<void> _pollRemote() async {
    final client = _client;
    if (client == null || _isPolling) return;
    _isPolling = true;
    try {
      final state = await client.getState();
      _stateService.updateState(state: state);
      _handleStateTransition(state);

      if (state.isActive &&
          state.currentSlot != 0 &&
          _stateService.currentQuestion?.slot != state.currentSlot) {
        final qMap = await client.getQuestion(state.currentSlot);
        _stateService.updateState(
            state: state, question: _mapToQuestion(qMap));
      }

      final sc = await client.getScores();
      _stateService.updateScores(sc);
      _error = null;
    } catch (e) {
      _error = 'Sem conexão com o professor: $e';
    } finally {
      _isPolling = false;
      notifyListeners();
    }
  }

  QuestionEntity _mapToQuestion(Map<String, dynamic> m) {
    final choices = (m['choices'] as List<dynamic>? ?? []).map((c) {
      final cm = c as Map<String, dynamic>;
      return ParsedChoice(
        value: cm['value'] as String? ?? '',
        text: cm['text'] as String? ?? '',
        htmlText: cm['htmlText'] as String? ?? '',
        isCorrect: cm['isCorrect'] as bool? ?? false,
      );
    }).toList();

    return QuestionEntity(
      slot: (m['slot'] as num?)?.toInt() ?? 0,
      page: (m['page'] as num?)?.toInt() ?? 0,
      text: m['text'] as String? ?? '',
      htmlText: m['htmlText'] as String? ?? '',
      type: m['type'] as String? ?? 'multichoice',
      generalFeedback: m['generalFeedback'] as String? ?? '',
      inputBaseName: m['inputBaseName'] as String? ?? '',
      seqCheck: m['seqCheck'] as String? ?? '',
      answerInputName: m['answerInputName'] as String?,
      choices: choices,
    );
  }

  // ── Resposta ───────────────────────────────────────────────────────────────

  void selectAnswer(String inputName, String value) {
    if (_hasAnswered || !quizState.isActive) return;
    if (value.isEmpty) {
      _selectedAnswers.remove(inputName);
    } else {
      _selectedAnswers[inputName] = value;
    }
    final q = currentQuestion;
    if (q != null) {
      if (q.isMultiChoice && inputName == q.inputBaseName) {
        try {
          _selectedChoiceText =
              q.choices.firstWhere((c) => c.value == value).text;
        } catch (_) {
          _selectedChoiceText = value;
        }
      } else {
        _selectedChoiceText = 'Resposta registrada';
      }
    }
    notifyListeners();
  }

  Future<void> submitAnswer() async {
    final user = _user;
    final q = currentQuestion;
    if (user == null ||
        q == null ||
        _hasAnswered ||
        _isSubmitting ||
        _selectedAnswers.isEmpty) {
      return;
    }

    _isSubmitting = true;
    notifyListeners();
    try {
      if (_client != null) {
        await _submitRemote(user, q);
      } else {
        await _submitLocal();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> _submitLocal() async {
    final user = _user;
    final q = currentQuestion;
    if (user == null || q == null) return;
    final state = quizState;
    final bonus = state.isTimerPending
        ? state.durationSeconds * 10
        : state.secondsRemaining * 10;
    final correct = await _quizRepo.submitAnswer(
      user: user,
      question: q,
      answers: Map.from(_selectedAnswers),
      roundId: state.roundId,
      score: 1000 + bonus,
    );
    _lastAnswerCorrect = correct;
    _lastAnswerGraded = !q.isEssay;
    _hasAnswered = true;
  }

  Future<void> _submitRemote(LocalUserEntity user, QuestionEntity q) async {
    final client = _client!;
    final state = quizState;
    final bonus = state.isTimerPending
        ? state.durationSeconds * 10
        : state.secondsRemaining * 10;
    bool correct = false;
    if (q.isMultiChoice) {
      final idx = int.tryParse(_selectedAnswers[q.inputBaseName] ?? '');
      correct =
          idx != null && idx < q.choices.length && q.choices[idx].isCorrect;
    }
    await client.submitScore(
      studentId: user.id.toString(),
      studentName: user.name,
      questionSlot: q.slot,
      roundId: state.roundId,
      answers: Map.from(_selectedAnswers),
      isCorrect: correct,
      score: correct ? 1000 + bonus : 0,
    );
    _lastAnswerCorrect = correct;
    _lastAnswerGraded = !q.isEssay;
    _hasAnswered = true;
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  void _resetForNewRound() {
    _lastSeenSlot = 0;
    _resetAnswerState();
  }

  void _resetAnswerState() {
    _selectedAnswers = {};
    _selectedChoiceText = null;
    _hasAnswered = false;
    _lastAnswerCorrect = false;
    _lastAnswerGraded = true;
    _autoSubmitted = false;
    _error = null;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _stateService.removeListener(_onStateChanged);
    _pollTimer?.cancel();
    super.dispose();
  }
}
