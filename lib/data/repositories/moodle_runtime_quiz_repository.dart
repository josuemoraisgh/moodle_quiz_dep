import 'dart:typed_data';

import '../../core/config/quiz_runtime_config.dart';
import '../../domain/entities/local_quiz_entity.dart';
import '../../domain/entities/local_user_entity.dart';
import '../../domain/entities/moodle_course.dart';
import '../../domain/entities/moodle_quiz.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/quiz_state_entity.dart';
import '../../domain/entities/score_entity.dart';
import '../../domain/entities/student_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/i_quiz_repository.dart';
import '../../domain/repositories/i_quiz_runtime_repository.dart';

class MoodleRuntimeQuizRepository implements IQuizRuntimeRepository {
  final IQuizRepository _moodleQuiz;
  final QuizRuntimeConfig _config;

  UserEntity? _user;
  MoodleCourse? _course;
  MoodleQuiz? _selectedMoodleQuiz;
  LocalQuizEntity? _selectedQuiz;
  int? _teacherAttemptId;
  final Map<int, int> _studentAttempts = {};
  List<MoodleQuiz> _moodleQuizzes = [];

  MoodleRuntimeQuizRepository({
    required IQuizRepository moodleQuiz,
    required QuizRuntimeConfig config,
  })  : _moodleQuiz = moodleQuiz,
        _config = config;

  @override
  QuizOperationMode get operationMode => QuizOperationMode.online;

  @override
  bool get supportsImport => false;

  @override
  bool get supportsDelete => false;

  @override
  Future<void> initialize(LocalUserEntity user) async {
    _user = _toMoodleUser(user);
    await _resolveCourse();
  }

  @override
  Future<List<LocalQuizEntity>> loadQuizzes() async {
    final user = _requireUser();
    final course = await _resolveCourse();
    _moodleQuizzes = await _moodleQuiz.getQuizzesByCourse(user, course.id);
    return _moodleQuizzes
        .map((quiz) => LocalQuizEntity(id: quiz.id, name: quiz.name))
        .toList();
  }

  @override
  Future<List<StudentEntity>> loadStudents() async => const [];

  @override
  Future<LocalQuizEntity> saveQuiz(
    String name,
    List<QuestionEntity> questions,
  ) async {
    throw UnsupportedError(
        'Importacao local nao esta disponivel no modo online.');
  }

  @override
  Future<LocalQuizEntity?> loadQuizWithQuestions(int quizId) async {
    final user = _requireUser();
    final course = await _resolveCourse();
    if (_moodleQuizzes.isEmpty) await loadQuizzes();
    final quiz = _moodleQuizzes.firstWhere(
      (item) => item.id == quizId,
      orElse: () => MoodleQuiz(id: quizId, courseId: course.id, name: 'Quiz'),
    );
    _selectedMoodleQuiz = quiz;
    await _moodleQuiz.setSelectedQuiz(
      user: user,
      courseId: course.id,
      quizId: quiz.id,
      quizName: quiz.name,
    );
    _teacherAttemptId = await _moodleQuiz.startAttempt(user, quiz.id);
    final questions = await _moodleQuiz.loadQuestionsWithAnswers(
      user,
      _teacherAttemptId!,
      0,
    );
    _selectedQuiz = LocalQuizEntity(
      id: quiz.id,
      name: quiz.name,
      questions: questions,
    );
    return _selectedQuiz;
  }

  @override
  Future<void> deleteQuiz(int quizId) async {
    throw UnsupportedError(
        'Exclusao de quiz nao esta disponivel no modo online.');
  }

  @override
  Future<LocalQuizEntity> importFromXml(Uint8List bytes, String fileName) {
    throw UnsupportedError(
        'Importacao XML nao esta disponivel no modo online.');
  }

  @override
  Future<QuizStateEntity> openSession(LocalQuizEntity quiz) async {
    _selectedQuiz = quiz;
    return getLiveState();
  }

  @override
  Future<void> updateState(QuizStateEntity state) async {
    final user = _requireUser();
    final course = await _resolveCourse();
    final quiz = _selectedMoodleQuiz;
    switch (state.status) {
      case QuizStatus.active:
        await _moodleQuiz.releaseQuestion(
          user: user,
          courseId: course.id,
          page: state.currentPage,
          slot: state.currentSlot,
          duration: state.durationSeconds,
          startOnFirstResponse: state.startOnFirstResponse,
          totalPages: state.totalPages,
          quizName: state.quizTitle,
          quizId: quiz?.id ?? state.quizId,
        );
        break;
      case QuizStatus.closed:
        await _moodleQuiz.closeQuestion(user, course.id);
        break;
      case QuizStatus.finished:
        await _moodleQuiz.setFinished(user, course.id);
        break;
      case QuizStatus.waiting:
        await _moodleQuiz.resetQuiz(user, course.id);
        break;
    }
  }

  @override
  Future<QuizStateEntity> resetSession(int quizId, String quizTitle) async {
    final user = _requireUser();
    final course = await _resolveCourse();
    await _moodleQuiz.resetQuiz(user, course.id);
    _studentAttempts.clear();
    return QuizStateEntity.empty();
  }

  @override
  Future<QuizStateEntity> getLiveState() async {
    final user = _requireUser();
    final course = await _resolveCourse();
    return _moodleQuiz.getQuizState(user, course.id);
  }

  @override
  Future<QuestionEntity?> getLiveQuestion(int slot) async {
    final user = _requireUser();
    final state = await getLiveState();
    final attemptId = await _ensureAttempt(user, state.quizId);
    if (attemptId == null) return null;
    return _moodleQuiz.getQuestion(user, attemptId, slot);
  }

  @override
  Future<List<ScoreEntity>> loadScores() async {
    final user = _requireUser();
    final course = await _resolveCourse();
    return _moodleQuiz.getScores(user, course.id);
  }

  @override
  Future<bool> submitAnswer({
    required LocalUserEntity user,
    required QuestionEntity question,
    required Map<String, String> answers,
    required String roundId,
    required int score,
  }) async {
    final moodleUser = _toMoodleUser(user);
    final state = await getLiveState();
    final course = await _resolveCourse();
    final attemptId = await _ensureAttempt(moodleUser, state.quizId);
    if (attemptId == null) return false;
    final correct = await _moodleQuiz.submitPage(
      moodleUser,
      attemptId,
      question,
      answers,
    );
    await _moodleQuiz.submitScore(
      user: moodleUser,
      courseId: course.id,
      score: correct ? score : 0,
      correct: correct,
      page: question.page,
    );
    return correct;
  }

  @override
  Future<void> saveRemoteAnswer(Map<String, dynamic> body) async {}

  Future<int?> _ensureAttempt(UserEntity user, int quizId) async {
    if (quizId <= 0) return null;
    final existing = _studentAttempts[user.id];
    if (existing != null) return existing;
    final attempt = await _moodleQuiz.startAttempt(user, quizId);
    _studentAttempts[user.id] = attempt;
    return attempt;
  }

  Future<MoodleCourse> _resolveCourse() async {
    final user = _requireUser();
    final cached = _course;
    if (cached != null) return cached;
    final courses = await _moodleQuiz.getCourses(user);
    if (courses.isEmpty) {
      throw Exception('Nenhum curso Moodle disponivel para este usuario.');
    }
    if (_config.courseId > 0) {
      for (final course in courses) {
        if (course.id == _config.courseId) {
          _course = course;
          return course;
        }
      }
      throw Exception('Curso Moodle ${_config.courseId} nao encontrado.');
    }
    _course = courses.first;
    return _course!;
  }

  UserEntity _requireUser() {
    final user = _user;
    if (user == null) {
      throw StateError('Repositorio online ainda nao inicializado.');
    }
    return user;
  }

  UserEntity _toMoodleUser(LocalUserEntity user) {
    return UserEntity(
      id: user.id,
      username: user.username.isEmpty ? user.name : user.username,
      fullname: user.name,
      token: user.token,
      baseUrl: user.baseUrl.isEmpty ? _config.moodleBaseUrl : user.baseUrl,
      isTeacher: user.isTeacher,
      availableFunctions: user.availableFunctions,
    );
  }
}
