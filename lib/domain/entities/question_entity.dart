import 'package:equatable/equatable.dart';

import '../../core/utils/moodle_html_parser.dart'
    show
        MatchData,
        GapInputData,
        DdMarkerData,
        MoodleAnswerControl,
        ParsedChoice;

/// Representa uma questão do Moodle já parseada e pronta para exibição.
class QuestionEntity extends Equatable {
  final int slot; // slot Moodle (1-indexed)
  final int page; // página da questão (0-indexed)
  final String text; // enunciado sem tags HTML (fallback)
  final String htmlText; // enunciado como HTML com URLs corrigidas
  final String displayHtml; // HTML completo para exibição somente leitura
  final List<ParsedChoice> choices;
  final List<String> imageUrls;
  final String
      inputBaseName; // "q{attemptId}:{slot}_answer" (base para seqcheck)
  final String seqCheck;
  final String type; // tipo real do Moodle
  final String generalFeedback;
  final String rightAnswerHtml;
  final List<MoodleAnswerControl> answerControls;

  // Dados específicos por tipo
  final String? answerInputName; // campo de texto para numerical/shortanswer
  final MatchData? matchData; // estrutura de associação (match)
  final GapInputData? gapInputData; // estrutura de lacunas (gapselect/ddwtos)
  final DdMarkerData? ddMarkerData; // estrutura de marcadores sobre imagem

  const QuestionEntity({
    required this.slot,
    required this.page,
    required this.text,
    this.htmlText = '',
    this.displayHtml = '',
    required this.choices,
    this.imageUrls = const [],
    required this.inputBaseName,
    required this.seqCheck,
    this.type = 'multichoice',
    this.generalFeedback = '',
    this.rightAnswerHtml = '',
    this.answerControls = const [],
    this.answerInputName,
    this.matchData,
    this.gapInputData,
    this.ddMarkerData,
  });

  // ── Classificação por tipo ─────────────────────────────────────────────────

  /// Múltipla escolha ou V/F (radio buttons): interativo com botões.
  bool get isMultiChoice =>
      type == 'multichoice' || type == 'truefalse' || type == 'calculatedmulti';

  /// Numérica ou Calculada: campo de texto numérico.
  bool get isNumerical =>
      type == 'numerical' || type == 'calculated' || type == 'calculatedsimple';

  /// Resposta curta: campo de texto livre.
  bool get isShortAnswer => type == 'shortanswer';

  /// Associação (match): pares de premissas e respostas via dropdowns.
  bool get isMatch => type == 'match';

  /// Selecionar palavras que faltam (gapselect): dropdowns inline no texto.
  bool get isGapSelect => type == 'gapselect';

  /// Arrastar e soltar palavras no texto (ddwtos): palavras e lacunas.
  bool get isDdwtos => type == 'ddwtos';

  /// Respostas embutidas (Cloze/multianswer): mix de tipos.
  bool get isCloze => type == 'multianswer';

  /// Ordenação: lista reordenável.
  bool get isOrdering => type == 'ordering';

  /// Dissertativa: sem auto-avaliação.
  bool get isEssay => type == 'essay';

  /// GeoGebra: applet externo.
  bool get isGeoGebra => type == 'geogebra';

  /// Arrastar e soltar em imagem.
  bool get isDdImage => type == 'ddimageortext' || type == 'ddmarker';

  /// Tipos que têm widget interativo no app.
  bool get isInteractive =>
      isMultiChoice ||
      isNumerical ||
      isShortAnswer ||
      isMatch ||
      isGapSelect ||
      isDdwtos ||
      isCloze ||
      isOrdering ||
      isEssay ||
      (isDdImage && ddMarkerData != null) ||
      answerControls.any((c) => c.isAnswerable);

  @override
  List<Object?> get props => [slot];
}
