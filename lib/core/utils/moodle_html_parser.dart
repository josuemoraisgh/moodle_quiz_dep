/// Extrai dados estruturados de um bloco HTML de questão do Moodle.
/// Implementado em Dart puro (compatível com WASM – sem dart:html).
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

// ── Entidades de saída ────────────────────────────────────────────────────────

class ParsedChoice {
  final String value; // "0", "1", "2"…
  final String text; // texto exibido para o aluno
  final String
      htmlText; // alternativa como HTML rico (preserva imagens/tabelas)
  final bool isCorrect; // true se esta alternativa é a resposta correta

  const ParsedChoice({
    required this.value,
    required this.text,
    this.htmlText = '',
    this.isCorrect = false,
  });
}

/// Controle de resposta bruto extraido do HTML do Moodle.
class MoodleAnswerControl {
  final String name;
  final String type;
  final String value;
  final String label;
  final String htmlLabel;
  final List<ParsedChoice> options;

  const MoodleAnswerControl({
    required this.name,
    required this.type,
    this.value = '',
    this.label = '',
    this.htmlLabel = '',
    this.options = const [],
  });

  bool get isHidden => type == 'hidden';
  bool get isText => type == 'text' || type == 'number';
  bool get isLongText => type == 'textarea';
  bool get isSingleChoice => type == 'radio';
  bool get isMultipleChoice => type == 'checkbox';
  bool get isSelect => type == 'select';
  bool get isAnswerable => !isHidden;
}

/// Sub-questão de uma questão de Associação (match).
class MatchSubQuestion {
  final String text; // texto da premissa
  final String htmlText; // premissa como HTML
  final String inputName; // nome do campo select, e.g. "q12345:1_sub0"
  final String? correctValue; // valor correto (preenchido após revisão)

  const MatchSubQuestion({
    required this.text,
    required this.htmlText,
    required this.inputName,
    this.correctValue,
  });
}

/// Dados estruturados de uma questão de Associação.
class MatchData {
  final List<MatchSubQuestion> subQuestions;
  final List<ParsedChoice> options; // opções iguais para todas as sub-questões

  const MatchData({required this.subQuestions, required this.options});
}

/// Dados estruturados de uma questão de lacunas (gapselect / ddwtos).
/// Permite renderizar a questão como widget Flutter nativo interativo.
class GapInputData {
  /// Número de lacunas na questão.
  final int gapCount;

  /// Opções disponíveis (mesmas para todas as lacunas em ddwtos/gapselect).
  final List<ParsedChoice> options;

  /// Opcoes por lacuna. Em gapselect o Moodle pode renderizar um grupo de
  /// opcoes diferente para cada `<select>`.
  final List<List<ParsedChoice>> optionsByGap;

  /// Prefixo do nome do campo Moodle — ex: "q123:1_p".
  /// Nome completo da lacuna N: "${inputNamePrefix}N" (N = 1, 2, 3…).
  final String inputNamePrefix;

  const GapInputData({
    required this.gapCount,
    required this.options,
    this.optionsByGap = const [],
    required this.inputNamePrefix,
  });

  String inputName(int gapNum) => '$inputNamePrefix$gapNum';

  List<ParsedChoice> optionsForGap(int gapNum) {
    final index = gapNum - 1;
    if (index >= 0 &&
        index < optionsByGap.length &&
        optionsByGap[index].isNotEmpty) {
      return optionsByGap[index];
    }
    return options;
  }
}

/// Choice/marker available in a Moodle ddmarker question.
class DdMarkerChoice {
  final int choiceNo;
  final String inputName;
  final String text;
  final bool infinite;
  final int noOfDrags;

  const DdMarkerChoice({
    required this.choiceNo,
    required this.inputName,
    required this.text,
    this.infinite = false,
    this.noOfDrags = 1,
  });
}

/// Structured data for Moodle drag-and-drop marker questions.
class DdMarkerData {
  final String backgroundImageUrl;
  final List<DdMarkerChoice> choices;

  const DdMarkerData({
    required this.backgroundImageUrl,
    required this.choices,
  });
}

class ParsedQuestion {
  final int slot;
  final String text; // texto da questão (HTML stripped — fallback)
  final String htmlText; // enunciado como HTML com URLs corrigidas
  final String displayHtml; // HTML completo da questão (todos os blocos)
  final List<ParsedChoice> choices;
  final List<String> imageUrls;
  final String
      inputBaseName; // "q{attemptId}:{slot}_answer" (usado para seqcheck)
  final String seqCheck; // valor do input sequencecheck
  final String type; // tipo real do Moodle (ou inferido)
  final List<MoodleAnswerControl> answerControls;

  // Dados específicos por tipo
  final String?
      answerInputName; // nome do campo de texto (numerical/shortanswer)
  final MatchData? matchData; // estrutura de associação (match)
  final GapInputData? gapInputData; // estrutura de lacunas (gapselect/ddwtos)
  final DdMarkerData? ddMarkerData; // estrutura de marcadores sobre imagem

  const ParsedQuestion({
    required this.slot,
    required this.text,
    required this.htmlText,
    this.displayHtml = '',
    required this.choices,
    required this.imageUrls,
    required this.inputBaseName,
    required this.seqCheck,
    required this.type,
    this.answerControls = const [],
    this.answerInputName,
    this.matchData,
    this.gapInputData,
    this.ddMarkerData,
  });

  bool get isMultiChoice =>
      type == 'multichoice' || type == 'truefalse' || type == 'calculatedmulti';
}

// ── Parser ────────────────────────────────────────────────────────────────────

class MoodleHtmlParser {
  static final RegExp _malformedTexSpanStartRe = RegExp(
    r'<span\s+class\s*=\s*"?\s*(?=Em\s+branco\b)',
    caseSensitive: false,
  );
  static final RegExp _malformedTexAltRe =
      RegExp(r'"\s+(?:alt|title)\s*=', caseSensitive: false);
  static final RegExp _moodleTexSrcRe = RegExp(
    r'\bsrc\s*=\s*"[^"]*(?:/filter/tex/|tex/pix\.php)[^"]*"',
    caseSensitive: false,
  );
  static final RegExp _blankLabelBeforeControlRe = RegExp(
    r'\bEm\s+branco\s+\d+\s+Quest\S*\s+\d+\s*(?=\s*<(?:select|input|textarea|span)\b)',
    caseSensitive: false,
    dotAll: true,
  );

  /// Analisa o HTML de `mod_quiz_get_attempt_data.questions[].html`.
  static ParsedQuestion parse({
    required String html,
    required int attemptId,
    required int slot,
    required String token,
    required String baseUrl,
  }) {
    final normalizedHtml = _normalizeQuestionHtml(html);

    // Extrai o tipo diretamente da classe CSS do elemento raiz da questão.
    // Moodle renderiza: class="que {type} {behaviour} {state}"
    final htmlType = _extractTypeFromHtml(normalizedHtml);

    final choices = _extractChoices(normalizedHtml, token, baseUrl);
    var answerControls =
        _extractAnswerControls(normalizedHtml, token, baseUrl);

    // Resolve o tipo final: prefere o tipo inferido do HTML; fallback para contagem de radios
    String type;
    if (htmlType.isNotEmpty) {
      if (htmlType == 'multichoice' || htmlType == 'calculatedmulti') {
        // Valida com contagem de choices para truefalse
        type = (choices.isNotEmpty && choices.length == 2)
            ? 'truefalse'
            : htmlType;
      } else {
        type = htmlType;
      }
    } else {
      // Fallback legado: conta radio buttons
      type = choices.length == 2
          ? 'truefalse'
          : (choices.isEmpty ? 'other' : 'multichoice');
    }

    var text = _extractText(normalizedHtml);
    var htmlText = _extractHtmlText(normalizedHtml, token, baseUrl);
    var displayHtml = extractDisplayHtml(normalizedHtml, token, baseUrl);
    final images = _extractImages(normalizedHtml, token, baseUrl);
    final seqCheck = _extractSeqCheck(normalizedHtml);

    final extractedBase = _extractInputBaseName(normalizedHtml);
    final hardcoded = 'q$attemptId:${slot}_answer';
    final inputBase = extractedBase ?? hardcoded;

    if (type == 'ordering' && !answerControls.any((c) => c.isSelect)) {
      final fallbackControls = _extractOrderingFallbackControls(
        normalizedHtml,
        inputBase,
        token,
        baseUrl,
      );
      if (fallbackControls.isNotEmpty) answerControls = fallbackControls;
    }

    // Dados específicos por tipo
    MatchData? matchData;
    String? answerInputName;
    GapInputData? gapInputData;
    DdMarkerData? ddMarkerData;

    if (type == 'match') {
      matchData = _extractMatchData(normalizedHtml, token, baseUrl);
    } else if (type == 'numerical' ||
        type == 'calculated' ||
        type == 'calculatedsimple' ||
        type == 'shortanswer') {
      answerInputName = _extractAnswerInputName(normalizedHtml) ?? inputBase;
    } else if (type == 'gapselect' || type == 'ddwtos') {
      gapInputData = _extractGapInputData(normalizedHtml, slot, attemptId);
    } else if (type == 'ddmarker') {
      ddMarkerData = _extractDdMarkerData(normalizedHtml, token, baseUrl);
    }

    if ((type == 'gapselect' || type == 'ddwtos') && gapInputData != null) {
      final recoveredPrompt = _recoverGapPromptFromAccessibleText(
        html,
        normalizedHtml,
        slot,
      );
      if (recoveredPrompt != null &&
          _shouldUseRecoveredGapPrompt(htmlText, displayHtml)) {
        htmlText = recoveredPrompt;
        if (!_hasVisibleQuestionContent(displayHtml)) {
          displayHtml = recoveredPrompt;
        }
        text = _stripHtml(recoveredPrompt).trim();
      }
    }

    return ParsedQuestion(
      slot: slot,
      text: text,
      htmlText: htmlText,
      displayHtml: displayHtml,
      choices: choices,
      imageUrls: images,
      inputBaseName: inputBase,
      seqCheck: seqCheck,
      type: type,
      answerControls: answerControls,
      answerInputName: answerInputName,
      matchData: matchData,
      gapInputData: gapInputData,
      ddMarkerData: ddMarkerData,
    );
  }

  static String _repairMalformedTexGapHtml(String source) {
    if (!source.contains('<span') ||
        !RegExp(r'(?:/filter/tex/|tex/pix\.php)', caseSensitive: false)
            .hasMatch(source)) {
      return source;
    }

    final buffer = StringBuffer();
    var index = 0;

    while (index < source.length) {
      final startMatch = _firstMatchAfter(
        _malformedTexSpanStartRe,
        source,
        index,
      );
      if (startMatch == null) break;

      final start = startMatch.start;
      final valueStart = startMatch.end;
      final altMatch = _firstMatchAfter(_malformedTexAltRe, source, valueStart);
      if (altMatch == null) {
        buffer.write(source.substring(index, valueStart));
        index = valueStart;
        continue;
      }

      final classValue = source.substring(valueStart, altMatch.start);
      if (!RegExp(r'^\s*"?\s*Em\s+branco\b', caseSensitive: false)
          .hasMatch(classValue)) {
        buffer.write(source.substring(index, valueStart));
        index = valueStart;
        continue;
      }

      final srcMatch = _firstMatchAfter(_moodleTexSrcRe, source, altMatch.end);
      if (srcMatch == null) {
        buffer.write(source.substring(index, valueStart));
        index = valueStart;
        continue;
      }

      final close = source.indexOf('/>', srcMatch.end);
      final fallbackClose = source.indexOf('>', srcMatch.end);
      final end = close >= 0
          ? close + 2
          : (fallbackClose >= 0 ? fallbackClose + 1 : -1);
      if (end < 0) {
        buffer.write(source.substring(index, valueStart));
        index = valueStart;
        continue;
      }

      buffer.write(source.substring(index, start));
      // Write back the real content from the malformed span's class-attribute
      // fragment. This preserves actual <select> elements (the gap answer
      // controls) and separator text (e.g. "·"). The "Em branco N Questão N"
      // accessibility labels are removed in the next step by
      // _cleanBlankLabelsBeforeControls.
      buffer.write(classValue);
      index = end;
    }

    buffer.write(source.substring(index));
    return buffer.toString();
  }

  static String _normalizeQuestionHtml(String source) {
    return _stripResidualMalformedTexShell(
      _cleanBlankLabelsBeforeControls(
        _repairMalformedTexGapHtml(source),
      ),
    );
  }

  static String _cleanBlankLabelsBeforeControls(String source) {
    return source.replaceAll(_blankLabelBeforeControlRe, '');
  }

  static String _stripResidualMalformedTexShell(String source) {
    final cleaned = source.replaceAllMapped(
      RegExp(
        r'''<span\s+class\s*=\s*(?!\s*["'])(.*?)"\s+(?:alt|title)\s*=\s*".*?"\s+src\s*=\s*"[^"]*(?:/filter/tex/|tex/pix\.php)[^"]*"\s*(?:/?>|/&gt;)''',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) {
        final visiblePart = match.group(1) ?? '';
        final markers = RegExp(r'\[\d+\]')
            .allMatches(visiblePart)
            .map((m) => m.group(0) ?? '')
            .where((marker) => marker.isNotEmpty)
            .toSet()
            .toList(growable: false);
        if (markers.isEmpty) return visiblePart;
        return markers.join(' ${String.fromCharCode(183)} ');
      },
    );
    return _stripLiteralTexAttributeResidue(cleaned);
  }

  static String _stripLiteralTexAttributeResidue(String source) {
    return source.replaceAllMapped(
      RegExp(
        r'''\s*(?:"|&quot;)\s+(?:alt|title)\s*=\s*(?:"|&quot;).*?\s+src\s*=\s*(?:"|&quot;)[^"']*(?:/filter/tex/|tex/pix\.php)[^"']*(?:"|&quot;)\s*(?:/?>|/&gt;|&gt;)''',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) {
        if (match.start > 0) {
          final previous = source.substring(match.start - 1, match.start);
          if (RegExp(r'[\p{L}\p{N}_-]', unicode: true).hasMatch(previous)) {
            return match.group(0) ?? '';
          }
        }
        return ' ';
      },
    );
  }

  static bool _shouldUseRecoveredGapPrompt(
    String htmlText,
    String displayHtml,
  ) {
    final source = htmlText.trim().isNotEmpty ? htmlText : displayHtml;
    if (source.trim().isEmpty) return true;

    String prompt;
    try {
      prompt = extractTextWithGapMarkers(source, '', '');
    } catch (_) {
      prompt = source;
    }

    final plain = _plainText(prompt);
    if (plain.isEmpty) return true;
    if (prompt.contains('src=') || prompt.contains('/filter/tex/')) return true;
    if (RegExp(r'\b(?:qno|Incompleto|Vale\s+\d|Verificar\s+Quest)',
            caseSensitive: false)
        .hasMatch(plain)) {
      return true;
    }
    return RegExp(r'\bEm\s+branco\s+\d+\s+Quest\S*\s+\d+', caseSensitive: false)
        .hasMatch(plain);
  }

  static String? _recoverGapPromptFromAccessibleText(
    String rawHtml,
    String normalizedHtml,
    int slot,
  ) {
    final optionGroups = _extractSelectOptionGroups(normalizedHtml);
    if (optionGroups.isEmpty) return null;

    final textCandidates = <String>[
      _plainTextWithoutFormControls(rawHtml),
      _plainTextWithoutFormControls(normalizedHtml),
      _plainTextLoose(rawHtml),
      _plainText(rawHtml),
      _plainTextLoose(normalizedHtml),
      _plainText(normalizedHtml),
    ].where((text) => text.trim().isNotEmpty);

    for (final candidate in textCandidates) {
      final recovered = _recoverGapPromptFromPlainText(
        candidate,
        optionGroups,
      );
      if (recovered != null) return recovered;
    }

    return null;
  }

  static String? _recoverGapPromptFromPlainText(
    String sourceText,
    List<List<String>> optionGroups,
  ) {
    var text = sourceText;
    final questionTextMatch = RegExp(
      r'Texto\s+da\s+quest\S*o',
      caseSensitive: false,
    ).firstMatch(text);
    if (questionTextMatch != null) {
      text = text.substring(questionTextMatch.end).trim();
    }

    text = text
        .replaceFirst(
          RegExp(
            r'^Quest\S*o\s*(?:"?qno"?>)?\s*\d+\s*Incompleto\s+Vale\s+.*?ponto\(s\)\.\s*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'Marcar\s+quest\S*o(?:\s+v\d+[^.]*\.)?',
              caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(r'Verificar\s+Quest\S*o\s+\d+.*$',
              caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final labelPattern = RegExp(
      r'\bEm\s+branco\s+(\d+)\s+Quest\S*o\s+\d+\s*',
      caseSensitive: false,
    );
    final labels = labelPattern.allMatches(text).toList(growable: false);
    if (labels.isEmpty) return null;

    final buffer = StringBuffer('<div class="qtext">');
    var cursor = 0;
    for (var i = 0; i < labels.length; i++) {
      final label = labels[i];
      final gapNum = int.tryParse(label.group(1) ?? '') ?? (i + 1);
      final nextStart =
          i + 1 < labels.length ? labels[i + 1].start : text.length;
      final before = text.substring(cursor, label.start);
      final afterLabel = text.substring(label.end, nextStart);
      final options = gapNum > 0 && gapNum <= optionGroups.length
          ? optionGroups[gapNum - 1]
          : const <String>[];

      buffer.write(_escapeHtmlText(_humanizePromptText(before)));
      buffer.write(_gapMarkerHtml(gapNum));
      buffer.write(_escapeHtmlText(_humanizePromptText(
        _stripLeadingOptionTexts(afterLabel, options),
      )));
      cursor = nextStart;
    }
    buffer.write(_escapeHtmlText(_humanizePromptText(text.substring(cursor))));
    buffer.write('</div>');

    final recovered = buffer.toString();
    return _hasVisibleQuestionContent(recovered) ? recovered : null;
  }

  static List<List<String>> _extractSelectOptionGroups(String html) {
    final fragment = html_parser.parseFragment(html);
    final groups = <List<String>>[];

    for (final select in fragment.querySelectorAll('select')) {
      final options = <String>[];
      for (final option in select.querySelectorAll('option')) {
        final value = option.attributes['value'] ?? '';
        final text = _normalizePlainText(option.text);
        if (text.isEmpty) continue;
        if (value == '-1') continue;
        options.add(text);
      }
      if (options.isNotEmpty) groups.add(options);
    }

    return groups;
  }

  static String _stripLeadingOptionTexts(String value, List<String> options) {
    var result = _normalizePlainText(value);
    if (result.isEmpty || options.isEmpty) return result;

    final sorted = [...options]..sort((a, b) => b.length.compareTo(a.length));
    var changed = true;
    while (changed) {
      changed = false;
      for (final option in sorted) {
        final end = _matchingOptionPrefixEnd(result, option);
        if (end != null) {
          result = result.substring(end).trimLeft();
          changed = true;
        }
      }
    }

    return result;
  }

  static int? _matchingOptionPrefixEnd(String value, String option) {
    final target = _comparisonPromptText(option);
    if (target.isEmpty) return null;

    final maxEnd =
        value.length < option.length + 40 ? value.length : option.length + 40;
    for (var end = 1; end <= maxEnd; end++) {
      final prefix = _comparisonPromptText(value.substring(0, end));
      if (prefix == target) return end;
      if (prefix.length > target.length + 4) return null;
    }
    return null;
  }

  static String _comparisonPromptText(String value) {
    return _humanizePromptText(value)
        .replaceAll(RegExp(r'[^\p{L}\p{N}%]+', unicode: true), '')
        .toLowerCase();
  }

  static String _humanizePromptText(String value) {
    return _normalizePlainText(value)
        .replaceAll(r'\(', '')
        .replaceAll(r'\)', '')
        .replaceAll(r'\Delta', String.fromCharCode(916))
        .replaceAll(r'\rho', String.fromCharCode(961))
        .replaceAll(r'\cdot', String.fromCharCode(183))
        .replaceAll(r'\times', String.fromCharCode(215))
        .replaceAllMapped(RegExp(r'\s+([.,;:])'), (match) => match.group(1)!)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _gapMarkerHtml(int gapNum) {
    return '<span style="display:inline-block;border:2px dashed #6c7ae0;'
        'border-radius:4px;background:rgba(108,122,224,0.12);'
        'padding:1px 10px;margin:0 4px;color:#a0a8f8;'
        'font-weight:700;font-size:0.9em;">[$gapNum]</span>';
  }

  static String _plainText(String html) {
    final fragment = html_parser.parseFragment(html);
    return _normalizePlainText(fragment.text ?? '');
  }

  static String _plainTextLoose(String html) {
    return _normalizePlainText(
      html
          .replaceAll(
              RegExp(r'<script\b[^>]*>.*?</script>',
                  caseSensitive: false, dotAll: true),
              ' ')
          .replaceAll(
              RegExp(r'<style\b[^>]*>.*?</style>',
                  caseSensitive: false, dotAll: true),
              ' ')
          .replaceAll(RegExp(r'<[^>]+>'), ' '),
    );
  }

  static String _plainTextWithoutFormControls(String html) {
    return _plainTextLoose(
      html
          .replaceAll(
              RegExp(r'<select\b[^>]*>.*?</select>',
                  caseSensitive: false, dotAll: true),
              ' ')
          .replaceAll(
              RegExp(r'<textarea\b[^>]*>.*?</textarea>',
                  caseSensitive: false, dotAll: true),
              ' ')
          .replaceAll(
              RegExp(r'<input\b[^>]*>', caseSensitive: false, dotAll: true),
              ' '),
    );
  }

  static String _normalizePlainText(String value) {
    return value
        .replaceAll(String.fromCharCode(160), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#160;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _escapeHtmlText(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  static RegExpMatch? _firstMatchAfter(
    RegExp pattern,
    String source,
    int start,
  ) {
    for (final match in pattern.allMatches(source, start)) {
      return match;
    }
    return null;
  }

  /// Extrai os values dos inputs de rádio cuja resposta é correta.
  static List<String> parseCorrectValues(String reviewHtml) {
    // ── Método primário: aria-labelledby + rightanswer ────────────────────────
    final attrRe = RegExp(r'([\w-]+)="([^"]*)"', caseSensitive: false);
    final radioRe =
        RegExp(r'<input\b[^>]*type="radio"[^>]*/?>', caseSensitive: false);

    final idToValue = <String, String>{};
    for (final m in radioRe.allMatches(reviewHtml)) {
      final tag = m.group(0) ?? '';
      String value = '', ariaLabelledBy = '';
      for (final a in attrRe.allMatches(tag)) {
        final k = a.group(1)!.toLowerCase();
        if (k == 'value') value = a.group(2)!;
        if (k == 'aria-labelledby') ariaLabelledBy = a.group(2)!;
      }
      if (value.isNotEmpty && value != '-1' && ariaLabelledBy.isNotEmpty) {
        idToValue[ariaLabelledBy] = value;
      }
    }

    final labelDivRe = RegExp(
      r'<div\b[^>]+id="([^"]+)"[^>]*data-region="answer-label"[^>]*>(.*?)</div>\s*</div>',
      caseSensitive: false,
      dotAll: true,
    );
    final idToText = <String, String>{};
    for (final m in labelDivRe.allMatches(reviewHtml)) {
      final id = m.group(1) ?? '';
      final content = m.group(2) ?? '';
      final cleaned = content.replaceAll(
          RegExp(r'<span[^>]*class="[^"]*answernumber[^"]*"[^>]*>.*?</span>',
              caseSensitive: false, dotAll: true),
          '');
      final text = _stripHtml(cleaned).trim();
      if (id.isNotEmpty && text.isNotEmpty) idToText[id] = text;
    }

    final rightAnswerRe = RegExp(
      r'<div[^>]*class="[^"]*rightanswer[^"]*"[^>]*>(.*?)</div>',
      caseSensitive: false,
      dotAll: true,
    );
    final rightMatch = rightAnswerRe.firstMatch(reviewHtml);
    if (rightMatch != null) {
      String correctText = _stripHtml(rightMatch.group(1) ?? '').trim();
      final sepIdx = correctText.indexOf(':');
      if (sepIdx >= 0 && sepIdx < correctText.length - 1) {
        correctText = correctText.substring(sepIdx + 1).trim();
      }

      if (correctText.isNotEmpty) {
        for (final entry in idToText.entries) {
          if (entry.value == correctText ||
              entry.value.contains(correctText) ||
              correctText.contains(entry.value)) {
            final value = idToValue[entry.key];
            if (value != null) return [value];
          }
        }
      }
    }

    // ── Fallback legacy: containers com classe "correct" ──────────────────────
    final correctValues = <String>[];
    final containerRe = RegExp(
      r'<(?:li|div)\b[^>]*class="([^"]*)"[^>]*>(.*?)</(?:li|div)>',
      caseSensitive: false,
      dotAll: true,
    );
    final radioValueRe = RegExp(
      r'<input\b[^>]*type="radio"[^>]*value="([^"]*)"',
      caseSensitive: false,
    );
    for (final m in containerRe.allMatches(reviewHtml)) {
      final classAttr = m.group(1) ?? '';
      if (classAttr.contains('correct') && !classAttr.contains('incorrect')) {
        final radioMatch = radioValueRe.firstMatch(m.group(2) ?? '');
        if (radioMatch != null) {
          final value = radioMatch.group(1) ?? '';
          if (value.isNotEmpty && value != '-1') correctValues.add(value);
        }
      }
    }
    return correctValues;
  }

  /// Extrai os pares corretos de uma questão de Associação no HTML de revisão.
  /// Retorna mapa: inputName → correctValue (e.g. "q12345:1_sub0" → "2")
  static Map<String, String> parseCorrectMatchValues(String reviewHtml) {
    final result = <String, String>{};
    final fragment = html_parser.parseFragment(reviewHtml);

    // Cada linha da tabela de resposta da revisão tem a coluna de texto e a
    // coluna com o select já com a opção correta selecionada (selected="selected")
    for (final row in fragment
        .querySelectorAll('table.answer tr, table.generaltable tr')) {
      final select = row.querySelector('select');
      if (select == null) continue;
      final inputName = select.attributes['name'] ?? '';
      if (inputName.isEmpty) continue;

      // Opção marcada como correta no HTML de revisão
      final correctOption =
          select.querySelector('option[selected], option[selected="selected"]');
      if (correctOption != null) {
        final val = correctOption.attributes['value'] ?? '';
        if (val.isNotEmpty && val != '0') result[inputName] = val;
      }
    }
    return result;
  }

  /// Extrai selects que o Moodle devolve ja preenchidos na revisao.
  /// Usado como fallback para gapselect, ddwtos e ordering quando a revisao
  /// nao traz um bloco `.rightanswer` separado.
  static Map<String, ParsedChoice> parseSelectedSelectAnswers(
      String reviewHtml) {
    final result = <String, ParsedChoice>{};
    final fragment = html_parser.parseFragment(reviewHtml);

    for (final select in fragment.querySelectorAll('select')) {
      final name = select.attributes['name'] ?? '';
      if (name.isEmpty || !_isAnswerFieldName(name)) continue;

      final selected =
          select.querySelector('option[selected], option[selected="selected"]');
      if (selected == null) continue;

      final value = selected.attributes['value'] ?? '';
      if (value.isEmpty || value == '-1' || value == '0') continue;

      final text = _stripHtml(selected.innerHtml).trim();
      if (text.isEmpty) continue;

      result[name] = ParsedChoice(value: value, text: text);
    }

    return result;
  }

  /// Extrai o feedback geral da questão do HTML de revisão.
  static String parseGeneralFeedback(String reviewHtml) {
    final content = _extractTag(reviewHtml, 'generalfeedback') ?? '';
    return content.trim();
  }

  /// Extrai o HTML do bloco `.rightanswer` da revisão (se houver).
  static String parseRightAnswerHtml(
      String reviewHtml, String token, String baseUrl) {
    // Estratégia principal: parse DOM e busca por classes comuns de gabarito.
    final fragment = html_parser.parseFragment(reviewHtml);
    final node = fragment.querySelector('.rightanswer') ??
        fragment.querySelector('[class*="rightanswer"]') ??
        fragment.querySelector('.correctanswer') ??
        fragment.querySelector('[class*="correctanswer"]');

    if (node != null) {
      final html = node.outerHtml.trim();
      if (html.isNotEmpty) {
        return _rewriteResourceUrls(html, token, baseUrl);
      }
    }

    // Fallback legado para HTMLs antigos.
    final content = _extractTag(reviewHtml, 'rightanswer') ?? '';
    if (content.isEmpty) return '';
    return _rewriteResourceUrls(content.trim(), token, baseUrl);
  }

  // ── HTML completo para exibição somente leitura ──────────────────────────

  static String extractDisplayHtml(String html, String token, String baseUrl) {
    final normalizedHtml = _normalizeQuestionHtml(html);
    final fragment = html_parser.parseFragment(normalizedHtml);

    for (final el in fragment.querySelectorAll(
        'script, style, noscript, button, .submitbtns, .qn_buttontoggle, '
        '.questionflag, .questionflagsavebutton, .info, .history, '
        '.qheader, .grade, .state, .toggle-button, .editquestion, '
        '.que-finish-attempt, .editquestion-toolbar')) {
      el.remove();
    }

    dom.Element? formulation = fragment.querySelector('.formulation') ??
        fragment.querySelector('.qtext');
    if (formulation != null) {
      // Para ddwtos e gapselect, inclui o banco de palavras (.ablock) se existir
      // fora do .formulation, para que as palavras apareçam na visualização.
      final ablock = fragment.querySelector('.ablock');
      final htmlToProcess = (ablock != null && !formulation.contains(ablock))
          ? '${formulation.outerHtml}${ablock.outerHtml}'
          : formulation.outerHtml;
      final clone = html_parser.parseFragment(htmlToProcess);
      _cleanupFormulation(clone);
      return _rewriteResourceUrls(clone.outerHtml, token, baseUrl);
    }

    _cleanupFormulation(fragment);
    return _rewriteResourceUrls(fragment.outerHtml, token, baseUrl);
  }

  static void _cleanupFormulation(dom.DocumentFragment fragment) {
    for (final el in fragment.querySelectorAll(
        '.accesshide, .sr-only, .visually-hidden, .visuallyhidden')) {
      el.remove();
    }

    // Inputs ocultos e de controle: remove
    for (final input in fragment.querySelectorAll('input[type="hidden"], '
        'input[type="submit"], input[type="button"]')) {
      input.remove();
    }

    // Elementos arrastáveis (ddwtos): torna as palavras visíveis como chips
    for (final el in fragment
        .querySelectorAll('[draggable="true"], .drag, .draghome, .dragitem')) {
      final text = _stripHtml(el.innerHtml).trim();
      if (text.isNotEmpty) {
        final chip = dom.Element.tag('span');
        chip.attributes['style'] =
            'display:inline-block;border:1px solid rgba(255,255,255,0.35);'
            'border-radius:4px;background:rgba(255,255,255,0.08);'
            'vertical-align:middle;margin:2px;padding:2px 8px;font-size:0.9em;';
        chip.text = text;
        el.replaceWith(chip);
      } else {
        el.remove();
      }
    }

    // Lacunas de drop (ddwtos): mostra como caixa vazia estilizada
    for (final el in fragment.querySelectorAll('.drop, .droptarget')) {
      final placeholder = dom.Element.tag('span');
      placeholder.attributes['style'] =
          'display:inline-block;min-width:80px;height:20px;'
          'border:1px dashed #888;border-radius:4px;'
          'background:rgba(255,255,255,0.04);vertical-align:middle;margin:0 4px;';
      el.replaceWith(placeholder);
    }

    // Inputs de texto → caixas visuais vazias (para Cloze, Numérica…)
    for (final input
        in fragment.querySelectorAll('input[type="text"], input:not([type])')) {
      final placeholder = dom.Element.tag('span');
      placeholder.attributes['style'] =
          'display:inline-block;min-width:90px;height:18px;'
          'border:1px solid #888;border-radius:4px;'
          'background:rgba(255,255,255,0.06);vertical-align:middle;'
          'margin:0 4px;';
      input.replaceWith(placeholder);
    }

    // Selects → mostra as opções disponíveis como lista visual compacta
    for (final select in fragment.querySelectorAll('select')) {
      final options = select
          .querySelectorAll('option')
          .where((o) {
            final v = o.attributes['value'] ?? '';
            return v.isNotEmpty && v != '0';
          })
          .map((o) => _stripHtml(o.innerHtml).trim())
          .where((t) => t.isNotEmpty);

      final placeholder = dom.Element.tag('span');
      if (options.isNotEmpty) {
        placeholder.attributes['style'] =
            'display:inline-block;border:1px dashed #888;border-radius:4px;'
            'background:rgba(255,255,255,0.06);vertical-align:middle;'
            'margin:0 4px;padding:2px 6px;font-size:0.9em;color:#aaa;';
        placeholder.text =
            '[${options.take(4).join(' | ')}${options.length > 4 ? "…" : ""}]';
      } else {
        placeholder.attributes['style'] =
            'display:inline-block;min-width:90px;height:18px;'
            'border:1px solid #888;border-radius:4px;'
            'background:rgba(255,255,255,0.06);vertical-align:middle;'
            'margin:0 4px;';
      }
      select.replaceWith(placeholder);
    }
  }

  // ── Extração do tipo pelo HTML ─────────────────────────────────────────────

  /// Extrai o tipo da questão da classe CSS Moodle: `class="que {type} …"`.
  static void _removeQuestionChrome(dom.DocumentFragment fragment) {
    for (final el in fragment.querySelectorAll(
        'script, style, noscript, button, .submitbtns, .qn_buttontoggle, '
        '.questionflag, .questionflagsavebutton, .info, .history, '
        '.qheader, .grade, .state, .no, .qno, .accesshide, .sr-only, '
        '.visually-hidden, .visuallyhidden, .answer, .ablock, '
        '.que-finish-attempt, .editquestion-toolbar')) {
      el.remove();
    }

    for (final input in fragment.querySelectorAll('input[type="hidden"], '
        'input[type="submit"], input[type="button"]')) {
      input.remove();
    }
  }

  static bool _hasVisibleQuestionContent(String html) {
    final text = _stripHtml(html)
        .replaceAll(RegExp(r'&(?:nbsp|#160);'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return false;

    final signal = text
        .replaceAll(RegExp(r'\[\d+\]'), '')
        .replaceAll(RegExp(r'[.,;:()\[\]\s]+'), '')
        .trim();
    return signal.isNotEmpty || RegExp(r'\[\d+\]').hasMatch(text);
  }

  static String _extractTypeFromHtml(String html) {
    final re = RegExp(r'class="que\s+([\w-]+)', caseSensitive: false);
    return re.firstMatch(html)?.group(1)?.toLowerCase() ?? '';
  }

  // ── Extração dos dados de Associação (match) ──────────────────────────────

  static MatchData? _extractMatchData(
      String html, String token, String baseUrl) {
    final fragment = html_parser.parseFragment(html);

    // Moodle 4.x: linhas em table.answer ou tabelas genéricas dentro de .ablock
    final rows = fragment
        .querySelectorAll('table.answer tr, .ablock table tr, .answer tr');

    final subQuestions = <MatchSubQuestion>[];
    final options = <ParsedChoice>[];
    bool optionsExtracted = false;

    for (final row in rows) {
      final textCell = row.querySelector('.text') ??
          row.querySelector('td.text') ??
          row.querySelector('td:first-child');
      final select = row.querySelector('select');

      if (textCell == null || select == null) continue;

      final inputName = select.attributes['name'] ?? '';
      if (inputName.isEmpty) continue;

      final premiseHtml =
          _rewriteResourceUrls(textCell.innerHtml, token, baseUrl);
      final premiseText = _stripHtml(premiseHtml).trim();

      if (premiseText.isNotEmpty || premiseHtml.isNotEmpty) {
        subQuestions.add(MatchSubQuestion(
          text: premiseText,
          htmlText: premiseHtml,
          inputName: inputName,
        ));
      }

      if (!optionsExtracted) {
        for (final option in select.querySelectorAll('option')) {
          final value = option.attributes['value'] ?? '';
          if (value.isEmpty || value == '0') continue;
          final text = _stripHtml(option.innerHtml).trim();
          if (text.isNotEmpty) {
            options.add(ParsedChoice(value: value, text: text));
          }
        }
        optionsExtracted = true;
      }
    }

    if (subQuestions.isEmpty) return null;
    return MatchData(subQuestions: subQuestions, options: options);
  }

  static List<MoodleAnswerControl> _extractOrderingFallbackControls(
    String html,
    String inputBase,
    String token,
    String baseUrl,
  ) {
    final fragment = html_parser.parseFragment(html);
    final selectors = [
      '.answer li',
      '.answer label',
      '.sortablelist li',
      '.sortable li',
      '[data-region="answer"] li',
      '.ablock li',
    ];

    final items = <_ChoiceContent>[];
    final seen = <String>{};
    for (final selector in selectors) {
      for (final element in fragment.querySelectorAll(selector)) {
        if (element.querySelector('select') != null) continue;
        if (_isMoodleUiControl(element)) continue;

        final clone = html_parser.parseFragment(element.outerHtml);
        for (final el in clone.querySelectorAll(
            'select, input, button, .accesshide, .sr-only, '
            '.visually-hidden, .visuallyhidden')) {
          el.remove();
        }

        final elementClones = clone.nodes.whereType<dom.Element>();
        final elementClone =
            elementClones.isEmpty ? null : elementClones.first;
        final rawHtml = elementClone?.innerHtml ?? element.innerHtml;
        final htmlText = _rewriteResourceUrls(rawHtml, token, baseUrl);
        final text = _stripHtml(htmlText).trim();
        final key = _normalizePlainText(text);
        if (key.isEmpty || !seen.add(key)) continue;
        items.add(_ChoiceContent(text: text, html: htmlText.trim()));
      }
      if (items.isNotEmpty) break;
    }

    if (items.length < 2) return const [];

    final options = List<ParsedChoice>.generate(
      items.length,
      (index) => ParsedChoice(value: '${index + 1}', text: '${index + 1}'),
      growable: false,
    );

    return List<MoodleAnswerControl>.generate(
      items.length,
      (index) => MoodleAnswerControl(
        name: '${_orderingAnswerBase(inputBase)}$index',
        type: 'select',
        label: items[index].text,
        htmlLabel: items[index].html,
        options: options,
      ),
      growable: false,
    );
  }

  // ── Extração de dados de marcadores sobre imagem (ddmarker) ─────────────

  static String _orderingAnswerBase(String inputBase) {
    if (inputBase.endsWith('_answer')) return inputBase;
    if (inputBase.endsWith('answer')) {
      return '${inputBase.substring(0, inputBase.length - 'answer'.length)}_answer';
    }
    return '${inputBase}_answer';
  }

  static DdMarkerData? _extractDdMarkerData(
      String html, String token, String baseUrl) {
    final normalizedHtml = _normalizeQuestionHtml(html);
    final fragment = html_parser.parseFragment(normalizedHtml);
    final image = fragment.querySelector('img.dropbackground') ??
        fragment.querySelector('.droparea img') ??
        fragment.querySelector('.ddarea img');
    final rawImageUrl = image?.attributes['src'] ?? '';
    if (rawImageUrl.trim().isEmpty) return null;

    final choices = <DdMarkerChoice>[];
    for (final input in fragment.querySelectorAll('input.choices')) {
      final name = input.attributes['name'] ?? '';
      if (!_isAnswerFieldName(name)) continue;
      final classAttr = input.attributes['class'] ?? '';
      final choiceNo = _classSuffixAsInt(classAttr, 'choice');
      if (choiceNo == null) continue;

      final noOfDrags = _classSuffixAsInt(classAttr, 'noofdrags') ?? 1;
      final text = _markerTextForChoice(fragment, choiceNo);
      choices.add(DdMarkerChoice(
        choiceNo: choiceNo,
        inputName: name,
        text: text.isNotEmpty ? text : 'Marcador ${choiceNo + 1}',
        infinite: _hasClassToken(classAttr, 'infinite'),
        noOfDrags: noOfDrags,
      ));
    }

    choices.sort((a, b) => a.choiceNo.compareTo(b.choiceNo));
    if (choices.isEmpty) return null;

    return DdMarkerData(
      backgroundImageUrl: _normalizeResourceUrl(rawImageUrl, token, baseUrl),
      choices: choices,
    );
  }

  static int? _classSuffixAsInt(String classAttr, String prefix) {
    final match =
        RegExp('(?:^|\\s)$prefix(\\d+)(?:\\s|\$)').firstMatch(classAttr);
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  static bool _hasClassToken(String classAttr, String token) {
    return RegExp('(?:^|\\s)$token(?:\\s|\$)').hasMatch(classAttr);
  }

  static String _markerTextForChoice(
      dom.DocumentFragment fragment, int choiceNo) {
    final direct = fragment.querySelector(
      '.choice$choiceNo .markertext, .marker.choice$choiceNo, '
      '.draghome.choice$choiceNo, .dragitem.choice$choiceNo',
    );
    if (direct == null) return '';
    final markerText = direct.querySelector('.markertext');
    return _stripHtml((markerText ?? direct).innerHtml).trim();
  }

  // ── Extração de dados de lacunas (gapselect / ddwtos) ─────────────────────

  /// Extrai estrutura interativa de lacunas para gapselect e ddwtos.
  /// Suporta duas estratégias:
  /// 1. HTML acessível com `<select>` inline no texto.
  /// 2. HTML JS com `.drop` (lacunas) e `.drag` (banco de palavras).
  static GapInputData? _extractGapInputData(
      String html, int slot, int attemptId) {
    final normalizedHtml = _normalizeQuestionHtml(html);
    final fragment = html_parser.parseFragment(normalizedHtml);

    // ── Estratégia 1: selects inline (gapselect / ddwtos acessível) ──────────
    final selects = fragment.querySelectorAll('select');
    if (selects.isNotEmpty) {
      final optionsByGap = <List<ParsedChoice>>[];
      final mergedByKey = <String, ParsedChoice>{};
      final seenNames = <String>{};
      var gapCount = 0;
      var prefix = '';

      for (final select in selects) {
        final name = select.attributes['name'] ?? '';
        if (name.isEmpty) continue;
        if (!seenNames.add(name)) continue;

        // Deriva prefixo: "q123:1_p1" → "q123:1_p"
        if (prefix.isEmpty) {
          prefix = name.replaceAll(RegExp(r'\d+$'), '');
        }
        gapCount++;

        // Extrai opções do primeiro select (todas as lacunas têm as mesmas)
        final gapOptions = <ParsedChoice>[];
        for (final opt in select.querySelectorAll('option')) {
          final value = opt.attributes['value'] ?? '';
          if (value.isEmpty || value == '0') continue;
          final text = _stripHtml(opt.innerHtml).trim();
          if (text.isNotEmpty) {
            final choice = ParsedChoice(value: value, text: text);
            gapOptions.add(choice);
            mergedByKey.putIfAbsent('$value\x00$text', () => choice);
          }
        }
        optionsByGap.add(gapOptions);
      }

      final options = mergedByKey.values.toList(growable: false);
      if (gapCount > 0 && options.isNotEmpty && prefix.isNotEmpty) {
        return GapInputData(
          gapCount: gapCount,
          options: options,
          optionsByGap: optionsByGap,
          inputNamePrefix: prefix,
        );
      }
    }

    // ── Estratégia 2: drop spans + drag items (ddwtos JS) ──────────────────
    final drops = fragment.querySelectorAll(
        '.drop, span[class*="drop"][class*="empty"], span[class*="drop"][class*="active"]');
    final drags =
        fragment.querySelectorAll('.drag:not(.dragplaceholder), .dragitem, '
            'span[class*="drag"]:not([class*="placeholder"])');

    if (drops.isNotEmpty && drags.isNotEmpty) {
      final options = <ParsedChoice>[];
      var choiceIdx = 1;

      for (final drag in drags) {
        final text = _stripHtml(drag.innerHtml).trim();
        if (text.isEmpty) continue;
        final dataChoice = drag.attributes['data-choice'] ??
            drag.attributes['data-value'] ??
            '$choiceIdx';
        options.add(ParsedChoice(value: dataChoice, text: text));
        choiceIdx++;
      }

      if (options.isNotEmpty) {
        final prefix = 'q$attemptId:${slot}_p';
        return GapInputData(
          gapCount: drops.length,
          options: options,
          optionsByGap: List<List<ParsedChoice>>.generate(
            drops.length,
            (_) => options,
            growable: false,
          ),
          inputNamePrefix: prefix,
        );
      }
    }

    return null;
  }

  /// Retorna o HTML do enunciado com lacunas marcadas como [1], [2], [3]…
  /// para exibição acima dos dropdowns interativos.
  static String extractTextWithGapMarkers(
      String html, String token, String baseUrl) {
    final normalizedHtml = _normalizeQuestionHtml(html);
    final fragment = html_parser.parseFragment(normalizedHtml);

    var gapNum = 0;

    void replaceWithMarker(dom.Element el) {
      gapNum++;
      final marker = dom.Element.tag('span');
      marker.attributes['style'] =
          'display:inline-block;border:2px dashed #6c7ae0;border-radius:4px;'
          'background:rgba(108,122,224,0.12);padding:1px 10px;margin:0 4px;'
          'color:#a0a8f8;font-weight:700;font-size:0.9em;';
      marker.text = '[$gapNum]';
      el.replaceWith(marker);
    }

    // Selects → marcadores numerados
    for (final el in fragment.querySelectorAll('select')) {
      replaceWithMarker(el);
    }

    // Drop spans → marcadores numerados
    for (final el in fragment
        .querySelectorAll('.drop, span[class*="drop"][class*="empty"], '
            'span[class*="drop"][class*="active"]')) {
      replaceWithMarker(el);
    }

    _normalizeTexImagesInGapPrompt(fragment);

    // Remove elementos do banco de palavras (mostrados como opções nos dropdowns)
    for (final el in fragment.querySelectorAll(
        '.drag, .dragitem, .dragcontainer, .dragwordscontainer, '
        '.draghome, .dragplaceholder, .ablock')) {
      el.remove();
    }

    // Remove elementos de controle
    for (final el in fragment
        .querySelectorAll('.accesshide, .sr-only, input[type="hidden"], '
            '.visually-hidden, .visuallyhidden, input[type="submit"], '
            'input[type="button"]')) {
      el.remove();
    }

    for (final el in fragment.querySelectorAll(
        '.info, .state, .grade, .no, .qno, .submitbtns, .questionflag, '
        '.questionflagsavebutton, button')) {
      el.remove();
    }

    final formulation = fragment.querySelector('.formulation') ??
        fragment.querySelector('.qtext');
    if (formulation != null) {
      return _rewriteResourceUrls(
        _cleanGapMarkerLabels(formulation.outerHtml),
        token,
        baseUrl,
      );
    }
    return _rewriteResourceUrls(
      _cleanGapMarkerLabels(fragment.outerHtml),
      token,
      baseUrl,
    );
  }

  static String _cleanGapMarkerLabels(String html) {
    var cleaned = html.replaceAllMapped(
      RegExp(
        r'\bEm\s+branco\s+\d+\s+Quest\S*\s+\d+\s*(<span\b[^>]*>\s*\[\d+\]\s*</span>)',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) => match.group(1) ?? '',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(
        r'\bEm\s+branco\s+\d+\s+Quest\S*\s+\d+\s*(?=(?:\s|&nbsp;|<[^>]+>)*<span\b[^>]*>\s*\[\d+\]\s*</span>)',
        caseSensitive: false,
        dotAll: true,
      ),
      (_) => '',
    );
    return _stripResidualMalformedTexShell(cleaned);
  }

  static void _normalizeTexImagesInGapPrompt(dom.DocumentFragment fragment) {
    for (final img in fragment.querySelectorAll('img').toList()) {
      final src = img.attributes['src'] ?? '';
      if (!_isMoodleTexSource(src)) continue;

      final alt = _normalizePlainText(
        img.attributes['alt'] ?? img.attributes['title'] ?? '',
      );
      if (alt.isEmpty || _containsGapSignal(alt)) {
        img.remove();
        continue;
      }

      final replacement = dom.Element.tag('span');
      replacement.text = _humanizePromptText(alt);
      img.replaceWith(replacement);
    }
  }

  static bool _isMoodleTexSource(String src) {
    return RegExp(r'(?:/filter/tex/|tex/pix\.php)', caseSensitive: false)
        .hasMatch(src);
  }

  static bool _containsGapSignal(String value) {
    return RegExp(r'(?:\[\d+\]|\bEm\s+branco\s+\d+|\bResposta\s+\d+)',
            caseSensitive: false)
        .hasMatch(value);
  }

  // ── Extração do nome do campo de texto ────────────────────────────────────

  /// Extrai o nome do campo `<input type="text">` (numerical/shortanswer).
  static String? _extractAnswerInputName(String html) {
    final re = RegExp(
      r'<input\b[^>]*type="text"[^>]*name="([^"]+)"',
      caseSensitive: false,
    );
    final m = re.firstMatch(html);
    if (m != null) return m.group(1);

    // Fallback: sem type (tratado como text pelo browser)
    final reNoType = RegExp(
      r'<input\b(?![^>]*type=)[^>]*name="(q[^"]+_answer)"',
      caseSensitive: false,
    );
    return reNoType.firstMatch(html)?.group(1);
  }

  // ── Extração do HTML do enunciado ─────────────────────────────────────────

  static List<MoodleAnswerControl> _extractAnswerControls(
      String html, String token, String baseUrl) {
    final fragment = html_parser.parseFragment(html);
    final labelByFor = <String, _ChoiceContent>{};
    final labelById = <String, _ChoiceContent>{};

    for (final label in fragment.querySelectorAll('label[for]')) {
      final id = label.attributes['for'] ?? '';
      if (id.isEmpty) continue;
      final content = _choiceContentFromElement(label, token, baseUrl);
      if (content.hasContent) labelByFor[id] = content;
    }

    for (final label
        in fragment.querySelectorAll('[data-region="answer-label"]')) {
      final id = label.id;
      if (id.isEmpty) continue;
      final content = _choiceContentFromElement(label, token, baseUrl);
      if (content.hasContent) labelById[id] = content;
    }

    final controls = <MoodleAnswerControl>[];
    final radioGroups = <String, List<ParsedChoice>>{};
    final radioGroupOrder = <String>[];

    for (final input in fragment.querySelectorAll('input')) {
      final name = input.attributes['name'] ?? '';
      if (!_isAnswerFieldName(name)) continue;
      if (_isMoodleUiControl(input)) continue;

      final type = (input.attributes['type'] ?? 'text').toLowerCase();
      if (_shouldSkipInputType(type)) continue;

      final value = input.attributes['value'] ?? '';
      final label = _controlLabel(input, labelByFor, labelById, token, baseUrl);

      if (type == 'radio') {
        if (value.isEmpty || value == '-1') continue;
        radioGroups.putIfAbsent(name, () {
          radioGroupOrder.add(name);
          return <ParsedChoice>[];
        }).add(ParsedChoice(
          value: value,
          text: label.text,
          htmlText: label.html,
        ));
        continue;
      }

      if (type == 'checkbox') {
        controls.add(MoodleAnswerControl(
          name: name,
          type: 'checkbox',
          value: value.isEmpty ? '1' : value,
          label: label.text,
          htmlLabel: label.html,
        ));
        continue;
      }

      if (type == 'hidden') {
        controls.add(MoodleAnswerControl(
          name: name,
          type: 'hidden',
          value: value,
        ));
        continue;
      }

      controls.add(MoodleAnswerControl(
        name: name,
        type: type == 'number' ? 'number' : 'text',
        value: value,
        label: label.text,
        htmlLabel: label.html,
      ));
    }

    final seenSelectNames = <String>{};
    for (final select in fragment.querySelectorAll('select')) {
      final name = select.attributes['name'] ?? '';
      if (!_isAnswerFieldName(name)) continue;
      if (!seenSelectNames.add(name)) continue;
      if (_isMoodleUiControl(select)) continue;
      final label =
          _controlLabel(select, labelByFor, labelById, token, baseUrl);
      final options = <ParsedChoice>[];
      for (final option in select.querySelectorAll('option')) {
        final value = option.attributes['value'] ?? '';
        if (value.isEmpty || value == '0') continue;
        final htmlText = _rewriteResourceUrls(option.innerHtml, token, baseUrl);
        final text = _stripHtml(htmlText).trim();
        if (text.isEmpty && htmlText.trim().isEmpty) continue;
        options.add(ParsedChoice(
          value: value,
          text: text,
          htmlText: htmlText.trim(),
        ));
      }
      controls.add(MoodleAnswerControl(
        name: name,
        type: 'select',
        label: label.text,
        htmlLabel: label.html,
        options: options,
      ));
    }

    for (final textarea in fragment.querySelectorAll('textarea')) {
      final name = textarea.attributes['name'] ?? '';
      if (!_isAnswerFieldName(name)) continue;
      if (_isMoodleUiControl(textarea)) continue;
      final label =
          _controlLabel(textarea, labelByFor, labelById, token, baseUrl);
      controls.add(MoodleAnswerControl(
        name: name,
        type: 'textarea',
        value: textarea.text,
        label: label.text,
        htmlLabel: label.html,
      ));
    }

    for (final name in radioGroupOrder.reversed) {
      final options = radioGroups[name] ?? const <ParsedChoice>[];
      if (options.isEmpty) continue;
      controls.insert(
        0,
        MoodleAnswerControl(
          name: name,
          type: 'radio',
          options: options,
        ),
      );
    }

    return controls;
  }

  static bool _isAnswerFieldName(String name) {
    final lower = name.toLowerCase();
    if (lower.isEmpty || !lower.startsWith('q')) return false;
    if (lower.contains(':sequencecheck')) return false;
    if (lower.contains('flagged') || lower.contains(':flag')) return false;
    if (lower.endsWith('-submit')) return false;
    return true;
  }

  static bool _isMoodleUiControl(dom.Element element) {
    dom.Element? current = element;
    var depth = 0;
    while (current != null && depth < 6) {
      final classAttr = current.attributes['class']?.toLowerCase() ?? '';
      if (classAttr.contains('questionflag') ||
          classAttr.contains('questionflagsavebutton') ||
          classAttr.contains('qn_buttontoggle') ||
          classAttr.contains('submitbtns')) {
        return true;
      }
      current = current.parent;
      depth++;
    }
    return false;
  }

  static bool _shouldSkipInputType(String type) {
    return type == 'submit' ||
        type == 'button' ||
        type == 'reset' ||
        type == 'image' ||
        type == 'file';
  }

  static _ChoiceContent _controlLabel(
    dom.Element element,
    Map<String, _ChoiceContent> labelByFor,
    Map<String, _ChoiceContent> labelById,
    String token,
    String baseUrl,
  ) {
    final id = element.id;
    if (id.isNotEmpty && labelByFor.containsKey(id)) return labelByFor[id]!;

    final ariaLabelledBy = element.attributes['aria-labelledby'] ?? '';
    if (ariaLabelledBy.isNotEmpty && labelById.containsKey(ariaLabelledBy)) {
      return labelById[ariaLabelledBy]!;
    }

    final nearest = _nearestControlLabel(element);
    if (nearest != null) {
      final html = _rewriteResourceUrls(nearest.innerHtml, token, baseUrl);
      final text = _stripHtml(html).trim();
      if (text.isNotEmpty || html.trim().isNotEmpty) {
        return _ChoiceContent(text: text, html: html.trim());
      }
    }

    return const _ChoiceContent(text: '', html: '');
  }

  static dom.Element? _nearestControlLabel(dom.Element element) {
    dom.Element? current = element.parent;
    var depth = 0;
    while (current != null && depth < 4) {
      if (current.localName == 'label') return current;
      final textCell = current.querySelector('.text, .prompt, .qtext');
      if (textCell != null && textCell.text.trim().isNotEmpty) {
        return textCell;
      }
      current = current.parent;
      depth++;
    }
    return null;
  }

  static String _extractHtmlText(String html, String token, String baseUrl) {
    final normalizedHtml = _normalizeQuestionHtml(html);
    final fragment = html_parser.parseFragment(normalizedHtml);

    dom.Element? contentElement = fragment.querySelector('.qtext') ??
        fragment.querySelector('.formulation');

    if (contentElement != null) {
      final clone = html_parser.parseFragment(contentElement.outerHtml);
      _removeQuestionChrome(clone);
      final content = _stripResidualMalformedTexShell(clone.outerHtml).trim();
      if (_hasVisibleQuestionContent(content)) {
        return _rewriteResourceUrls(content, token, baseUrl);
      }
    }

    String content = _extractTag(normalizedHtml, 'qtext') ??
        _extractTag(normalizedHtml, 'formulation') ??
        '';
    if (content.isEmpty) content = normalizedHtml;
    content = _removeBlock(content, r'class="(?:ablock|answer)');
    content = _stripResidualMalformedTexShell(content).trim();
    return _rewriteResourceUrls(content, token, baseUrl);
  }

  // ── Extração do texto da questão ──────────────────────────────────────────

  static String _extractText(String html) {
    final text = _stripHtml(_extractHtmlText(html, '', '')).trim();
    if (text.isNotEmpty) return text;

    String fallback =
        _extractTag(html, 'qtext') ?? _extractTag(html, 'formulation') ?? '';
    if (fallback.isEmpty) fallback = html;
    fallback = _removeBlock(fallback, r'class="(?:ablock|answer)');
    return _stripHtml(fallback).trim();
  }

  // ── Extração de alternativas ──────────────────────────────────────────────

  static List<ParsedChoice> _extractChoices(
      String html, String token, String baseUrl) {
    final choices = <ParsedChoice>[];
    final fragment = html_parser.parseFragment(html);

    final ariaLabelMap = <String, _ChoiceContent>{};
    for (final element
        in fragment.querySelectorAll('[data-region="answer-label"]')) {
      final id = element.id;
      if (id.isEmpty) continue;
      final content = _choiceContentFromElement(element, token, baseUrl);
      if (content.hasContent) ariaLabelMap[id] = content;
    }

    final forLabelMap = <String, _ChoiceContent>{};
    for (final element in fragment.querySelectorAll('label[for]')) {
      final forAttr = element.attributes['for'] ?? '';
      if (forAttr.isEmpty) continue;
      final content = _choiceContentFromElement(element, token, baseUrl);
      if (content.hasContent) forLabelMap[forAttr] = content;
    }

    for (final input in fragment.querySelectorAll('input')) {
      final type = input.attributes['type']?.toLowerCase() ?? '';
      if (type != 'radio') continue;

      final value = input.attributes['value'] ?? '';
      if (value.isEmpty || value == '-1') continue;

      final id = input.id;
      final ariaLabelledBy = input.attributes['aria-labelledby'] ?? '';
      final content = ariaLabelMap[ariaLabelledBy] ??
          (id.isNotEmpty ? forLabelMap[id] : null) ??
          const _ChoiceContent(text: '', html: '');

      choices.add(ParsedChoice(
        value: value,
        text: content.text,
        htmlText: content.html,
      ));
    }

    return choices;
  }

  // ── Extração de imagens ───────────────────────────────────────────────────

  static List<String> _extractImages(
      String html, String token, String baseUrl) {
    final images = <String>[];
    final imgRe = RegExp(
      r'''<img[^>]+src=(["'])(.*?)\1''',
      caseSensitive: false,
    );
    for (final m in imgRe.allMatches(html)) {
      var src = m.group(2) ?? '';
      if (src.isEmpty) continue;
      images.add(_normalizeResourceUrl(src, token, baseUrl));
    }
    return images;
  }

  static _ChoiceContent _choiceContentFromElement(
      dom.Element element, String token, String baseUrl) {
    for (final span in element.querySelectorAll('.answernumber')) {
      span.remove();
    }
    final cleanedHtml = _rewriteResourceUrls(element.innerHtml, token, baseUrl);
    final text = _stripHtml(cleanedHtml).trim();
    return _ChoiceContent(text: text, html: cleanedHtml.trim());
  }

  static String _rewriteResourceUrls(
      String html, String token, String baseUrl) {
    return html.replaceAllMapped(
      RegExp("\\b(src|href)=([\"'])(.*?)\\2", caseSensitive: false),
      (m) {
        final attr = m.group(1) ?? 'src';
        final quote = m.group(2) ?? '"';
        final url = _normalizeResourceUrl(m.group(3) ?? '', token, baseUrl);
        return '$attr=$quote$url$quote';
      },
    );
  }

  static String _normalizeResourceUrl(
      String url, String token, String baseUrl) {
    var src = url.trim();
    if (src.isEmpty ||
        src.startsWith('data:') ||
        src.startsWith('blob:') ||
        src.startsWith('mailto:') ||
        src.startsWith('#')) {
      return src;
    }

    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    if (src.startsWith('@@PLUGINFILE@@')) {
      src =
          src.replaceFirst('@@PLUGINFILE@@', '$root/webservice/pluginfile.php');
    } else if (src.startsWith('/') && !src.startsWith('//')) {
      src = '$root$src';
    } else if (!RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false)
        .hasMatch(src)) {
      src = '$root/$src';
    }

    if (src.contains('/pluginfile.php')) {
      src = src.replaceFirst('/pluginfile.php', '/webservice/pluginfile.php');
    }

    src = src.replaceAll(' ', '%20');

    if (src.contains('/webservice/pluginfile.php') &&
        !RegExp(r'([?&])token=').hasMatch(src)) {
      final sep = src.contains('?') ? '&' : '?';
      src = '$src${sep}token=$token';
    }

    return src;
  }

  // ── Extração do sequencecheck ─────────────────────────────────────────────

  static String _extractSeqCheck(String html) {
    final inputRe = RegExp(
      r'<input\b[^>]*name="[^"]*:sequencecheck"[^>]*/?>',
      caseSensitive: false,
    );
    final inputTag = inputRe.firstMatch(html)?.group(0) ?? '';
    if (inputTag.isEmpty) return '1';
    final valueRe = RegExp(r'\bvalue="([^"]*)"', caseSensitive: false);
    return valueRe.firstMatch(inputTag)?.group(1) ?? '1';
  }

  // ── Extração do inputBaseName real ─────────────────────────────────────────

  static String? _extractInputBaseName(String html) {
    final attrRe = RegExp(r'([\w-]+)="([^"]*)"', caseSensitive: false);

    // 1) Tenta de radio buttons (multichoice/truefalse)
    final radioRe =
        RegExp(r'<input\b[^>]*type="radio"[^>]*/?>', caseSensitive: false);
    for (final m in radioRe.allMatches(html)) {
      final inputTag = m.group(0)!;
      for (final a in attrRe.allMatches(inputTag)) {
        final key = a.group(1)!.toLowerCase();
        final val = a.group(2)!;
        if (key == 'name' && val.isNotEmpty) return val;
      }
    }

    // 2) Fallback: deduz do input :sequencecheck
    final allInputsRe = RegExp(r'<input\b[^>]*/?>', caseSensitive: false);
    for (final m in allInputsRe.allMatches(html)) {
      final inputTag = m.group(0)!;
      if (!inputTag.contains(':sequencecheck')) continue;
      for (final a in attrRe.allMatches(inputTag)) {
        final key = a.group(1)!.toLowerCase();
        final val = a.group(2)!;
        if (key == 'name' && val.contains(':sequencecheck')) {
          return val.replaceFirst(':sequencecheck', 'answer');
        }
      }
    }

    return null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String? _extractTag(String html, String className) {
    final re = RegExp(
      'class="[^"]*$className[^"]*"',
      caseSensitive: false,
    );
    final start = re.firstMatch(html)?.start;
    if (start == null) return null;

    int tagStart = html.lastIndexOf('<', start);
    if (tagStart < 0) return null;

    int depth = 1;
    int i = html.indexOf('>', tagStart) + 1;
    while (i < html.length && depth > 0) {
      final openDiv = html.indexOf('<div', i);
      final closeDiv = html.indexOf('</div', i);
      if (closeDiv < 0) break;
      if (openDiv >= 0 && openDiv < closeDiv) {
        depth++;
        i = openDiv + 4;
      } else {
        depth--;
        if (depth == 0) return html.substring(tagStart, closeDiv);
        i = closeDiv + 5;
      }
    }
    return null;
  }

  static String _removeBlock(String html, String pattern) {
    final re = RegExp(pattern, caseSensitive: false);
    final match = re.firstMatch(html);
    if (match == null) return html;

    int tagStart = html.lastIndexOf('<', match.start);
    if (tagStart < 0) return html;

    int depth = 1;
    int i = html.indexOf('>', tagStart) + 1;
    while (i < html.length && depth > 0) {
      final open = html.indexOf('<div', i);
      final close = html.indexOf('</div', i);
      if (close < 0) break;
      if (open >= 0 && open < close) {
        depth++;
        i = open + 4;
      } else {
        depth--;
        if (depth == 0) {
          final end = html.indexOf('>', close) + 1;
          return html.substring(0, tagStart) + html.substring(end);
        }
        i = close + 5;
      }
    }
    return html;
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(
            RegExp(r'<br\s*/?>|</p>|</li>|</div>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}

class _ChoiceContent {
  final String text;
  final String html;

  const _ChoiceContent({required this.text, required this.html});

  bool get hasContent => text.isNotEmpty || html.isNotEmpty;
}
