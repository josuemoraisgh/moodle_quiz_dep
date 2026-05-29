import 'dart:convert';

import '../../domain/entities/question_entity.dart';
import 'moodle_html_parser.dart';

/// Serializa e desserializa [QuestionEntity] para/de JSON (armazenamento SQLite).
class QuestionSerializer {
  static Map<String, dynamic> toJson(QuestionEntity q) {
    return {
      'slot': q.slot,
      'page': q.page,
      'text': q.text,
      'html_text': q.htmlText,
      'display_html': q.displayHtml,
      'type': q.type,
      'general_feedback': q.generalFeedback,
      'right_answer_html': q.rightAnswerHtml,
      'input_base_name': q.inputBaseName,
      'seq_check': q.seqCheck,
      'answer_input_name': q.answerInputName,
      'image_urls': q.imageUrls,
      'choices': q.choices.map(_choiceToJson).toList(),
      'answer_controls': q.answerControls.map(_controlToJson).toList(),
      'match_data': q.matchData == null ? null : _matchToJson(q.matchData!),
      'gap_input_data':
          q.gapInputData == null ? null : _gapToJson(q.gapInputData!),
      'dd_marker_data':
          q.ddMarkerData == null ? null : _ddMarkerToJson(q.ddMarkerData!),
    };
  }

  static QuestionEntity fromJson(Map<String, dynamic> j) {
    return QuestionEntity(
      slot: j['slot'] as int? ?? 1,
      page: j['page'] as int? ?? 0,
      text: j['text'] as String? ?? '',
      htmlText: j['html_text'] as String? ?? '',
      displayHtml: j['display_html'] as String? ?? '',
      type: j['type'] as String? ?? 'multichoice',
      generalFeedback: j['general_feedback'] as String? ?? '',
      rightAnswerHtml: j['right_answer_html'] as String? ?? '',
      inputBaseName: j['input_base_name'] as String? ?? '',
      seqCheck: j['seq_check'] as String? ?? '',
      answerInputName: j['answer_input_name'] as String?,
      imageUrls: _strList(j['image_urls']),
      choices: _list(j['choices']).map(_choiceFromJson).toList(),
      answerControls:
          _list(j['answer_controls']).map(_controlFromJson).toList(),
      matchData: j['match_data'] == null
          ? null
          : _matchFromJson(j['match_data'] as Map<String, dynamic>),
      gapInputData: j['gap_input_data'] == null
          ? null
          : _gapFromJson(j['gap_input_data'] as Map<String, dynamic>),
      ddMarkerData: j['dd_marker_data'] == null
          ? null
          : _ddMarkerFromJson(j['dd_marker_data'] as Map<String, dynamic>),
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
        subQuestions:
            _list(j['sub_questions']).map(_subQFromJson).toList(),
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

  static DdMarkerData _ddMarkerFromJson(Map<String, dynamic> j) =>
      DdMarkerData(
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
}
