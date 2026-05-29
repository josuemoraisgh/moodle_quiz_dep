import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_quiz_live/core/utils/moodle_html_parser.dart';

void main() {
  group('MoodleHtmlParser', () {
    test('preserves Moodle images in question text and choices', () {
      const html = '''
<div class="qtext">
  <p>Observe a figura:</p>
  <img src="@@PLUGINFILE@@/question.png" alt="Figura da questão">
</div>
<div class="answer">
  <div class="r0">
    <input type="radio" name="q42:1_answer" value="0" id="q42_1_0" aria-labelledby="q42_1_0_label">
    <div>
      <div id="q42_1_0_label" data-region="answer-label">
        <span class="answernumber">a. </span>
        <p>Alternativa com figura</p>
        <img src="/pluginfile.php/99/answer.png" alt="Figura da alternativa">
      </div>
    </div>
  </div>
</div>
<input type="hidden" name="q42:1_:sequencecheck" value="1">
''';

      final parsed = MoodleHtmlParser.parse(
        html: html,
        attemptId: 42,
        slot: 1,
        token: 'abc123',
        baseUrl: 'https://moodle.example.edu',
      );

      expect(parsed.htmlText,
          contains('webservice/pluginfile.php/question.png?token=abc123'));
      expect(parsed.choices, hasLength(1));
      expect(parsed.choices.single.text, 'Alternativa com figura');
      expect(
          parsed.choices.single.htmlText, contains('Alternativa com figura'));
      expect(
          parsed.choices.single.htmlText,
          contains(
              'https://moodle.example.edu/webservice/pluginfile.php/99/answer.png?token=abc123'));
    });

    test('extracts generic answer controls from Moodle html', () {
      const html = '''
<div class="que multianswer deferredfeedback notyetanswered">
  <div class="qtext">
    <p>Complete os campos:</p>
    <label for="short">Resposta curta</label>
    <input type="text" id="short" name="q42:2_answer" value="">
    <select name="q42:2_sub1">
      <option value="0">Escolha...</option>
      <option value="1">Alpha</option>
      <option value="2">Beta</option>
    </select>
    <label for="essay">Texto</label>
    <textarea id="essay" name="q42:2_answer_text"></textarea>
    <label for="check0">Marcar opcao</label>
    <input type="checkbox" id="check0" name="q42:2_choice0" value="1">
    <span class="questionflag">
      <label for="flag">Marcar questão</label>
      <input type="checkbox" id="flag" name="q42:2_:flagged" value="1">
    </span>
  </div>
  <input type="hidden" name="q42:2_:sequencecheck" value="1">
</div>
''';

      final parsed = MoodleHtmlParser.parse(
        html: html,
        attemptId: 42,
        slot: 2,
        token: 'abc123',
        baseUrl: 'https://moodle.example.edu',
      );

      final controls = {for (final c in parsed.answerControls) c.name: c};
      expect(controls['q42:2_answer']?.type, 'text');
      expect(controls['q42:2_sub1']?.type, 'select');
      expect(controls['q42:2_sub1']?.options.map((o) => o.text),
          ['Alpha', 'Beta']);
      expect(controls['q42:2_answer_text']?.type, 'textarea');
      expect(controls['q42:2_choice0']?.type, 'checkbox');
      expect(controls.containsKey('q42:2_:sequencecheck'), isFalse);
      expect(controls.containsKey('q42:2_:flagged'), isFalse);
    });

    test('keeps distinct option groups for each gapselect blank', () {
      const html = '''
<div class="que gapselect deferredfeedback notyetanswered">
  <div class="qtext">
    Complete: Em branco 1 Questao 3
    <select name="q42:3_p1">
      <option value=""> </option>
      <option value="1">massa especifica rho</option>
      <option value="2">temperatura T</option>
    </select>
    e Em branco 2 Questao 3
    <select name="q42:3_p2">
      <option value=""> </option>
      <option value="1">gravidade g</option>
      <option value="2">vazao Q</option>
    </select>.
  </div>
</div>
''';

      final parsed = MoodleHtmlParser.parse(
        html: html,
        attemptId: 42,
        slot: 3,
        token: 'abc123',
        baseUrl: 'https://moodle.example.edu',
      );

      final gap = parsed.gapInputData!;
      expect(gap.gapCount, 2);
      expect(gap.optionsByGap, hasLength(2));
      expect(gap.optionsForGap(1).map((o) => o.text),
          ['massa especifica rho', 'temperatura T']);
      expect(
          gap.optionsForGap(2).map((o) => o.text), ['gravidade g', 'vazao Q']);
      expect(gap.options.map((o) => o.text), contains('gravidade g'));
    });

    test('removes duplicate TeX gap images from marker prompt', () {
      const html = '''
<div class="que gapselect deferredfeedback notyetanswered">
  <div class="qtext">
    Complete a relacao:
    <img class="texrender" alt="Delta P = [1] cdot [2]" src="https://moodle.ufu.br/filter/tex/pix.php/hash.gif" />
    Delta P =
    <label class="visually-hidden" for="q42_3_p1">Em branco 1 Questao 3</label>
    <select id="q42_3_p1" name="q42:3_p1">
      <option value=""> </option>
      <option value="1">rho</option>
      <option value="2">T</option>
    </select>
    cdot
    <label class="visually-hidden" for="q42_3_p2">Em branco 2 Questao 3</label>
    <select id="q42_3_p2" name="q42:3_p2">
      <option value=""> </option>
      <option value="1">g</option>
      <option value="2">Q</option>
    </select>
  </div>
</div>
''';

      final prompt = MoodleHtmlParser.extractTextWithGapMarkers(
        html,
        'abc123',
        'https://moodle.example.edu',
      );

      expect(prompt, contains('Complete a relacao'));
      expect(prompt, contains('Delta P ='));
      expect(prompt, contains('[1]'));
      expect(prompt, contains('[2]'));
      expect(prompt, isNot(contains('tex/pix.php')));
      expect(prompt, isNot(contains('alt=')));
      expect(prompt, isNot(contains('visually-hidden')));
      expect(prompt, isNot(contains('Em branco 1 Questao 3')));
    });

    test('repairs malformed TeX gaps before counting and rendering markers',
        () {
      const optionHtml = '''
        <option value="0">Escolha...</option>
        <option value="1">fluido incompressivel</option>
        <option value="2">rho</option>
      ''';
      const html = '''
<div class="que gapselect deferredfeedback notyetanswered">
  <div class="formulation">
    <div class="qtext">
      \\Delta P = <span class=Em branco 1 Questao 3
        <select name="q42:3_p1">$optionHtml</select>
        · Em branco 2 Questao 3 <select name="q42:3_p2">$optionHtml</select>
        · Em branco 3 Questao 3 <select name="q42:3_p3">$optionHtml</select>
        " alt="\\Delta P = Em branco 1 Questao 3
        <select name="q42:3_dup1">$optionHtml</select>
        · Em branco 2 Questao 3 <select name="q42:3_dup2">$optionHtml</select>
        · Em branco 3 Questao 3 <select name="q42:3_dup3">$optionHtml</select>"
        src="https://moodle.ufu.br/filter/tex/pix.php/hash.gif" />
      A relacao pressupoe fluido em Em branco 4 Questao 3
      <select name="q42:3_p4">$optionHtml</select>
      e comparacao entre pontos pertencentes ao Em branco 5 Questao 3
      <select name="q42:3_p5">$optionHtml</select>.
    </div>
  </div>
</div>
''';

      final parsed = MoodleHtmlParser.parse(
        html: html,
        attemptId: 42,
        slot: 3,
        token: 'abc123',
        baseUrl: 'https://moodle.example.edu',
      );
      final prompt = MoodleHtmlParser.extractTextWithGapMarkers(
        html,
        'abc123',
        'https://moodle.example.edu',
      );

      expect(parsed.gapInputData?.gapCount, 5);
      expect(prompt, isNot(contains('src=')));
      expect(prompt, isNot(contains('alt=')));
      expect(prompt, isNot(contains('<span class=Em')));
      expect(prompt, isNot(contains('Em branco 1 Questao 3')));
      expect(prompt, isNot(contains('Em branco 4 Questao 3')));
      expect(prompt, contains('[1]'));
      expect(prompt, contains('[5]'));
      expect(prompt, isNot(contains('[6]')));
    });

    test('strips literal TeX attribute residue and duplicate named selects',
        () {
      const optionHtml = '''
        <option value=""> </option>
        <option value="1">correta</option>
        <option value="2">distrator</option>
      ''';
      const html = '''
<div class="que gapselect deferredfeedback notyetanswered">
  <div class="formulation">
    <div class="qtext">
      Complete a análise técnica do Teorema de Stevin. Para dois pontos de um mesmo fluido em condição hidrostática, a diferença de pressão vertical é dada por:
      <select name="q1180693:3_p1">$optionHtml</select> ·
      <select name="q1180693:3_p2">$optionHtml</select> ·
      <select name="q1180693:3_p3">$optionHtml</select>
      " alt="Δ P =
      <select name="q1180693:3_p1">$optionHtml</select> ·
      <select name="q1180693:3_p2">$optionHtml</select> ·
      <select name="q1180693:3_p3">$optionHtml</select>"
      src="https://moodle.ufu.br/filter/tex/pix.php/hash.gif" />
      A relação pressupõe fluido em <select name="q1180693:3_p4">$optionHtml</select>
      e comparação entre pontos pertencentes ao <select name="q1180693:3_p5">$optionHtml</select>.
    </div>
  </div>
</div>
''';

      final parsed = MoodleHtmlParser.parse(
        html: html,
        attemptId: 940970,
        slot: 3,
        token: 'abc123',
        baseUrl: 'https://moodle.example.edu',
      );
      final prompt = MoodleHtmlParser.extractTextWithGapMarkers(
        parsed.htmlText,
        'abc123',
        'https://moodle.example.edu',
      );

      expect(parsed.answerControls, hasLength(5));
      expect(parsed.gapInputData?.gapCount, 5);
      expect(parsed.text, isNot(contains('alt=')));
      expect(parsed.text, isNot(contains('src=')));
      expect(parsed.text, isNot(contains('tex/pix.php')));
      expect(prompt, contains('[1]'));
      expect(prompt, contains('[5]'));
      expect(prompt, isNot(contains('[6]')));
      expect(prompt, isNot(contains('alt=')));
      expect(prompt, isNot(contains('src=')));
      expect(prompt, isNot(contains('tex/pix.php')));
    });

    test('does not let quiz header metadata leak into gap prompt', () {
      const optionHtml = '''
        <option value="0">Escolha...</option>
        <option value="1">fluido incompressivel</option>
        <option value="2">rho</option>
      ''';
      const html = '''
<div class="que gapselect deferredfeedback notyetanswered">
  <div class="info">
    <h3 class="no">Questão <span class="qno">3</span></h3>
    <div class="state">Incompleto</div>
    <div class="grade">Vale 1,00 ponto(s).</div>
  </div>
  <div class="formulation">
    <div class="qtext">
      Complete a análise técnica.
      \\Delta P = <span class=Em branco 1 Questão 3
        <select name="q42:3_p1">$optionHtml</select>
        · Em branco 2 Questão 3 <select name="q42:3_p2">$optionHtml</select>
        · Em branco 3 Questão 3 <select name="q42:3_p3">$optionHtml</select>
        " alt="\\Delta P = Em branco 1 Questão 3
        <select name="q42:3_dup1">$optionHtml</select>
        · Em branco 2 Questão 3 <select name="q42:3_dup2">$optionHtml</select>
        · Em branco 3 Questão 3 <select name="q42:3_dup3">$optionHtml</select>"
        src="https://moodle.ufu.br/filter/tex/pix.php/hash.gif" />
      A relação pressupõe fluido em Em branco 4 Questão 3
      <select name="q42:3_p4">$optionHtml</select>.
      <button>Verificar Questão 3</button>
    </div>
  </div>
</div>
''';

      final parsed = MoodleHtmlParser.parse(
        html: html,
        attemptId: 42,
        slot: 3,
        token: 'abc123',
        baseUrl: 'https://moodle.example.edu',
      );
      final prompt = MoodleHtmlParser.extractTextWithGapMarkers(
        html,
        'abc123',
        'https://moodle.example.edu',
      );

      expect(parsed.gapInputData?.gapCount, 4);
      expect(prompt, contains('Complete a análise técnica'));
      expect(prompt, isNot(contains('"qno">3')));
      expect(prompt, isNot(contains('Incompleto')));
      expect(prompt, isNot(contains('Vale 1,00')));
      expect(prompt, isNot(contains('Verificar Questão 3')));
      expect(prompt, isNot(contains('Em branco 1 Questão 3')));
      expect(prompt, isNot(contains('Em branco 4 Questão 3')));
      expect(prompt, contains('[1]'));
      expect(prompt, contains('[4]'));
      expect(prompt, isNot(contains('[5]')));
    });

    test('strips malformed TeX shell that remains after gap markers', () {
      const html = '''
<div class="qtext">
  \\Delta P = <span class=
    <span style="color:red">[1]</span> ·
    <span style="color:red">[2]</span> ·
    <span style="color:red">[3]</span>
    " alt="\\AP =
    <span style="color:red">[4]</span> ·
    <span style="color:red">[5]</span> ·
    <span style="color:red">[6]</span>"
    src="https://moodle.ufu.br/filter/tex/pix.php/hash.gif" />
  A relação pressupõe fluido em <span>[7]</span>.
</div>
''';

      final prompt = MoodleHtmlParser.extractTextWithGapMarkers(
        html,
        'abc123',
        'https://moodle.example.edu',
      );

      expect(prompt, isNot(contains('<span class=')));
      expect(prompt, isNot(contains('alt=')));
      expect(prompt, isNot(contains('src=')));
      expect(prompt, contains('[1]'));
      expect(prompt, contains('[2]'));
      expect(prompt, contains('[3]'));
      expect(prompt, isNot(contains('[4]')));
      expect(prompt, isNot(contains('[6]')));
      expect(prompt, contains('[7]'));
    });

    test('recovers gapselect prompt from accessible text when TeX breaks qtext',
        () {
      const html = '''
<div class="que gapselect deferredfeedback notyetanswered">
  <div class="qtext">
    Questão <span class="qno">3</span>Incompleto Vale 1,00 ponto(s).
    Complete a análise técnica do Teorema de Stevin. Para dois pontos de um mesmo fluido em condição hidrostática, a diferença de pressão vertical é dada por:
    \\Delta P =
    Em branco 1 Questão 3
    <select name="q1180673:3_p1">
      <option value="0">Escolha...</option>
      <option value="1">massa específica \\(\\rho\\)</option>
      <option value="2">temperatura absoluta \\(T\\)</option>
    </select>
    \\cdot Em branco 2 Questão 3
    <select name="q1180673:3_p2">
      <option value="0">Escolha...</option>
      <option value="1">vazão volumétrica \\(Q\\)</option>
      <option value="2">aceleração da gravidade \\(g\\)</option>
    </select>
    \\cdot Em branco 3 Questão 3
    <select name="q1180673:3_p3">
      <option value="0">Escolha...</option>
      <option value="1">diferença vertical de altura \\(\\Delta h\\)</option>
      <option value="2">área da seção transversal \\(A\\)</option>
    </select>
    A relação pressupõe fluido em Em branco 4 Questão 3
    <select name="q1180673:3_p4">
      <option value="0">Escolha...</option>
      <option value="1">repouso</option>
      <option value="2">escoamento turbulento</option>
    </select>
    e comparação entre pontos pertencentes ao Em branco 5 Questão 3
    <select name="q1180673:3_p5">
      <option value="0">Escolha...</option>
      <option value="1">mesmo fluido homogêneo</option>
      <option value="2">instrumento eletrônico</option>
    </select>,
    sem aceleração macroscópica do escoamento.
    Verificar Questão 3
  </div>
</div>
''';

      final parsed = MoodleHtmlParser.parse(
        html: html,
        attemptId: 940951,
        slot: 3,
        token: 'abc123',
        baseUrl: 'https://moodle.example.edu',
      );
      final prompt = MoodleHtmlParser.extractTextWithGapMarkers(
        parsed.htmlText,
        'abc123',
        'https://moodle.example.edu',
      );

      expect(parsed.gapInputData?.gapCount, 5);
      expect(parsed.gapInputData?.inputNamePrefix, 'q1180673:3_p');
      expect(
          prompt, contains('Complete a análise técnica do Teorema de Stevin'));
      expect(prompt, contains('Δ P ='));
      expect(prompt, contains('[1]'));
      expect(prompt, contains('[5]'));
      expect(prompt, contains('A relação pressupõe fluido em'));
      expect(prompt, isNot(contains('qno')));
      expect(prompt, isNot(contains('Incompleto')));
      expect(prompt, isNot(contains('Vale 1,00')));
      expect(prompt, isNot(contains('Em branco 1 Questão 3')));
      expect(prompt, isNot(contains('massa específica')));
      expect(prompt, isNot(contains('Verificar Questão 3')));
    });

    test('removes option text when raw text has latex and option has unicode',
        () {
      const html = '''
<div class="que gapselect deferredfeedback notyetanswered">
  <div class="qtext">
    Questão <span class="qno">3</span>Incompleto Vale 1,00 ponto(s).
    Texto da questão Complete:
    \\Delta P = Em branco 1 Questão 3 massa específica \\(\\rho\\) temperatura absoluta \\(T\\)
    \\cdot Em branco 2 Questão 3 aceleração da gravidade \\(g\\) vazão volumétrica \\(Q\\).
    <select name="q1180678:3_p1">
      <option value=""></option>
      <option value="1">massa específica ρ</option>
      <option value="2">temperatura absoluta T</option>
    </select>
    <select name="q1180678:3_p2">
      <option value=""></option>
      <option value="1">aceleração da gravidade g</option>
      <option value="2">vazão volumétrica Q</option>
    </select>
    Verificar Questão 3
  </div>
</div>
''';

      final parsed = MoodleHtmlParser.parse(
        html: html,
        attemptId: 940956,
        slot: 3,
        token: 'abc123',
        baseUrl: 'https://moodle.example.edu',
      );
      final prompt = MoodleHtmlParser.extractTextWithGapMarkers(
        parsed.htmlText,
        'abc123',
        'https://moodle.example.edu',
      );

      expect(prompt, contains('Complete:'));
      expect(prompt, contains('[1]'));
      expect(prompt, contains('[2]'));
      expect(prompt, isNot(contains('massa específica')));
      expect(prompt, isNot(contains('temperatura absoluta')));
      expect(prompt, isNot(contains('aceleração da gravidade')));
      expect(prompt, isNot(contains('vazão volumétrica')));
      expect(prompt, isNot(contains('Incompleto')));
    });
    test('extracts ddmarker background and hidden coordinate fields', () {
      const html = '''
<div id="q940:1" class="que ddmarker deferredfeedback notyetanswered">
  <div class="formulation">
    <div class="qtext"><p>Marque os erros na imagem.</p></div>
    <div class="ddarea">
      <div class="droparea">
        <img class="dropbackground img-fluid w-100" src="@@PLUGINFILE@@/si_erros_grafia.png" alt="Imagem">
      </div>
      <div class="draghomes">
        <span class="marker user-select-none choice0 infinite">
          <span class="target"></span><span class="markertext">ERRO</span>
        </span>
      </div>
      <div class="ddform">
        <input type="hidden" id="q940_1_c0" name="q940:1_c0" value=""
          class="choices choice0 noofdrags12 infinite">
      </div>
    </div>
  </div>
  <input type="hidden" name="q940:1_:sequencecheck" value="1">
</div>
''';

      final parsed = MoodleHtmlParser.parse(
        html: html,
        attemptId: 940,
        slot: 1,
        token: 'abc123',
        baseUrl: 'https://moodle.example.edu',
      );

      final data = parsed.ddMarkerData!;
      expect(data.backgroundImageUrl,
          contains('webservice/pluginfile.php/si_erros_grafia.png'));
      expect(data.backgroundImageUrl, contains('token=abc123'));
      expect(data.choices, hasLength(1));
      expect(data.choices.single.inputName, 'q940:1_c0');
      expect(data.choices.single.text, 'ERRO');
      expect(data.choices.single.infinite, isTrue);
      expect(data.choices.single.noOfDrags, 12);
    });

    test('builds ordering controls from static Moodle list fallback', () {
      const html = '''
<div class="que ordering deferredfeedback notyetanswered">
  <div class="formulation">
    <input type="hidden" name="q42:24:sequencecheck" value="1" />
    <div class="qtext"><p>Ordene os elementos.</p></div>
    <div class="ablock">
      <ul class="answer">
        <li>Declarar o resultado completo y ± U</li>
        <li>Informar o fator k utilizado</li>
        <li>Registrar a incerteza expandida U</li>
      </ul>
    </div>
  </div>
</div>
''';

      final parsed = MoodleHtmlParser.parse(
        html: html,
        attemptId: 42,
        slot: 24,
        token: '',
        baseUrl: '',
      );

      final controls = parsed.answerControls.where((c) => c.isSelect).toList();
      expect(parsed.type, 'ordering');
      expect(controls, hasLength(3));
      expect(controls.first.name, 'q42:24_answer0');
      expect(controls.first.label, contains('Declarar'));
      expect(controls.first.options.map((o) => o.value), ['1', '2', '3']);
    });
  });
}
