import 'dart:typed_data';

import '../../core/config/quiz_runtime_config.dart';
import '../entities/local_quiz_entity.dart';
import '../entities/local_user_entity.dart';
import '../entities/question_entity.dart';
import '../entities/quiz_state_entity.dart';
import '../entities/score_entity.dart';
import '../entities/student_entity.dart';

abstract class IQuizRuntimeRepository {
  QuizOperationMode get operationMode;
  bool get supportsImport;
  bool get supportsDelete;

  Future<void> initialize(LocalUserEntity user);

  Future<List<LocalQuizEntity>> loadQuizzes();
  Future<List<StudentEntity>> loadStudents();
  Future<LocalQuizEntity> saveQuiz(
    String name,
    List<QuestionEntity> questions,
  );
  Future<LocalQuizEntity?> loadQuizWithQuestions(int quizId);
  Future<void> deleteQuiz(int quizId);
  Future<LocalQuizEntity> importFromXml(Uint8List bytes, String fileName);

  Future<QuizStateEntity> openSession(LocalQuizEntity quiz);
  Future<void> updateState(QuizStateEntity state);
  Future<QuizStateEntity> resetSession(int quizId, String quizTitle);

  Future<QuizStateEntity> getLiveState();
  Future<QuestionEntity?> getLiveQuestion(int slot);

  Future<List<ScoreEntity>> loadScores();
  Future<bool> submitAnswer({
    required LocalUserEntity user,
    required QuestionEntity question,
    required Map<String, String> answers,
    required String roundId,
    required int score,
  });
  Future<void> saveRemoteAnswer(Map<String, dynamic> body);
}
