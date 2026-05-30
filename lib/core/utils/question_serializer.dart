import 'dart:convert';

import '../../domain/entities/question_entity.dart';
import 'moodle_html_parser.dart';

/// Serializa e desserializa [QuestionEntity] para/de um schema canônico v2.
class QuestionSerializer {
  static const int _schemaVersion = 2;

  static Map<String, dynamic> toJson(QuestionEntity q) {
    final promptHtml = q.htmlText.trim().isNotEmpty
        ? q.htmlText
        : '<p>${_escapeHtml(q.text)}</p>';

    final payload = <String, dynamic>{
      'schema_version': _schemaVersion,
      'slot': q.slot,
      'page': q.page,
      'type': q.type,
      'prompt': {
        'text': q.text,
        'html': promptHtml,
      },
      'interaction': {
        'input_base_name': q.inputBaseName,
        'seq_check': q.seqCheck,
      },
      'feedback': {
        'general': q.generalFeedback,
        'right_answer_html': q.rightAnswerHtml,
      },
      'media': {
        'image_urls': q.imageUrls,
      },
    };

    if (q.answerInputName != null && q.answerInputName!.trim().isNotEmpty) {
      (payload['interaction'] as Map<String, dynamic>)['answer_input_name'] =
          q.answerInputName;
    }

    if (q.choices.isNotEmpty) {
      payload['choices'] = q.choices.map(_choiceToJson).toList();
    }

    if (q.answerControls.isNotEmpty) {
      payload['answer_controls'] =
          q.answerControls.map(_controlToJson).toList();
    }

    if (q.matchData != null) {
      payload['type_data'] = {
        'match': _matchToJson(q.matchData!),
      };
    } else if (q.gapInputData != null) {
      payload['type_data'] = {
        'gap': _gapToJson(q.gapInputData!),
      };
    } else if (q.ddMarkerData != null) {
      payload['type_data'] = {
        'dd_marker': _ddMarkerToJson(q.ddMarkerData!),
      };
    }

    return payload;
  }

  static QuestionEntity fromJson(Map<String, dynamic> j) {
    final schemaVersion = j['schema_version'];
    if (schemaVersion != _schemaVersion) {
      throw const FormatException(
        'Unsupported question schema. Expected schema_version=2.',
      );
    }

    final prompt = _obj(j['prompt']);
    final interaction = _obj(j['interaction']);
    final feedback = _obj(j['feedback']);
    final media = _obj(j['media']);
    final typeData = _obj(j['type_data']);

    final text = prompt['text'] as String? ?? '';
    final htmlText = prompt['html'] as String? ?? '';
    final displayHtml = prompt['display_html'] as String? ?? htmlText;
    final type = j['type'] as String? ?? 'multichoice';

    MatchData? matchData;
    GapInputData? gapInputData;
    DdMarkerData? ddMarkerData;

    final matchMap = _obj(typeData['match']);
    if (matchMap.isNotEmpty) {
      matchData = _matchFromJson(matchMap);
    }
    final gapMap = _obj(typeData['gap']);
    if (gapMap.isNotEmpty) {
      gapInputData = _gapFromJson(gapMap);
    }
    final ddMarkerMap = _obj(typeData['dd_marker']);
    if (ddMarkerMap.isNotEmpty) {
      ddMarkerData = _ddMarkerFromJson(ddMarkerMap);
    }

    return QuestionEntity(
      slot: j['slot'] as int? ?? 1,
      page: j['page'] as int? ?? 0,
      text: text,
      htmlText: htmlText,
      displayHtml: displayHtml,
      type: type,
      generalFeedback: feedback['general'] as String? ?? '',
      rightAnswerHtml: feedback['right_answer_html'] as String? ?? '',
      inputBaseName: interaction['input_base_name'] as String? ?? '',
      seqCheck: interaction['seq_check'] as String? ?? '',
      answerInputName: interaction['answer_input_name'] as String?,
      imageUrls: _strList(media['image_urls']),
      choices: _list(j['choices']).map(_choiceFromJson).toList(),
      answerControls:
          _list(j['answer_controls']).map(_controlFromJson).toList(),
      matchData: matchData,
      gapInputData: gapInputData,
      ddMarkerData: ddMarkerData,
    );
  }

  /// Converte para string JSON para armazenamento na coluna TEXT do SQLite.
  static String encode(QuestionEntity q) => jsonEncode(toJson(q));

  static QuestionEntity decode(String data) =>
      fromJson(jsonDecode(data) as Map<String, dynamic>);

  // ── ParsedChoice ────────────────────────────────────────────────────────────

  static Map<String, dynamic> _choiceToJson(ParsedChoice c) => {
        'value': c.value,
        'text': c.text,
        'html_text': c.htmlText,
        'is_correct': c.isCorrect,
      };

  static ParsedChoice _choiceFromJson(Map<String, dynamic> j) => ParsedChoice(
        value: j['value'] as String? ?? '',
        text: j['text'] as String? ?? '',
        htmlText: j['html_text'] as String? ?? '',
        isCorrect: j['is_correct'] as bool? ?? false,
      );

  // ── MoodleAnswerControl ─────────────────────────────────────────────────────

  static Map<String, dynamic> _controlToJson(MoodleAnswerControl c) => {
        'name': c.name,
        'type': c.type,
        'value': c.value,
        'label': c.label,
        'html_label': c.htmlLabel,
        'options': c.options.map(_choiceToJson).toList(),
      };

  static MoodleAnswerControl _controlFromJson(Map<String, dynamic> j) =>
      MoodleAnswerControl(
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? 'text',
        value: j['value'] as String? ?? '',
        label: j['label'] as String? ?? '',
        htmlLabel: j['html_label'] as String? ?? '',
        options: _list(j['options']).map(_choiceFromJson).toList(),
      );

  // ── MatchData ───────────────────────────────────────────────────────────────

  static Map<String, dynamic> _matchToJson(MatchData m) => {
        'sub_questions': m.subQuestions.map(_subQToJson).toList(),
        'options': m.options.map(_choiceToJson).toList(),
      };

  static MatchData _matchFromJson(Map<String, dynamic> j) => MatchData(
        subQuestions: _list(j['sub_questions']).map(_subQFromJson).toList(),
        options: _list(j['options']).map(_choiceFromJson).toList(),
      );

  static Map<String, dynamic> _subQToJson(MatchSubQuestion s) => {
        'text': s.text,
        'html_text': s.htmlText,
        'input_name': s.inputName,
        'correct_value': s.correctValue,
      };

  static MatchSubQuestion _subQFromJson(Map<String, dynamic> j) =>
      MatchSubQuestion(
        text: j['text'] as String? ?? '',
        htmlText: j['html_text'] as String? ?? '',
        inputName: j['input_name'] as String? ?? '',
        correctValue: j['correct_value'] as String?,
      );

  // ── GapInputData ────────────────────────────────────────────────────────────

  static Map<String, dynamic> _gapToJson(GapInputData g) => {
        'gap_count': g.gapCount,
        'input_name_prefix': g.inputNamePrefix,
        'options': g.options.map(_choiceToJson).toList(),
        'options_by_gap': g.optionsByGap
            .map((list) => list.map(_choiceToJson).toList())
            .toList(),
      };

  static GapInputData _gapFromJson(Map<String, dynamic> j) => GapInputData(
        gapCount: j['gap_count'] as int? ?? 0,
        inputNamePrefix: j['input_name_prefix'] as String? ?? '',
        options: _list(j['options']).map(_choiceFromJson).toList(),
        optionsByGap: (_list(j['options_by_gap']))
            .map((inner) =>
                _list(inner as Object?).map(_choiceFromJson).toList())
            .toList(),
      );

  // ── DdMarkerData ────────────────────────────────────────────────────────────

  static Map<String, dynamic> _ddMarkerToJson(DdMarkerData d) => {
        'background_image_url': d.backgroundImageUrl,
        'choices': d.choices
            .map((c) => {
                  'choice_no': c.choiceNo,
                  'input_name': c.inputName,
                  'text': c.text,
                  'infinite': c.infinite,
                  'no_of_drags': c.noOfDrags,
                })
            .toList(),
      };

  static DdMarkerData _ddMarkerFromJson(Map<String, dynamic> j) => DdMarkerData(
        backgroundImageUrl: j['background_image_url'] as String? ?? '',
        choices: _list(j['choices'])
            .map((c) => DdMarkerChoice(
                  choiceNo: c['choice_no'] as int? ?? 0,
                  inputName: c['input_name'] as String? ?? '',
                  text: c['text'] as String? ?? '',
                  infinite: c['infinite'] as bool? ?? false,
                  noOfDrags: c['no_of_drags'] as int? ?? 1,
                ))
            .toList(),
      );

  // ── Helpers ─────────────────────────────────────────────────────────────────

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

  static String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
