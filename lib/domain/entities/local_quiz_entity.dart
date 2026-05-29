import 'package:equatable/equatable.dart';

import 'question_entity.dart';

/// Quiz armazenado localmente com suas questões já parseadas.
class LocalQuizEntity extends Equatable {
  final int id;
  final String name;
  final List<QuestionEntity> questions;

  const LocalQuizEntity({
    required this.id,
    required this.name,
    this.questions = const [],
  });

  int get totalQuestions => questions.length;

  @override
  List<Object?> get props => [id, name];
}
