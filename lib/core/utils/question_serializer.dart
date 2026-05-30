import 'dart:convert';

import '../../domain/entities/question_entity.dart';
import 'moodle_html_parser.dart';

/// Serializa e desserializa [QuestionEntity] para/de schema v3.
///
/// Mudanças em relação ao v2:
///  - Campos planos (sem agrupamentos prompt/interaction/feedback/media)
///  - Campos de texto puro removidos: derivados do HTML no decode
///  - Chaves curtas em choices/controls/opts: {v, h, ok}
class QuestionSerializer {
  static const int _schemaVersion = 3;

  // ── Encode ──────────────────────────────────────────────────────────────────

  static Map<String, dynamic> toJson(QuestionEntity q) {
    final html = q.htmlText.trim().isNotEmpty
        ? q.htmlText
        : '<p>${_escapeHtml(q.text)}</p>';

    final payload = <String, dynamic>{
      'v': _schemaVersion,
      'slot': q.slot,
      'page': q.page,
      'type': q.type,
      'html': html,
      'input': q.inputBaseName,
      'seq': q.seqCheck,
    };

    if (q.generalFeedback.isNotEmpty) payload['feedback'] = q.generalFeedback;
    if (q.rightAnswerHtml.isNotEmpty) payload['answer_html'] = q.rightAnswerHtml;
    if (q.imageUrls.isNotEmpty) payload['images'] = q.imageUrls;
    if (q.answerInputName != null && q.answerInputName!.trim().isNotEmpty) {
      payload['answer_field'] = q.answerInputName;
    }
    if (q.choices.isNotEmpty) {
      payload['choices'] = q.choices.map(_choiceToJson).toList();
    }
    if (q.answerControls.isNotEmpty) {
      payload['controls'] = q.answerControls.map(_controlToJson).toList();
    }
    if (q.matchData != null) payload['match'] = _matchToJson(q.matchData!);
    if (q.gapInputData != null) payload['gap'] = _gapToJson(q.gapInputData!);
    if (q.ddMarkerData != null) payload['dd'] = _ddMarkerToJson(q.ddMarkerData!);

    return payload;
  }

  // ── Decode ──────────────────────────────────────────────────────────────────

  static QuestionEntity fromJson(Map<String, dynamic> j) {
    final version = j['v'] ?? j['schema_version'];
    if (version == 2) return _fromJsonV2(j);
    if (version != _schemaVersion) {
      throw FormatException(
        'Schema de questão não suportado. Esperado v$_schemaVersion, recebido v$version.',
      );
    }

    final htmlText = j['html'] as String? ?? '';
    final type = j['type'] as String? ?? 'multichoice';

    MatchData? matchData;
    GapInputData? gapInputData;
    DdMarkerData? ddMarkerData;

    final matchMap = _obj(j['match']);
    if (matchMap.isNotEmpty) matchData = _matchFromJson(matchMap);

    final gapMap = _obj(j['gap']);
    if (gapMap.isNotEmpty) gapInputData = _gapFromJson(gapMap);

    final ddMap = _obj(j['dd']);
    if (ddMap.isNotEmpty) ddMarkerData = _ddMarkerFromJson(ddMap);

    return QuestionEntity(
      slot: j['slot'] as int? ?? 1,
      page: j['page'] as int? ?? 0,
      text: _stripHtml(htmlText),
      htmlText: htmlText,
      displayHtml: htmlText,
      type: type,
      generalFeedback: j['feedback'] as String? ?? '',
      rightAnswerHtml: j['answer_html'] as String? ?? '',
      inputBaseName: j['input'] as String? ?? '',
      seqCheck: j['seq'] as String? ?? '',
      answerInputName: j['answer_field'] as String?,
      imageUrls: _strList(j['images']),
      choices: _list(j['choices']).map(_choiceFromJson).toList(),
      answerControls: _list(j['controls']).map(_controlFromJson).toList(),
      matchData: matchData,
      gapInputData: gapInputData,
      ddMarkerData: ddMarkerData,
    );
  }

  /// Retrocompatibilidade: lê schema v2 antigo e devolve [QuestionEntity].
  static QuestionEntity _fromJsonV2(Map<String, dynamic> j) {
    final prompt = _obj(j['prompt']);
    final interaction = _obj(j['interaction']);
    final feedback = _obj(j['feedback']);
    final media = _obj(j['media']);
    final typeData = _obj(j['type_data']);

    final htmlText = prompt['html'] as String? ?? '';

    MatchData? matchData;
    GapInputData? gapInputData;
    DdMarkerData? ddMarkerData;

    final matchMap = _obj(typeData['match']);
    if (matchMap.isNotEmpty) matchData = _matchFromJson(matchMap);

    final gapMap = _obj(typeData['gap']);
    if (gapMap.isNotEmpty) gapInputData = _gapFromJson(gapMap);

    final ddMap = _obj(typeData['dd_marker']);
    if (ddMap.isNotEmpty) ddMarkerData = _ddMarkerFromJson(ddMap);

    return QuestionEntity(
      slot: j['slot'] as int? ?? 1,
      page: j['page'] as int? ?? 0,
      text: prompt['text'] as String? ?? _stripHtml(htmlText),
      htmlText: htmlText,
      displayHtml: prompt['display_html'] as String? ?? htmlText,
      type: j['type'] as String? ?? 'multichoice',
      generalFeedback: feedback['general'] as String? ?? '',
      rightAnswerHtml: feedback['right_answer_html'] as String? ?? '',
      inputBaseName: interaction['input_base_name'] as String? ?? '',
      seqCheck: interaction['seq_check'] as String? ?? '',
      answerInputName: interaction['answer_input_name'] as String?,
      imageUrls: _strList(media['image_urls']),
      choices: _list(j['choices']).map(_choiceFromJsonV2).toList(),
      answerControls: _list(j['answer_controls']).map(_controlFromJsonV2).toList(),
      matchData: matchData,
      gapInputData: gapInputData,
      ddMarkerData: ddMarkerData,
    );
  }

  static String encode(QuestionEntity q) => jsonEncode(toJson(q));

  static QuestionEntity decode(String data) =>
      fromJson(jsonDecode(data) as Map<String, dynamic>);

  // ── ParsedChoice ─────────────────────────────────────────────────────────────

  static Map<String, dynamic> _choiceToJson(ParsedChoice c) => {
        'v': c.value,
        'h': c.htmlText.isNotEmpty ? c.htmlText : '<p>${_escapeHtml(c.text)}</p>',
        'ok': c.isCorrect,
      };

  static ParsedChoice _choiceFromJson(Map<String, dynamic> j) {
    final html = j['h'] as String? ?? '';
    return ParsedChoice(
      value: j['v'] as String? ?? '',
      text: _stripHtml(html),
      htmlText: html,
      isCorrect: j['ok'] as bool? ?? false,
    );
  }

  // v2 compat
  static ParsedChoice _choiceFromJsonV2(Map<String, dynamic> j) =>
      ParsedChoice(
        value: j['value'] as String? ?? '',
        text: j['text'] as String? ?? '',
        htmlText: j['html_text'] as String? ?? '',
        isCorrect: j['is_correct'] as bool? ?? false,
      );

  // ── MoodleAnswerControl ───────────────────────────────────────────────────────

  static Map<String, dynamic> _controlToJson(MoodleAnswerControl c) {
    final html = c.htmlLabel.isNotEmpty
        ? c.htmlLabel
        : '<p>${_escapeHtml(c.label)}</p>';
    final m = <String, dynamic>{
      'name': c.name,
      'type': c.type,
      'hl': html,
    };
    if (c.value.isNotEmpty) m['value'] = c.value;
    if (c.options.isNotEmpty) m['opts'] = c.options.map(_choiceToJson).toList();
    return m;
  }

  static MoodleAnswerControl _controlFromJson(Map<String, dynamic> j) {
    final html = j['hl'] as String? ?? '';
    return MoodleAnswerControl(
      name: j['name'] as String? ?? '',
      type: j['type'] as String? ?? 'text',
      value: j['value'] as String? ?? '',
      label: _stripHtml(html),
      htmlLabel: html,
      options: _list(j['opts']).map(_choiceFromJson).toList(),
    );
  }

  // v2 compat
  static MoodleAnswerControl _controlFromJsonV2(Map<String, dynamic> j) =>
      MoodleAnswerControl(
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? 'text',
        value: j['value'] as String? ?? '',
        label: j['label'] as String? ?? '',
        htmlLabel: j['html_label'] as String? ?? '',
        options: _list(j['options']).map(_choiceFromJsonV2).toList(),
      );

  // ── MatchData ─────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _matchToJson(MatchData m) => {
        'subs': m.subQuestions.map(_subQToJson).toList(),
        'opts': m.options.map(_choiceToJson).toList(),
      };

  static MatchData _matchFromJson(Map<String, dynamic> j) => MatchData(
        subQuestions: _list(j['subs']).map(_subQFromJson).toList(),
        options: _list(j['opts']).map(_choiceFromJson).toList(),
      );

  static Map<String, dynamic> _subQToJson(MatchSubQuestion s) {
    final html = s.htmlText.isNotEmpty
        ? s.htmlText
        : '<p>${_escapeHtml(s.text)}</p>';
    final m = <String, dynamic>{'h': html, 'name': s.inputName};
    if (s.correctValue != null) m['correct'] = s.correctValue;
    return m;
  }

  static MatchSubQuestion _subQFromJson(Map<String, dynamic> j) {
    final html = j['h'] as String? ?? '';
    return MatchSubQuestion(
      text: _stripHtml(html),
      htmlText: html,
      inputName: j['name'] as String? ?? '',
      correctValue: j['correct'] as String?,
    );
  }

  // ── GapInputData ──────────────────────────────────────────────────────────────

  static Map<String, dynamic> _gapToJson(GapInputData g) {
    final m = <String, dynamic>{
      'count': g.gapCount,
      'prefix': g.inputNamePrefix,
      'opts': g.options.map(_choiceToJson).toList(),
    };
    if (g.optionsByGap.isNotEmpty) {
      m['by_gap'] =
          g.optionsByGap.map((l) => l.map(_choiceToJson).toList()).toList();
    }
    return m;
  }

  static GapInputData _gapFromJson(Map<String, dynamic> j) => GapInputData(
        gapCount: j['count'] as int? ?? 0,
        inputNamePrefix: j['prefix'] as String? ?? '',
        options: _list(j['opts']).map(_choiceFromJson).toList(),
        optionsByGap: (_list(j['by_gap']))
            .map((inner) => _list(inner as Object?).map(_choiceFromJson).toList())
            .toList(),
      );

  // ── DdMarkerData ──────────────────────────────────────────────────────────────

  static Map<String, dynamic> _ddMarkerToJson(DdMarkerData d) => {
        'bg': d.backgroundImageUrl,
        'choices': d.choices
            .map((c) => {
                  'no': c.choiceNo,
                  'name': c.inputName,
                  'h': c.text,
                  'inf': c.infinite,
                  'n': c.noOfDrags,
                })
            .toList(),
      };

  static DdMarkerData _ddMarkerFromJson(Map<String, dynamic> j) => DdMarkerData(
        backgroundImageUrl: j['bg'] as String? ?? '',
        choices: _list(j['choices'])
            .map((c) => DdMarkerChoice(
                  choiceNo: c['no'] as int? ?? 0,
                  inputName: c['name'] as String? ?? '',
                  text: c['h'] as String? ?? '',
                  infinite: c['inf'] as bool? ?? false,
                  noOfDrags: c['n'] as int? ?? 1,
                ))
            .toList(),
      );

  // ── Helpers ───────────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _list(Object? raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  static List<String> _strList(Object? raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  static Map<String, dynamic> _obj(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  static String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  static String _stripHtml(String html) =>
      html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
}
