import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moodle_quiz_live/core/utils/moodle_html_parser.dart';
import 'package:moodle_quiz_live/domain/entities/question_entity.dart';
import 'package:moodle_quiz_live/presentation/widgets/question_engine_widget.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('gap prompt falls back to displayHtml when htmlText is empty',
      (tester) async {
    const optionHtml = '''
      <option value="0">Escolha...</option>
      <option value="1">rho</option>
    ''';
    const question = QuestionEntity(
      slot: 3,
      page: 0,
      text: '',
      htmlText: '<div></div>',
      displayHtml:
          '<div class="qtext">Enunciado recuperado <select name="q42:3_p1">$optionHtml</select>.</div>',
      choices: [],
      inputBaseName: 'q42:3_p',
      seqCheck: '1',
      type: 'gapselect',
      gapInputData: GapInputData(
        gapCount: 1,
        inputNamePrefix: 'q42:3_p',
        options: [ParsedChoice(value: '1', text: 'rho')],
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QuestionEngineWidget(
            question: question,
            mode: QuestionEngineMode.preview,
            compact: true,
          ),
        ),
      ),
    );

    final renderedText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join(' ');

    expect(renderedText, contains('Enunciado recuperado'));
    expect(renderedText, contains('[1]'));
  });

  testWidgets('inline gap dropdown shows the selected option text',
      (tester) async {
    const question = QuestionEntity(
      slot: 7,
      page: 0,
      text: '',
      htmlText:
          '<p>Fluxo: 1. Coletar -> <select name="q0:7_p1"><option value="0"></option><option value="1">eliminar erros grosseiros</option></select>.</p>',
      displayHtml: '',
      choices: [],
      inputBaseName: 'q0:7_answer',
      seqCheck: '1',
      type: 'ddwtos',
      gapInputData: GapInputData(
        gapCount: 1,
        inputNamePrefix: 'q0:7_p',
        options: [
          ParsedChoice(value: '1', text: 'eliminar erros grosseiros'),
          ParsedChoice(value: '2', text: 'corrigir erro sistematico'),
        ],
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QuestionEngineWidget(
            question: question,
            mode: QuestionEngineMode.answer,
            selectedAnswers: {'q0:7_p1': '1'},
            compact: true,
          ),
        ),
      ),
    );

    expect(find.text('eliminar erros grosseiros'), findsOneWidget);
  });

  testWidgets('inline gap prompt renders latex equations', (tester) async {
    const question = QuestionEntity(
      slot: 12,
      page: 0,
      text: '',
      htmlText:
          r'<p>Complete: no modelo \(y=f(x_1,x_2,...,x_n)\), coeficiente [[1]].</p>',
      displayHtml: '',
      choices: [],
      inputBaseName: 'q0:12_answer',
      seqCheck: '1',
      type: 'gapselect',
      gapInputData: GapInputData(
        gapCount: 1,
        inputNamePrefix: 'q0:12_p',
        options: [ParsedChoice(value: '1', text: 'derivada parcial')],
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QuestionEngineWidget(
            question: question,
            mode: QuestionEngineMode.answer,
            compact: true,
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('ordering question can move items up and down', (tester) async {
    const options = [
      ParsedChoice(value: '1', text: '1'),
      ParsedChoice(value: '2', text: '2'),
      ParsedChoice(value: '3', text: '3'),
    ];
    const question = QuestionEntity(
      slot: 8,
      page: 0,
      text: 'Ordene',
      htmlText: '<p>Ordene</p>',
      displayHtml: '',
      choices: [],
      inputBaseName: 'q0:8_answer',
      seqCheck: '1',
      type: 'ordering',
      answerControls: [
        MoodleAnswerControl(
          name: 'q0:8_answer0',
          type: 'select',
          label: 'A',
          options: options,
        ),
        MoodleAnswerControl(
          name: 'q0:8_answer1',
          type: 'select',
          label: 'B',
          options: options,
        ),
        MoodleAnswerControl(
          name: 'q0:8_answer2',
          type: 'select',
          label: 'C',
          options: options,
        ),
      ],
    );
    var selected = <String, String>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => QuestionEngineWidget(
              question: question,
              mode: QuestionEngineMode.answer,
              selectedAnswers: selected,
              compact: true,
              onSelectAnswer: (name, value) {
                setState(() {
                  selected = {...selected, name: value};
                });
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Descer').first);
    await tester.pumpAndSettle();

    expect(selected['q0:8_answer0'], '2');
    expect(selected['q0:8_answer1'], '1');
    expect(tester.getTopLeft(find.text('B')).dy,
        lessThan(tester.getTopLeft(find.text('A')).dy));
  });
}
