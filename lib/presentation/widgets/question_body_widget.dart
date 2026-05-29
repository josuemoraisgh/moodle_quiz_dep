import 'package:flutter/material.dart';

import '../../domain/entities/question_entity.dart';
import 'question_engine_widget.dart';

class QuestionBodyWidget extends StatelessWidget {
  final QuestionEntity question;
  final bool showCorrect;
  final bool compact;

  const QuestionBodyWidget({
    super.key,
    required this.question,
    this.showCorrect = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return QuestionEngineWidget(
      question: question,
      mode: QuestionEngineMode.preview,
      showCorrect: showCorrect,
      compact: compact,
    );
  }
}
