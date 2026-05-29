import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_quiz_live/core/utils/moodle_xml_quiz_parser.dart';

void main() {
  test('parses Moodle XML export into the shared question engine model', () {
    final bytes = File('questoes_erros_incertezas_moodle.xml').readAsBytesSync();

    final questions = MoodleXmlQuizParser.parseQuestions(bytes);

    expect(questions.length, greaterThan(10));

    final multichoice = questions.firstWhere((q) => q.type == 'multichoice');
    expect(multichoice.choices, hasLength(4));
    expect(multichoice.choices.where((c) => c.isCorrect), hasLength(1));

    final match = questions.firstWhere((q) => q.type == 'match');
    expect(match.matchData?.subQuestions, isNotEmpty);
    expect(match.matchData?.subQuestions.first.correctValue, '1');

    final ordering = questions.firstWhere((q) => q.type == 'ordering');
    expect(ordering.answerControls.where((c) => c.isSelect), hasLength(8));
    expect(ordering.displayHtml, isNot(contains('<li>')));

    final gapselect = questions.firstWhere((q) => q.type == 'gapselect');
    expect(gapselect.gapInputData?.gapCount, 4);
    expect(gapselect.answerControls.where((c) => c.isSelect), hasLength(4));

    final ddwtos = questions.firstWhere((q) => q.type == 'ddwtos');
    expect(ddwtos.gapInputData?.gapCount, 4);
    expect(ddwtos.answerControls.where((c) => c.isSelect), hasLength(4));
    expect(ddwtos.gapInputData?.options, hasLength(6));
    expect(
      List.generate(
        4,
        (index) => ddwtos.gapInputData!
            .optionsForGap(index + 1)
            .map((o) => o.value)
            .toList(),
      ),
      everyElement(['1', '2', '3', '4', '5', '6']),
    );
    expect(
      ddwtos.rightAnswerHtml,
      allOf(
        contains('[1] eliminar erros grosseiros'),
        contains('[4] expandir por k'),
        isNot(contains('[5] aumentar o bias')),
      ),
    );
  });
}
