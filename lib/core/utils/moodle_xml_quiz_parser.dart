import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:xml/xml.dart' as xml;

import '../../domain/entities/question_entity.dart';
import 'moodle_html_parser.dart'
    show MoodleHtmlParser, ParsedChoice, MatchData, MatchSubQuestion;

class MoodleXmlQuizParser {
  static List<QuestionEntity> parseQuestions(
    Uint8List bytes, {
    String token = '',
    String baseUrl = '',
    void Function(String)? onLog,
  }) {
    final source = _decode(bytes);
    final document = xml.XmlDocument.parse(source);
    final questions = document
        .findAllElements('question')
        .where((q) => q.getAttribute('type') != 'category')
        .toList(growable: false);

    final result = <QuestionEntity>[];
    for (var i = 0; i < questions.length; i++) {
      final node = questions[i];
      final slot = i + 1;
      final xmlType = node.getAttribute('type')?.trim() ?? 'unknown';
      final type = _normalizeType(xmlType);
      final questionName = _childText(node, 'name');
      final questionText = _formattedText(node, 'questiontext');
      final feedback = _formattedText(node, 'generalfeedback');
      final html = _buildAttemptHtml(node, type: type, slot: slot);

      final parsed = MoodleHtmlParser.parse(
        html: html,
        attemptId: 0,
        slot: slot,
        token: token,
        baseUrl: baseUrl,
      );

      final rightAnswerHtml = _rightAnswerHtml(node, type);
      var question = QuestionEntity(
        slot: parsed.slot,
        page: i,
        text: parsed.text.isNotEmpty ? parsed.text : questionName,
        htmlText: parsed.htmlText.isNotEmpty ? parsed.htmlText : questionText,
        displayHtml:
            parsed.displayHtml.isNotEmpty ? parsed.displayHtml : questionText,
        choices: _markCorrectChoices(parsed.choices, node, type),
        imageUrls: parsed.imageUrls,
        inputBaseName: parsed.inputBaseName,
        seqCheck: parsed.seqCheck,
        type: type,
        generalFeedback: feedback,
        rightAnswerHtml: rightAnswerHtml,
        answerControls: parsed.answerControls,
        answerInputName: parsed.answerInputName,
        matchData: _matchDataWithCorrectValues(parsed.matchData),
        gapInputData: parsed.gapInputData,
        ddMarkerData: parsed.ddMarkerData,
      );

      onLog?.call(
        '  -> XML slot=$slot tipo=$type "${questionName.isEmpty ? question.text : questionName}"',
      );
      result.add(question);
    }
    return result;
  }

  static String _decode(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _normalizeType(String type) {
    return switch (type) {
      'matching' => 'match',
      'truefalse' => 'truefalse',
      'calculatedmulti' => 'calculatedmulti',
      'calculatedsimple' => 'calculatedsimple',
      _ => type,
    };
  }

  static String _buildAttemptHtml(
    xml.XmlElement question, {
    required String type,
    required int slot,
  }) {
    final qName = 'q0:$slot';
    final prompt = _applyFirstDatasetValues(
      _formattedText(question, 'questiontext'),
      question,
    );
    final body = switch (type) {
      'multichoice' ||
      'truefalse' ||
      'calculatedmulti' =>
        _multichoiceHtml(question, qName),
      'match' => _matchHtml(question, qName),
      'gapselect' => _gapSelectHtml(question, qName, prompt, type),
      'ddwtos' => _gapSelectHtml(question, qName, prompt, type),
      'ordering' => _orderingHtml(question, qName),
      'essay' => '<textarea name="${qName}_answer"></textarea>',
      'shortanswer' => '<input type="text" name="${qName}_answer" />',
      'numerical' ||
      'calculated' ||
      'calculatedsimple' =>
        '<input type="number" name="${qName}_answer" />',
      _ => _genericAnswerHtml(question, qName),
    };

    final qtext = (type == 'gapselect' || type == 'ddwtos')
        ? _gapPromptWithSelects(question, qName, prompt, type)
        : prompt;
    return '''
<div class="que $type immediatefeedback notyetanswered">
  <div class="formulation">
    <input type="hidden" name="$qName:sequencecheck" value="1" />
    <div class="qtext">$qtext</div>
    <div class="ablock">$body</div>
  </div>
</div>
''';
  }

  static String _multichoiceHtml(xml.XmlElement question, String qName) {
    final answers = question.findElements('answer').toList(growable: false);
    final buffer = StringBuffer('<div class="answer">');
    for (var i = 0; i < answers.length; i++) {
      final id = '${qName.replaceAll(':', '_')}_answer$i';
      buffer.write('''
<div class="r$i">
  <input type="radio" name="${qName}_answer" value="$i" id="$id" />
  <label for="$id"><span class="answernumber">${_letter(i)}. </span>${_answerText(answers[i])}</label>
</div>
''');
    }
    buffer.write('</div>');
    return buffer.toString();
  }

  static String _matchHtml(xml.XmlElement question, String qName) {
    final subs = question.findElements('subquestion').toList(growable: false);
    final options = subs
        .map((s) => _childText(s, 'answer'))
        .where((s) => s.trim().isNotEmpty)
        .toList(growable: false);
    final buffer = StringBuffer('<table class="answer"><tbody>');
    for (var i = 0; i < subs.length; i++) {
      buffer.write('<tr><td class="text">${_textElement(subs[i])}</td>');
      buffer.write('<td class="control"><select name="${qName}_sub$i">');
      buffer.write('<option value="0"></option>');
      for (var j = 0; j < options.length; j++) {
        buffer
            .write('<option value="${j + 1}">${_escape(options[j])}</option>');
      }
      buffer.write('</select></td></tr>');
    }
    buffer.write('</tbody></table>');
    return buffer.toString();
  }

  static String _gapSelectHtml(
      xml.XmlElement question, String qName, String prompt, String type) {
    return _gapPromptWithSelects(question, qName, prompt, type);
  }

  static String _gapPromptWithSelects(
      xml.XmlElement question, String qName, String prompt, String type) {
    final options = _gapOptions(question);
    return prompt.replaceAllMapped(RegExp(r'\[\[(\d+)\]\]'), (match) {
      final gap = int.tryParse(match.group(1) ?? '') ?? 1;
      final groupOptions = type == 'ddwtos'
          ? <_GapOption>[]
          : options.where((o) => o.group == gap).toList();
      final visibleOptions = groupOptions.isEmpty ? options : groupOptions;
      final buffer = StringBuffer('<select name="${qName}_p$gap">');
      buffer.write('<option value="0"></option>');
      for (final option in visibleOptions) {
        buffer.write(
          '<option value="${option.index}">${_escape(option.text)}</option>',
        );
      }
      buffer.write('</select>');
      return buffer.toString();
    });
  }

  static String _orderingHtml(xml.XmlElement question, String qName) {
    final answers = question.findElements('answer').toList(growable: false);
    final labels = answers.map(_answerText).toList(growable: false);
    final buffer = StringBuffer('<table class="answer ordering"><tbody>');
    for (var i = 0; i < labels.length; i++) {
      buffer.write('<tr>');
      buffer.write('<td class="text">${labels[i]}</td>');
      buffer.write('<td class="control"><select name="${qName}_answer$i">');
      buffer.write('<option value="0"></option>');
      for (var j = 0; j < labels.length; j++) {
        buffer.write('<option value="${j + 1}">${j + 1}</option>');
      }
      buffer.write('</select></td>');
      buffer.write('</tr>');
    }
    buffer.write('</tbody></table>');
    return buffer.toString();
  }

  static String _genericAnswerHtml(xml.XmlElement question, String qName) {
    if (question.findElements('answer').isEmpty) return '';
    return '<input type="text" name="${qName}_answer" />';
  }

  static List<ParsedChoice> _markCorrectChoices(
    List<ParsedChoice> choices,
    xml.XmlElement question,
    String type,
  ) {
    if (!(type == 'multichoice' ||
        type == 'truefalse' ||
        type == 'calculatedmulti')) {
      return choices;
    }
    final answers = question.findElements('answer').toList(growable: false);
    return choices.map((choice) {
      final index = int.tryParse(choice.value);
      final correct = index != null &&
          index >= 0 &&
          index < answers.length &&
          ((double.tryParse(answers[index].getAttribute('fraction') ?? '') ??
                  0) >
              0);
      return ParsedChoice(
        value: choice.value,
        text: choice.text,
        htmlText: choice.htmlText,
        isCorrect: correct,
      );
    }).toList(growable: false);
  }

  static MatchData? _matchDataWithCorrectValues(MatchData? data) {
    if (data == null) return null;
    final updated = <MatchSubQuestion>[];
    for (var i = 0; i < data.subQuestions.length; i++) {
      updated.add(MatchSubQuestion(
        text: data.subQuestions[i].text,
        htmlText: data.subQuestions[i].htmlText,
        inputName: data.subQuestions[i].inputName,
        correctValue: '${i + 1}',
      ));
    }
    return MatchData(subQuestions: updated, options: data.options);
  }

  static String _rightAnswerHtml(xml.XmlElement question, String type) {
    final pieces = <String>[];
    if (type == 'match') {
      for (final sub in question.findElements('subquestion')) {
        final left = _textElement(sub);
        final right = _childText(sub, 'answer');
        if (left.trim().isNotEmpty && right.trim().isNotEmpty) {
          pieces.add('$left &rarr; ${_escape(right)}');
        }
      }
    } else if (type == 'gapselect' || type == 'ddwtos') {
      final options = _gapOptions(question);
      final gapCount = _gapCount(question);
      for (var i = 1; i <= gapCount; i++) {
        final option = options.firstWhere(
          (o) => o.index == i,
          orElse: () => _GapOption(index: 0, group: 0, text: ''),
        );
        if (option.text.isNotEmpty) pieces.add('[$i] ${_escape(option.text)}');
      }
    } else if (type == 'ordering') {
      pieces.addAll(question.findElements('answer').map(_answerText));
    } else {
      pieces.addAll(question.findElements('answer').where((answer) {
        return (double.tryParse(answer.getAttribute('fraction') ?? '') ?? 0) >
            0;
      }).map(_answerText));
    }
    if (pieces.isEmpty) return '';
    return '<div class="rightanswer">${pieces.join('<br />')}</div>';
  }

  static List<_GapOption> _gapOptions(xml.XmlElement question) {
    final raw = <xml.XmlElement>[
      ...question.findElements('selectoption'),
      ...question.findElements('dragbox'),
    ];
    final result = <_GapOption>[];
    for (var i = 0; i < raw.length; i++) {
      final group = int.tryParse(_childText(raw[i], 'group')) ?? 1;
      final no = int.tryParse(_childText(raw[i], 'no')) ?? (i + 1);
      result.add(_GapOption(
        index: no,
        group: group,
        text: _textElement(raw[i]),
      ));
    }
    return result;
  }

  static int _gapCount(xml.XmlElement question) {
    final prompt = _formattedText(question, 'questiontext');
    final matches = RegExp(r'\[\[(\d+)\]\]').allMatches(prompt).toList();
    if (matches.isEmpty) return 0;
    return matches
        .map((m) => int.tryParse(m.group(1) ?? '') ?? 0)
        .fold<int>(0, max);
  }

  static String _applyFirstDatasetValues(String html, xml.XmlElement question) {
    final values = <String, String>{};
    for (final def in question.findAllElements('dataset_definition')) {
      final name = _childText(def, 'name');
      if (name.isEmpty) continue;
      final value = def
          .findAllElements('dataset_item')
          .map((item) => _childText(item, 'value'))
          .firstWhere((v) => v.isNotEmpty, orElse: () => '');
      if (value.isNotEmpty) values[name] = value;
    }
    var result = html;
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }

  static String _formattedText(xml.XmlElement parent, String childName) {
    final child = parent.findElements(childName).firstOrNull;
    if (child == null) return '';
    return _textElement(child);
  }

  static String _textElement(xml.XmlElement parent) {
    final text = parent.findElements('text').firstOrNull;
    if (text == null) return '';
    return text.innerText.trim();
  }

  static String _childText(xml.XmlElement parent, String childName) {
    final child = parent.findElements(childName).firstOrNull;
    if (child == null) return '';
    return _textElement(child).isNotEmpty
        ? _textElement(child)
        : child.innerText.trim();
  }

  static String _answerText(xml.XmlElement answer) {
    return _applyFirstDatasetValues(_textElement(answer), answer);
  }

  static String _letter(int index) {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    return letters[min(index, letters.length - 1)];
  }

  static String _escape(String value) => const HtmlEscape().convert(value);
}

class _GapOption {
  final int index;
  final int group;
  final String text;

  const _GapOption({
    required this.index,
    required this.group,
    required this.text,
  });
}
