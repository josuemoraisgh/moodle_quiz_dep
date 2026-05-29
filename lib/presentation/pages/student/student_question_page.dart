import 'package:flutter/material.dart';

import '../../../core/utils/responsive.dart';
import '../../../domain/entities/question_entity.dart';
import '../../widgets/question_engine_widget.dart';

class StudentQuestionPage extends StatelessWidget {
  final QuestionEntity question;
  final DateTime? endsAt;
  final Map<String, String> selectedAnswers;
  final bool hasAnswered;
  final bool isSubmitting;
  final void Function(String inputName, String value) onSelectAnswer;
  final VoidCallback onSubmit;

  const StudentQuestionPage({
    super.key,
    required this.question,
    required this.endsAt,
    required this.selectedAnswers,
    required this.hasAnswered,
    required this.isSubmitting,
    required this.onSelectAnswer,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding:
          Responsive.horizontalPadding(context).copyWith(top: 12, bottom: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: QuestionEngineWidget(
            question: question,
            mode: QuestionEngineMode.answer,
            endsAt: endsAt,
            selectedAnswers: selectedAnswers,
            hasAnswered: hasAnswered,
            isSubmitting: isSubmitting,
            onSelectAnswer: onSelectAnswer,
            onSubmit: onSubmit,
          ),
        ),
      ),
    );
  }
}
