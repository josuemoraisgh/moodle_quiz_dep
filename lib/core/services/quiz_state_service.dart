import 'package:flutter/foundation.dart';

import '../../domain/entities/question_entity.dart';
import '../../domain/entities/quiz_state_entity.dart';
import '../../domain/entities/score_entity.dart';

/// ChangeNotifier compartilhado entre ProfessorController e StudentController.
/// É a única fonte de verdade do estado ao vivo do quiz no processo local.
class QuizStateService extends ChangeNotifier {
  QuizStateEntity _quizState = QuizStateEntity.empty();
  QuestionEntity? _currentQuestion;
  List<ScoreEntity> _scores = [];

  QuizStateEntity get quizState => _quizState;
  QuestionEntity? get currentQuestion => _currentQuestion;
  List<ScoreEntity> get scores => List.unmodifiable(_scores);

  void updateState({
    required QuizStateEntity state,
    QuestionEntity? question,
  }) {
    _quizState = state;
    if (question != null) _currentQuestion = question;
    if (state.isWaiting) _currentQuestion = null;
    notifyListeners();
  }

  void updateScores(List<ScoreEntity> scores) {
    _scores = scores;
    notifyListeners();
  }

  void reset() {
    _quizState = QuizStateEntity.empty();
    _currentQuestion = null;
    _scores = [];
    notifyListeners();
  }
}
