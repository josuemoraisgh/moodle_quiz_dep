import 'dart:typed_data';

import '../../core/config/quiz_runtime_config.dart';
import '../../core/services/quiz_state_service.dart';
import '../../core/utils/moodle_xml_quiz_parser.dart';
import '../../domain/entities/answer_record_entity.dart';
import '../../domain/entities/local_quiz_entity.dart';
import '../../domain/entities/local_user_entity.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/quiz_state_entity.dart';
import '../../domain/entities/score_entity.dart';
import '../../domain/entities/student_entity.dart';
import '../../domain/repositories/i_quiz_runtime_repository.dart';
import 'local_quiz_repository_impl.dart' show LocalQuestionGrader;

class InMemoryQuizRepository implements IQuizRuntimeRepository {
  final QuizStateService _stateService;
  final List<StudentEntity> _students;
  final List<LocalQuizEntity> _quizzes;
  final List<AnswerRecordEntity> _answers = [];

  int _nextQuizId = 1;
  int _sessionId = 1;
  LocalQuizEntity? _selectedQuiz;
  Map<String, int> _prevRanks = {};

  InMemoryQuizRepository({
    required QuizStateService stateService,
    List<StudentEntity> students = const [],
    List<LocalQuizEntity> quizzes = const [],
    List<QuestionEntity> questions = const [],
    String initialQuizName = 'Quiz',
  })  : _stateService = stateService,
        _students = List.of(students),
        _quizzes = List.of(quizzes) {
    for (final quiz in _quizzes) {
      if (quiz.id >= _nextQuizId) _nextQuizId = quiz.id + 1;
    }
    if (questions.isNotEmpty) {
      _quizzes.add(LocalQuizEntity(
        id: _nextQuizId++,
        name: initialQuizName,
        questions: questions,
      ));
    }
  }

  @override
  QuizOperationMode get operationMode => QuizOperationMode.offline;

  @override
  bool get supportsImport => true;

  @override
  bool get supportsDelete => true;

  @override
  Future<void> initialize(LocalUserEntity user) async {}

  @override
  Future<List<LocalQuizEntity>> loadQuizzes() async =>
      List.unmodifiable(_quizzes);

  @override
  Future<List<StudentEntity>> loadStudents() async =>
      List.unmodifiable(_students);

  @override
  Future<LocalQuizEntity> saveQuiz(
    String name,
    List<QuestionEntity> questions,
  ) async {
    final quiz = LocalQuizEntity(
      id: _nextQuizId++,
      name: name,
      questions: questions,
    );
    _quizzes.insert(0, quiz);
    return quiz;
  }

  @override
  Future<LocalQuizEntity?> loadQuizWithQuestions(int quizId) async {
    for (final quiz in _quizzes) {
      if (quiz.id == quizId) return quiz;
    }
    return null;
  }

  @override
  Future<void> deleteQuiz(int quizId) async {
    _quizzes.removeWhere((quiz) => quiz.id == quizId);
  }

  @override
  Future<LocalQuizEntity> importFromXml(
      Uint8List bytes, String fileName) async {
    final questions = MoodleXmlQuizParser.parseQuestions(bytes);
    return saveQuiz(fileName, questions);
  }

  @override
  Future<QuizStateEntity> openSession(LocalQuizEntity quiz) async {
    _selectedQuiz = quiz;
    return _stateService.quizState;
  }

  @override
  Future<void> updateState(QuizStateEntity state) async {
    final question = _questionBySlot(state.currentSlot);
    _stateService.updateState(state: state, question: question);
  }

  @override
  Future<QuizStateEntity> resetSession(int quizId, String quizTitle) async {
    _sessionId++;
    _answers.clear();
    _prevRanks = {};
    _stateService.reset();
    return QuizStateEntity.empty();
  }

  @override
  Future<QuizStateEntity> getLiveState() async => _stateService.quizState;

  @override
  Future<QuestionEntity?> getLiveQuestion(int slot) async {
    final current = _stateService.currentQuestion;
    if (current?.slot == slot) return current;
    return _questionBySlot(slot);
  }

  @override
  Future<List<ScoreEntity>> loadScores() async {
    final byStudent = <int, List<AnswerRecordEntity>>{};
    for (final answer in _answers.where((a) => a.sessionId == _sessionId)) {
      byStudent.putIfAbsent(answer.studentId, () => []).add(answer);
    }
    final scores = byStudent.entries.map((entry) {
      final answers = entry.value;
      final totalScore = answers.fold<int>(0, (sum, a) => sum + a.score);
      final correct = answers.where((a) => a.isCorrect).length;
      final pageRounds = <int, String>{};
      for (final answer in answers) {
        pageRounds[answer.questionSlot] = answer.roundId;
      }
      return ScoreEntity(
        studentId: entry.key.toString(),
        studentName: answers.first.studentName,
        score: totalScore,
        correctCount: correct,
        totalAnswered: answers.length,
        rank: 0,
        answeredPages: pageRounds.keys.toList(),
        answeredPageRounds: pageRounds,
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final ranked = scores.indexed.map((entry) {
      final score = entry.$2;
      return ScoreEntity(
        studentId: score.studentId,
        studentName: score.studentName,
        score: score.score,
        correctCount: score.correctCount,
        totalAnswered: score.totalAnswered,
        rank: entry.$1 + 1,
        answeredPages: score.answeredPages,
        answeredPageRounds: score.answeredPageRounds,
        previousRank: _prevRanks[score.studentId],
      );
    }).toList();
    _prevRanks = {for (final score in ranked) score.studentId: score.rank};
    _stateService.updateScores(ranked);
    return ranked;
  }

  @override
  Future<bool> submitAnswer({
    required LocalUserEntity user,
    required QuestionEntity question,
    required Map<String, String> answers,
    required String roundId,
    required int score,
  }) async {
    final alreadyAnswered = _answers.any(
      (answer) =>
          answer.sessionId == _sessionId &&
          answer.studentId == user.id &&
          answer.questionSlot == question.slot &&
          answer.roundId == roundId,
    );
    if (alreadyAnswered) return false;
    final correct = LocalQuestionGrader.grade(question, answers);
    _answers.add(AnswerRecordEntity(
      id: _answers.length + 1,
      sessionId: _sessionId,
      studentId: user.id,
      studentName: user.name,
      questionSlot: question.slot,
      roundId: roundId,
      answerData: answers,
      isCorrect: correct,
      score: correct ? score : 0,
      answeredAt: DateTime.now(),
    ));
    await loadScores();
    return correct;
  }

  @override
  Future<void> saveRemoteAnswer(Map<String, dynamic> body) async {}

  QuestionEntity? _questionBySlot(int slot) {
    final questions = _selectedQuiz?.questions ?? const <QuestionEntity>[];
    for (final question in questions) {
      if (question.slot == slot) return question;
    }
    return null;
  }
}
