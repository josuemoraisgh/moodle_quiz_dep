import 'dart:typed_data';

import '../../core/services/quiz_state_service.dart';
import '../../core/utils/moodle_xml_quiz_parser.dart';
import '../../data/datasources/local_datasource.dart';
import '../../domain/entities/answer_record_entity.dart';
import '../../domain/entities/local_quiz_entity.dart';
import '../../domain/entities/local_user_entity.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/quiz_state_entity.dart';
import '../../domain/entities/score_entity.dart';
import '../../domain/entities/student_entity.dart';

/// Repositório local de quiz – SQLite como fonte de verdade, sem rede externa.
/// Usado pelo [ProfessorController] e pelo [StudentController].
class LocalQuizRepository {
  final LocalDatasource _db;
  final QuizStateService _stateService;

  int? _sessionId;
  Map<String, int> _prevRanks = {};

  LocalQuizRepository(this._db, this._stateService);

  int? get currentSessionId => _sessionId;

  // ── Quizzes ────────────────────────────────────────────────────────────────

  Future<List<LocalQuizEntity>> loadQuizzes() => _db.loadQuizzes();

  Future<List<StudentEntity>> loadStudents() => _db.loadStudents();

  Future<LocalQuizEntity> saveQuiz(
          String name, List<QuestionEntity> questions) =>
      _db.saveQuiz(name, questions);

  Future<LocalQuizEntity?> loadQuizWithQuestions(int quizId) =>
      _db.loadQuizWithQuestions(quizId);

  Future<void> deleteQuiz(int quizId) => _db.deleteQuiz(quizId);

  Future<LocalQuizEntity> importFromXml(
      Uint8List bytes, String fileName) async {
    final questions =
        MoodleXmlQuizParser.parseQuestions(bytes, token: '', baseUrl: '');
    return _db.saveQuiz(fileName, questions);
  }

  // ── Sessão ─────────────────────────────────────────────────────────────────

  Future<QuizStateEntity> openSession(LocalQuizEntity quiz) async {
    _sessionId = await _db.getLatestSessionId(quiz.id);
    _sessionId ??= await _db.createSession(quiz.id, quiz.name);
    final state = await _db.getSessionState(_sessionId!);
    return state ?? QuizStateEntity.empty();
  }

  Future<void> updateState(QuizStateEntity state) async {
    if (_sessionId == null) return;
    await _db.updateSession(_sessionId!, state);
  }

  Future<QuizStateEntity> resetSession(int quizId, String quizTitle) async {
    if (_sessionId != null) await _db.deleteSessionAnswers(_sessionId!);
    _sessionId = await _db.createSession(quizId, quizTitle);
    _prevRanks = {};
    return QuizStateEntity.empty();
  }

  // ── Pontuações ─────────────────────────────────────────────────────────────

  Future<List<ScoreEntity>> loadScores() async {
    final id = _sessionId;
    if (id == null) return [];
    final raw = await _db.loadScores(id);
    final withRanks = raw.asMap().entries.map((e) {
      final prev = _prevRanks[e.value.studentId];
      return ScoreEntity(
        studentId: e.value.studentId,
        studentName: e.value.studentName,
        score: e.value.score,
        correctCount: e.value.correctCount,
        totalAnswered: e.value.totalAnswered,
        rank: e.key + 1,
        answeredPages: e.value.answeredPages,
        answeredPageRounds: e.value.answeredPageRounds,
        previousRank: prev,
      );
    }).toList();
    _prevRanks = {for (final s in withRanks) s.studentId: s.rank};
    _stateService.updateScores(withRanks);
    return withRanks;
  }

  // ── Resposta (modo local – mesmo dispositivo) ──────────────────────────────

  Future<bool> submitAnswer({
    required LocalUserEntity user,
    required QuestionEntity question,
    required Map<String, String> answers,
    required String roundId,
    required int score,
  }) async {
    final sid = _sessionId;
    if (sid == null) return false;
    if (await _db.hasStudentAnswered(sid, user.id, question.slot, roundId)) {
      return false;
    }
    final correct = _grade(question, answers);
    await _db.saveAnswer(AnswerRecordEntity(
      id: 0,
      sessionId: sid,
      studentId: user.id,
      studentName: user.name,
      questionSlot: question.slot,
      roundId: roundId,
      answerData: answers,
      isCorrect: correct,
      score: correct ? score : 0,
      answeredAt: DateTime.now(),
    ));
    return correct;
  }

  /// Persiste resposta de aluno remoto (chegou via Wi-Fi → POST /api/score).
  Future<void> saveRemoteAnswer(Map<String, dynamic> body) async {
    final sid = _sessionId;
    if (sid == null) return;
    final studentId =
        int.tryParse(body['studentId']?.toString() ?? '0') ?? 0;
    final studentName = body['studentName'] as String? ?? 'Desconhecido';
    final slot = (body['questionSlot'] as num?)?.toInt() ?? 0;
    final roundId = body['roundId'] as String? ?? '';
    final isCorrect = body['isCorrect'] as bool? ?? false;
    final score = (body['score'] as num?)?.toInt() ?? 0;
    final rawA = (body['answers'] as Map?) ?? {};
    final answers = rawA.map((k, v) => MapEntry(k.toString(), v.toString()));
    if (await _db.hasStudentAnswered(sid, studentId, slot, roundId)) return;
    await _db.saveAnswer(AnswerRecordEntity(
      id: 0,
      sessionId: sid,
      studentId: studentId,
      studentName: studentName,
      questionSlot: slot,
      roundId: roundId,
      answerData: answers,
      isCorrect: isCorrect,
      score: score,
      answeredAt: DateTime.now(),
    ));
  }

  // ── Avaliação local ────────────────────────────────────────────────────────

  static bool _grade(QuestionEntity q, Map<String, String> answers) {
    if (answers.isEmpty) return false;

    if (q.isMultiChoice) {
      final selected = answers[q.inputBaseName];
      if (selected == null) return false;
      try {
        return q.choices.firstWhere((c) => c.value == selected).isCorrect;
      } catch (_) {
        return false;
      }
    }

    if (q.isMatch) {
      final match = q.matchData;
      if (match == null) return false;
      return match.subQuestions.every((sub) =>
          answers[sub.inputName] != null &&
          answers[sub.inputName] == sub.correctValue);
    }

    if (q.isGapSelect || q.isDdwtos) {
      final gap = q.gapInputData;
      if (gap == null) return false;
      for (var i = 1; i <= gap.gapCount; i++) {
        final selected = answers[gap.inputName(i)];
        if (selected == null || selected == '0' || selected.isEmpty) {
          return false;
        }
        final opts = gap.optionsForGap(i);
        final idx = (int.tryParse(selected) ?? 0) - 1;
        if (idx < 0 || idx >= opts.length || !opts[idx].isCorrect) {
          return false;
        }
      }
      return true;
    }

    if (q.isNumerical || q.isShortAnswer) {
      final inputName = q.answerInputName ?? q.inputBaseName;
      final typed = (answers[inputName] ?? '').trim().toLowerCase();
      if (typed.isEmpty) return false;
      return q.choices
          .any((c) => c.isCorrect && c.text.trim().toLowerCase() == typed);
    }

    if (q.isEssay) {
      final inputName = q.answerInputName ?? q.inputBaseName;
      return answers[inputName]?.trim().isNotEmpty ?? false;
    }

    return false;
  }
}
