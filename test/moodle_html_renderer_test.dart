import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_quiz_live/presentation/widgets/moodle_html_renderer.dart';

void main() {
  testWidgets('renders Moodle TeX images as equations', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MoodleHtmlRenderer(
            html:
                r'<p>Use <img class="texrender" alt="\rho=1000\,kg/m^3" src="broken.png"> e <img alt="g=9,81\,m/s^2" src="/filter/tex/pix.php/abc.png"></p>',
            textStyle: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsNWidgets(2));
    expect(find.textContaining('não carregada'), findsNothing);
  });

  testWidgets('repairs Moodle TeX with gap markers leaked into img attributes',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MoodleHtmlRenderer(
            html:
                r'\Delta P = <span class=Em branco 1 Questão 3 [1] · Em branco 2 Questão 3 [2] · Em branco 3 Questão 3 [3] " alt="\Delta P = Em branco 1 Questão 3 [4] · Em branco 2 Questão 3 [5] · Em branco 3 Questão 3 [6]" src="https://moodle.ufu.br/filter/tex/pix.php/abc.gif" />',
            textStyle: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );

    final renderedText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join(' ');

    expect(renderedText, isNot(contains('src=')));
    expect(renderedText, isNot(contains('<span')));
    expect(renderedText, contains('[1]'));
    expect(renderedText, contains('[2]'));
    expect(renderedText, contains('[3]'));
  });

  testWidgets('repairs parsed span left by malformed Moodle TeX',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MoodleHtmlRenderer(
            html:
                r'\Delta P = <span class="Em" data-b1="[1]" data-b2="[2]" data-b3="[3]" alt="\Delta P = Em branco 1 Questao 3 [4]" src="/filter/tex/pix.php/abc.gif"></span>',
            textStyle: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );

    final renderedText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join(' ');

    expect(renderedText, contains('[1]'));
    expect(renderedText, contains('[2]'));
    expect(renderedText, contains('[3]'));
    expect(renderedText, isNot(contains('[4]')));
  });
}
