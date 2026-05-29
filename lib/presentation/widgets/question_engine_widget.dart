import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/moodle_html_parser.dart'
    show
        DdMarkerChoice,
        DdMarkerData,
        MoodleAnswerControl,
        MoodleHtmlParser,
        ParsedChoice;
import '../../core/utils/responsive.dart';
import '../../domain/entities/question_entity.dart';
import 'moodle_html_renderer.dart';
import 'option_button.dart';
import 'timer_widget.dart';

enum QuestionEngineMode { answer, preview, reveal }

enum _PromptQuality { empty, markersOnly, visibleText }

class QuestionEngineWidget extends StatelessWidget {
  final QuestionEntity question;
  final QuestionEngineMode mode;
  final DateTime? endsAt;
  final Map<String, String> selectedAnswers;
  final bool hasAnswered;
  final bool isSubmitting;
  final bool showCorrect;
  final bool compact;
  final void Function(String inputName, String value)? onSelectAnswer;
  final VoidCallback? onSubmit;

  const QuestionEngineWidget({
    super.key,
    required this.question,
    required this.mode,
    this.endsAt,
    this.selectedAnswers = const {},
    this.hasAnswered = false,
    this.isSubmitting = false,
    this.showCorrect = false,
    this.compact = false,
    this.onSelectAnswer,
    this.onSubmit,
  });

  bool get _isAnswerMode => mode == QuestionEngineMode.answer;
  // Controles interativos sempre que um callback de seleção foi fornecido,
  // exceto no modo reveal ou quando já respondido.
  bool get _controlsDisabled =>
      mode == QuestionEngineMode.reveal ||
      hasAnswered ||
      onSelectAnswer == null;

  static const _letters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final spec = _uiSpec;
    final textStyle = GoogleFonts.nunito(
      fontSize: compact ? 14 : (isMobile ? 16 : 18),
      fontWeight: FontWeight.w600,
      color: AppTheme.textPrimary,
      height: 1.5,
    );

    final children = <Widget>[
      if (_isAnswerMode) ...[
        _buildTimer(),
        SizedBox(height: compact ? 10 : 16),
      ],
      _buildQuestionTypeHeader(spec),
      SizedBox(height: compact ? 8 : 12),
      _buildQuestionPrompt(textStyle),
      SizedBox(height: compact ? 10 : 16),
      ..._buildAnswerSurface(textStyle),
      if (_isAnswerMode) ...[
        SizedBox(height: compact ? 12 : 20),
        _buildSubmitButton(_hasAnswer),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildQuestionTypeHeader(_QuestionUiSpec spec) {
    final titleStyle = TextStyle(
      color: AppTheme.textPrimary,
      fontSize: compact ? 12 : 13,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.2,
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: spec.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: spec.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(spec.icon, color: spec.color, size: compact ? 16 : 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(spec.title, style: titleStyle),
                const SizedBox(height: 3),
                Text(
                  spec.instruction,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimer() {
    if (endsAt != null) return TimerWidget(endsAt: endsAt!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: AppTheme.cardDecoration(),
      child: const Row(
        children: [
          Icon(Icons.hourglass_top_rounded, color: AppTheme.warning, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'O cronometro vai comecar quando a primeira resposta for enviada.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionPrompt(TextStyle textStyle) {
    final html = _promptHtml;
    final content = (question.isGapSelect || question.isDdwtos) &&
            question.gapInputData != null
        ? _buildGapInlinePrompt(textStyle)
        : html.isNotEmpty
            ? MoodleHtmlRenderer(html: html, textStyle: textStyle)
            : Text(question.text, style: textStyle);

    if (compact) return content;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration(glowing: _isAnswerMode),
      child: content,
    );
  }

  String get _promptHtml {
    if (question.isMultiChoice && question.choices.isNotEmpty) {
      return question.htmlText;
    }
    if (question.isDdImage && question.ddMarkerData != null) {
      return question.htmlText;
    }
    if (question.isMatch && question.matchData != null) {
      return question.htmlText.isNotEmpty ? question.htmlText : question.text;
    }
    if (question.isOrdering) {
      return question.htmlText.isNotEmpty ? question.htmlText : question.text;
    }
    if ((question.isGapSelect || question.isDdwtos) &&
        question.gapInputData != null) {
      return _gapPromptHtml;
    }
    return question.displayHtml.isNotEmpty
        ? question.displayHtml
        : question.htmlText;
  }

  String get _gapPromptHtml {
    String? markerOnlyPrompt;
    final sources = <String>[
      question.htmlText,
      question.displayHtml,
    ].where((source) => source.trim().isNotEmpty);

    for (final source in sources) {
      final prompt = MoodleHtmlParser.extractTextWithGapMarkers(source, '', '');
      final quality = _promptQuality(prompt);
      if (quality == _PromptQuality.visibleText) return prompt;
      if (quality == _PromptQuality.markersOnly && markerOnlyPrompt == null) {
        markerOnlyPrompt = prompt;
      }
    }

    if (question.text.trim().isNotEmpty) return question.text;
    return markerOnlyPrompt ?? '';
  }

  static _PromptQuality _promptQuality(String html) {
    final text = html
        .replaceAll(
            RegExp(r'<script\b[^>]*>.*?</script>',
                caseSensitive: false, dotAll: true),
            ' ')
        .replaceAll(
            RegExp(r'<style\b[^>]*>.*?</style>',
                caseSensitive: false, dotAll: true),
            ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'&(?:nbsp|#160);'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.isEmpty) return _PromptQuality.empty;

    final signal = text
        .replaceAll(RegExp(r'\[\d+\]'), '')
        .replaceAll(RegExp(r'[.,;:()\[\]\s]+'), '')
        .trim();
    if (signal.isNotEmpty) return _PromptQuality.visibleText;
    return RegExp(r'\[\d+\]').hasMatch(text)
        ? _PromptQuality.markersOnly
        : _PromptQuality.empty;
  }

  List<Widget> _buildAnswerSurface(TextStyle textStyle) {
    final surface = <Widget>[];

    if (question.isOrdering && _orderingControls.isNotEmpty) {
      surface.add(_buildOrderingInputs(textStyle));
    } else if (question.isMultiChoice && question.choices.isNotEmpty) {
      surface.addAll(_buildChoiceInputs());
    } else {
      if (question.isMatch && question.matchData != null) {
        surface.add(_buildMatchInputs(textStyle));
      } else if (question.isDdImage && question.ddMarkerData != null) {
        surface.add(_buildDdMarkerInputs());
      } else if ((question.isGapSelect || question.isDdwtos) &&
          question.gapInputData != null) {
        if (!_gapPromptHasInlineTargets) {
          surface.add(_buildGapInputs());
        }
      } else {
        final checkboxControls = _answerableControls
            .where((c) => c.isMultipleChoice)
            .toList(growable: false);
        if (checkboxControls.isNotEmpty) {
          surface.add(_buildCheckboxInputs(checkboxControls));
        } else {
          final genericControls = _genericControls;
          if (genericControls.isNotEmpty) {
            surface.add(_buildGenericControls(genericControls));
          }
        }
      }
    }

    if (surface.isNotEmpty) {
      if (!_isAnswerMode &&
          showCorrect &&
          question.rightAnswerHtml.isNotEmpty) {
        surface.add(SizedBox(height: compact ? 8 : 12));
        surface.add(_buildRightAnswerCard(textStyle));
      } else if (!_isAnswerMode &&
          showCorrect &&
          question.rightAnswerHtml.isEmpty) {
        surface.add(SizedBox(height: compact ? 8 : 12));
        surface.add(
          _buildInfoBanner(
            icon: Icons.rule_rounded,
            color: AppTheme.warning,
            message:
                'O Moodle nao retornou o bloco de resposta correta para este tipo nesta tentativa/revisao.',
          ),
        );
      }
      return surface;
    }

    if (!_isAnswerMode && showCorrect && question.rightAnswerHtml.isNotEmpty) {
      return [_buildRightAnswerCard(textStyle)];
    }

    if (_isAnswerMode) {
      final gap = question.gapInputData;
      if ((question.isGapSelect || question.isDdwtos) &&
          gap != null &&
          _gapPromptHasInlineTargets) {
        return const [];
      }
      return [
        _buildInfoBanner(
          icon: Icons.info_outline_rounded,
          color: AppTheme.warning,
          message:
              'Este tipo de questao nao expos campos de resposta pela API. O enunciado foi aberto neste app, mas nao ha campos para envio.',
        ),
      ];
    }

    return const [];
  }

  List<MoodleAnswerControl> get _answerableControls =>
      question.answerControls.where((c) => c.isAnswerable).toList();

  List<MoodleAnswerControl> get _orderingControls => _answerableControls
      .where((c) => c.isSelect && c.options.isNotEmpty)
      .toList();

  Map<String, String> get _displaySelectedAnswers {
    if (_isAnswerMode || !showCorrect || question.rightAnswerHtml.isEmpty) {
      return selectedAnswers;
    }
    return {
      ...selectedAnswers,
      ..._correctAnswersFromRightAnswer(),
    };
  }

  List<MoodleAnswerControl> get _genericControls {
    final controls = _answerableControls.where((c) {
      if (c.isMultipleChoice) return false;
      if (question.isMatch && question.matchData != null) {
        return !question.matchData!.subQuestions
            .any((s) => s.inputName == c.name);
      }
      final gap = question.gapInputData;
      if (gap != null && c.name.startsWith(gap.inputNamePrefix)) {
        return false;
      }
      if (question.isMultiChoice && question.choices.isNotEmpty) return false;
      return true;
    }).toList();

    if (controls.isEmpty &&
        (question.isNumerical || question.isShortAnswer) &&
        question.answerInputName != null) {
      return [
        MoodleAnswerControl(
          name: question.answerInputName!,
          type: question.isNumerical ? 'number' : 'text',
        ),
      ];
    }

    return controls;
  }

  bool get _hasAnswer {
    if (question.isOrdering && _orderingControls.isNotEmpty) {
      return _orderingControls.every(
        (c) => (selectedAnswers[c.name] ?? '').trim().isNotEmpty,
      );
    }

    if (question.isMultiChoice && question.choices.isNotEmpty) {
      return (selectedAnswers[question.inputBaseName] ?? '').isNotEmpty;
    }

    if (question.isMatch && question.matchData != null) {
      return question.matchData!.subQuestions.every(
        (s) => (selectedAnswers[s.inputName] ?? '').isNotEmpty,
      );
    }

    final checkboxControls = _answerableControls
        .where((c) => c.isMultipleChoice)
        .toList(growable: false);
    if (checkboxControls.isNotEmpty) {
      return checkboxControls.any(
        (c) => (selectedAnswers[c.name] ?? '').isNotEmpty,
      );
    }

    final gap = question.gapInputData;
    if ((question.isGapSelect || question.isDdwtos) && gap != null) {
      return List.generate(gap.gapCount, (i) => gap.inputName(i + 1)).every(
        (name) => (selectedAnswers[name] ?? '').isNotEmpty,
      );
    }

    final ddMarker = question.ddMarkerData;
    if (question.isDdImage && ddMarker != null) {
      return ddMarker.choices.any(
        (choice) => (selectedAnswers[choice.inputName] ?? '').isNotEmpty,
      );
    }

    final controls = _genericControls;
    if (controls.isNotEmpty) {
      return controls.where((c) => !c.isMultipleChoice).every(
            (c) => (selectedAnswers[c.name] ?? '').trim().isNotEmpty,
          );
    }

    return selectedAnswers.values.any((v) => v.trim().isNotEmpty);
  }

  List<Widget> _buildChoiceInputs() {
    final selected = selectedAnswers[question.inputBaseName];
    final widgets = <Widget>[
      ...question.choices.asMap().entries.map((entry) {
        final index = entry.key;
        final choice = entry.value;
        final letter =
            index < _letters.length ? _letters[index] : '${index + 1}';
        final selectedByUser = selected == choice.value;
        final isCorrectState = showCorrect && choice.isCorrect;
        final isIncorrectState =
            showCorrect && selectedByUser && !choice.isCorrect;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OptionButton(
            label: letter,
            text: choice.text,
            htmlText: choice.htmlText,
            isSelected: selectedByUser || isCorrectState,
            isCorrectState: isCorrectState,
            isIncorrectState: isIncorrectState,
            isDisabled: _controlsDisabled,
            onTap: () =>
                onSelectAnswer?.call(question.inputBaseName, choice.value),
          ),
        );
      }),
    ];

    // No Moodle Mobile, questões de escolha única permitem limpar seleção.
    if (!_controlsDisabled && selected != null && selected.isNotEmpty) {
      widgets.add(
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () => onSelectAnswer?.call(question.inputBaseName, ''),
            icon: const Icon(Icons.clear_rounded, size: 16),
            label: const Text('Limpar escolha'),
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _badge(String text, bool correct) {
    final size = compact ? 26.0 : 34.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: correct ? AppTheme.success : AppTheme.bgDark,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: correct ? Colors.white : AppTheme.textSecondary,
          fontWeight: FontWeight.w800,
          fontSize: compact ? 12 : 15,
        ),
      ),
    );
  }

  Widget _buildCheckboxInputs(List<MoodleAnswerControl> controls) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: controls.map((control) {
          final selected = selectedAnswers[control.name] == control.value;
          return CheckboxListTile(
            value: selected,
            onChanged: _controlsDisabled
                ? null
                : (next) => onSelectAnswer?.call(
                      control.name,
                      next == true ? control.value : '',
                    ),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppTheme.primary,
            title: _controlLabel(control),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMatchInputs(TextStyle textStyle) {
    final matchData = question.matchData!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: matchData.subQuestions.asMap().entries.map((entry) {
          final index = entry.key;
          final sub = entry.value;
          final selected = selectedAnswers[sub.inputName] ??
              (!_isAnswerMode && showCorrect ? sub.correctValue : null);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _badge('${index + 1}', false),
                const SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: sub.htmlText.isNotEmpty
                      ? MoodleHtmlRenderer(
                          html: sub.htmlText,
                          textStyle: textStyle.copyWith(fontSize: 15),
                        )
                      : Text(sub.text, style: textStyle),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: _dropdown(
                    value: selected,
                    options: matchData.options,
                    hint: 'Escolha uma opcao...',
                    onChanged: (value) => onSelectAnswer?.call(
                      sub.inputName,
                      value ?? '',
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGapInputs() {
    final gap = question.gapInputData!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(gap.gapCount, (index) {
          final gapNum = index + 1;
          final inputName = gap.inputName(gapNum);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                _badge('[$gapNum]', false),
                const SizedBox(width: 10),
                Expanded(
                  child: _dropdown(
                    value: _displaySelectedAnswers[inputName],
                    options: gap.optionsForGap(gapNum),
                    hint: 'Preencha a lacuna [$gapNum]...',
                    onChanged: (value) => onSelectAnswer?.call(
                      inputName,
                      value ?? '',
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  bool get _gapPromptHasInlineTargets {
    final gap = question.gapInputData;
    if (gap == null) return false;
    final html = _gapInlineHtml;
    return RegExp(r'\[\d+\]').hasMatch(html) ||
        RegExp(r'<select\b', caseSensitive: false).hasMatch(html);
  }

  String get _gapInlineHtml {
    final markerHtml = _gapPromptHtml;
    if (_promptQuality(markerHtml) == _PromptQuality.visibleText) {
      return markerHtml;
    }
    if (question.displayHtml.trim().isNotEmpty) return question.displayHtml;
    return markerHtml;
  }

  Widget _buildGapInlinePrompt(TextStyle textStyle) {
    final gap = question.gapInputData!;
    final html = MoodleHtmlRenderer.prepareHtml(_gapInlineHtml);
    if (html.trim().isEmpty) return Text(question.text, style: textStyle);

    return HtmlWidget(
      html,
      textStyle: textStyle,
      customWidgetBuilder: (element) {
        final math = MoodleHtmlRenderer.buildMathWidgetForElement(
          element,
          textStyle,
        );
        if (math != null) return math;

        final gapNum = _gapNumberFromElement(element);
        if (gapNum == null || gapNum < 1 || gapNum > gap.gapCount) {
          return null;
        }
        final inputName = gap.inputName(gapNum);
        return InlineCustomWidget(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: _inlineDropdown(
              value: _displaySelectedAnswers[inputName],
              options: gap.optionsForGap(gapNum),
              hint: '[$gapNum]',
              onChanged: (value) => onSelectAnswer?.call(
                inputName,
                value ?? '',
              ),
            ),
          ),
        );
      },
      customStylesBuilder: (element) {
        if (element.localName == 'table') {
          return {
            'border-collapse': 'collapse',
            'width': 'auto',
            'max-width': '100%',
          };
        }
        if (element.localName == 'td' || element.localName == 'th') {
          return {'border': '1px solid #555', 'padding': '4px 8px'};
        }
        return null;
      },
    );
  }

  int? _gapNumberFromElement(dynamic element) {
    final localName = element.localName?.toString().toLowerCase() ?? '';
    if (localName != 'select' &&
        localName != 'span' &&
        localName != 'input' &&
        localName != 'textarea') {
      return null;
    }
    final name = element.attributes['name']?.toString() ?? '';
    final fromName = RegExp(r'(?:_p|gap|blank)(\d+)$', caseSensitive: false)
        .firstMatch(name)
        ?.group(1);
    if (fromName != null) return int.tryParse(fromName);

    final text = element.text?.toString() ?? '';
    final fromText = RegExp(r'\[(\d+)\]').firstMatch(text)?.group(1);
    if (fromText != null) return int.tryParse(fromText);
    return null;
  }

  Widget _buildDdMarkerInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoBanner(
          icon: Icons.touch_app_rounded,
          color: AppTheme.accent,
          message:
              'Selecione um marcador e toque na imagem para posicionar. Toque em um marcador existente para remover.',
        ),
        const SizedBox(height: 10),
        _DdMarkerInput(
          data: question.ddMarkerData!,
          selectedAnswers: selectedAnswers,
          disabled: _controlsDisabled,
          compact: compact,
          onChanged: (inputName, value) =>
              onSelectAnswer?.call(inputName, value),
        ),
      ],
    );
  }

  Widget _buildOrderingInputs(TextStyle textStyle) {
    return _OrderingInput(
      controls: _orderingControls,
      selectedAnswers: _displaySelectedAnswers,
      disabled: _controlsDisabled,
      compact: compact,
      textStyle: textStyle,
      onChanged: (inputName, value) => onSelectAnswer?.call(inputName, value),
    );
  }

  Map<String, String> _correctAnswersFromRightAnswer() {
    final html = question.rightAnswerHtml;
    if (html.trim().isEmpty) return const {};

    final result = <String, String>{};
    final plain = _normalizeAnswerText(_plainHtml(html));
    final gap = question.gapInputData;
    if ((question.isGapSelect || question.isDdwtos) && gap != null) {
      for (var i = 1; i <= gap.gapCount; i++) {
        final options = gap.optionsForGap(i);
        final value = _valueWhoseTextAppearsIn(plain, options);
        if (value != null) result[gap.inputName(i)] = value;
      }
    }

    if (question.isOrdering) {
      for (final control in _orderingControls) {
        final label = _normalizeAnswerText(
          control.label.isNotEmpty
              ? control.label
              : _plainHtml(control.htmlLabel),
        );
        if (label.isEmpty) continue;

        final rank = _rankBeforeLabel(plain, label);
        if (rank == null) continue;
        final value = _valueForRank(control, rank);
        if (value.isNotEmpty) result[control.name] = value;
      }
    }

    return result;
  }

  String? _valueWhoseTextAppearsIn(
    String plainRightAnswer,
    List<ParsedChoice> options,
  ) {
    final sorted = [...options]
      ..sort((a, b) => b.text.length.compareTo(a.text.length));
    for (final option in sorted) {
      final text = _normalizeAnswerText(option.text);
      if (text.isNotEmpty && plainRightAnswer.contains(text)) {
        return option.value;
      }
    }
    return null;
  }

  int? _rankBeforeLabel(String plainRightAnswer, String normalizedLabel) {
    final escaped = RegExp.escape(normalizedLabel);
    final match =
        RegExp(r'(?:^|\s)(\d+)\.?\s+' + escaped).firstMatch(plainRightAnswer);
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  String _valueForRank(MoodleAnswerControl control, int rank) {
    for (final option in control.options) {
      if (option.value.trim() == '$rank' || option.text.trim() == '$rank') {
        return option.value;
      }
    }
    final index = rank - 1;
    if (index >= 0 && index < control.options.length) {
      return control.options[index].value;
    }
    return '';
  }

  static String _plainHtml(String html) {
    return html
        .replaceAll(
            RegExp(r'<script\b[^>]*>.*?</script>',
                caseSensitive: false, dotAll: true),
            ' ')
        .replaceAll(
            RegExp(r'<style\b[^>]*>.*?</style>',
                caseSensitive: false, dotAll: true),
            ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
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

  static String _normalizeAnswerText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}%]+', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Widget _buildGenericControls(List<MoodleAnswerControl> controls) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: controls.map((control) {
          if (control.isSelect || control.isSingleChoice) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _labeledField(
                control,
                _dropdown(
                  value: selectedAnswers[control.name],
                  options: control.options,
                  hint: 'Escolha uma opcao...',
                  onChanged: (value) => onSelectAnswer?.call(
                    control.name,
                    value ?? '',
                  ),
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _labeledField(
              control,
              TextFormField(
                initialValue: selectedAnswers[control.name] ?? control.value,
                enabled: !_controlsDisabled,
                minLines: control.isLongText ? 4 : 1,
                maxLines: control.isLongText ? 8 : 1,
                keyboardType:
                    control.type == 'number' ? TextInputType.number : null,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: control.type == 'number'
                      ? 'Digite um valor numerico...'
                      : 'Digite sua resposta...',
                ),
                onChanged: (value) => onSelectAnswer?.call(
                  control.name,
                  value.trim(),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _labeledField(MoodleAnswerControl control, Widget field) {
    final hasLabel = control.label.isNotEmpty || control.htmlLabel.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasLabel) ...[
          DefaultTextStyle(
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w700,
            ),
            child: _controlLabel(control),
          ),
          const SizedBox(height: 8),
        ],
        field,
      ],
    );
  }

  Widget _controlLabel(MoodleAnswerControl control) {
    if (control.htmlLabel.isNotEmpty) {
      return MoodleHtmlRenderer(
        html: control.htmlLabel,
        textStyle: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: compact ? 13 : 15,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Text(
      control.label.isNotEmpty ? control.label : 'Resposta',
      style: TextStyle(
        color: AppTheme.textPrimary,
        fontSize: compact ? 13 : 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _dropdown({
    required String? value,
    required List<ParsedChoice> options,
    required String hint,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.bgDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.bgCardAlt),
      ),
      child: _AnswerDropdown(
        value: value,
        options: options,
        hint: hint,
        compact: false,
        isExpanded: true,
        disabled: _controlsDisabled,
        onChanged: onChanged,
      ),
    );
  }

  Widget _inlineDropdown({
    required String? value,
    required List<ParsedChoice> options,
    required String hint,
    required ValueChanged<String?> onChanged,
  }) {
    final selected = _AnswerDropdown.selectedValue(value, options);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: compact ? 96 : 118,
        maxWidth: compact ? 160 : 220,
        minHeight: compact ? 34 : 38,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: _controlsDisabled ? AppTheme.bgCard : AppTheme.bgDark,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected == null ? AppTheme.bgCardAlt : AppTheme.primary,
            width: selected == null ? 1 : 1.5,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: _AnswerDropdown(
            value: selected,
            options: options,
            hint: hint,
            compact: true,
            isExpanded: true,
            disabled: _controlsDisabled,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton(bool hasAnswer) {
    if (hasAnswered) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: AppTheme.success),
            SizedBox(width: 8),
            Text(
              'Resposta enviada! Aguardando resultado...',
              style: TextStyle(
                color: AppTheme.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: (hasAnswer && !isSubmitting) ? onSubmit : null,
      icon: isSubmitting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.send_rounded),
      label: Text(isSubmitting ? 'Enviando...' : 'Confirmar resposta'),
      style: ElevatedButton.styleFrom(
        backgroundColor: hasAnswer
            ? AppTheme.success
            : AppTheme.primary.withValues(alpha: 0.5),
        minimumSize: const Size(double.infinity, 52),
      ),
    );
  }

  _QuestionUiSpec get _uiSpec {
    if (question.isDdImage) {
      return const _QuestionUiSpec(
        title: 'Marcacao em imagem',
        instruction: 'Toque para posicionar marcadores visuais na figura.',
        icon: Icons.add_location_alt_rounded,
        color: AppTheme.warning,
      );
    }
    if (question.isMatch) {
      return const _QuestionUiSpec(
        title: 'Associacao',
        instruction: 'Selecione uma opcao para cada item da coluna.',
        icon: Icons.alt_route_rounded,
        color: AppTheme.accent,
      );
    }
    if (question.isGapSelect || question.isDdwtos) {
      return const _QuestionUiSpec(
        title: 'Preencher lacunas',
        instruction: 'Cada lacuna deve receber uma unica opcao valida.',
        icon: Icons.segment_rounded,
        color: AppTheme.primary,
      );
    }
    if (question.isMultiChoice && question.choices.isNotEmpty) {
      return const _QuestionUiSpec(
        title: 'Escolha unica',
        instruction: 'Selecione uma alternativa. Voce pode limpar a escolha.',
        icon: Icons.radio_button_checked_rounded,
        color: AppTheme.success,
      );
    }
    if (_answerableControls.any((c) => c.isMultipleChoice)) {
      return const _QuestionUiSpec(
        title: 'Multipla selecao',
        instruction: 'Marque uma ou mais opcoes conforme o enunciado.',
        icon: Icons.check_box_rounded,
        color: AppTheme.success,
      );
    }
    if (question.isNumerical) {
      return const _QuestionUiSpec(
        title: 'Resposta numerica',
        instruction: 'Informe um valor numerico no campo de resposta.',
        icon: Icons.calculate_rounded,
        color: AppTheme.warning,
      );
    }
    if (question.isOrdering) {
      return const _QuestionUiSpec(
        title: 'Ordenacao',
        instruction: 'Organize os itens na sequencia esperada.',
        icon: Icons.reorder_rounded,
        color: AppTheme.accent,
      );
    }
    if (question.isShortAnswer || question.isEssay || question.isCloze) {
      return const _QuestionUiSpec(
        title: 'Resposta textual',
        instruction: 'Digite a resposta no campo indicado.',
        icon: Icons.short_text_rounded,
        color: AppTheme.primary,
      );
    }

    return const _QuestionUiSpec(
      title: 'Questao',
      instruction: 'Interaja com os campos de resposta antes de confirmar.',
      icon: Icons.quiz_rounded,
      color: AppTheme.primary,
    );
  }

  Widget _buildRightAnswerCard(TextStyle textStyle) {
    if (question.rightAnswerHtml.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.success, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded,
              color: AppTheme.success, size: compact ? 16 : 20),
          const SizedBox(width: 10),
          Expanded(
            child: MoodleHtmlRenderer(
              html: question.rightAnswerHtml,
              textStyle: textStyle.copyWith(
                color: AppTheme.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildInfoBanner({
    required IconData icon,
    required Color color,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DdMarkerInput extends StatefulWidget {
  final DdMarkerData data;
  final Map<String, String> selectedAnswers;
  final bool disabled;
  final bool compact;
  final void Function(String inputName, String value) onChanged;

  const _DdMarkerInput({
    required this.data,
    required this.selectedAnswers,
    required this.disabled,
    required this.compact,
    required this.onChanged,
  });

  @override
  State<_DdMarkerInput> createState() => _DdMarkerInputState();
}

class _DdMarkerInputState extends State<_DdMarkerInput> {
  int _activeChoiceIndex = 0;
  ImageInfo? _imageInfo;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  String? _resolvedImageUrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant _DdMarkerInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.backgroundImageUrl != widget.data.backgroundImageUrl) {
      _imageInfo = null;
      _resolveImage(force: true);
    }
    if (_activeChoiceIndex >= widget.data.choices.length) {
      _activeChoiceIndex = 0;
    }
  }

  @override
  void dispose() {
    _removeImageListener();
    super.dispose();
  }

  void _resolveImage({bool force = false}) {
    final url = widget.data.backgroundImageUrl;
    if (!force && _resolvedImageUrl == url && _imageInfo != null) return;

    _removeImageListener();
    _resolvedImageUrl = url;
    final provider = NetworkImage(url);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() => _imageInfo = info);
    });
    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  void _removeImageListener() {
    final listener = _imageListener;
    final stream = _imageStream;
    if (listener != null && stream != null) {
      stream.removeListener(listener);
    }
    _imageListener = null;
    _imageStream = null;
  }

  @override
  Widget build(BuildContext context) {
    final choices = widget.data.choices;
    if (choices.isEmpty || widget.data.backgroundImageUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    final activeChoice = choices[_activeChoiceIndex];
    final naturalWidth = _imageInfo?.image.width.toDouble();
    final naturalHeight = _imageInfo?.image.height.toDouble();
    final aspectRatio = naturalWidth != null &&
            naturalHeight != null &&
            naturalWidth > 0 &&
            naturalHeight > 0
        ? naturalWidth / naturalHeight
        : 16 / 9;

    return Container(
      padding: EdgeInsets.all(widget.compact ? 10 : 14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMarkerToolbar(choices),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = width / aspectRatio;
              return GestureDetector(
                onTapUp: widget.disabled || naturalWidth == null
                    ? null
                    : (details) => _addMarker(
                          activeChoice,
                          details.localPosition,
                          Size(width, height),
                        ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          widget.data.backgroundImageUrl,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppTheme.bgDark,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.broken_image_rounded,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                        if (naturalWidth != null)
                          ..._buildPlacedMarkers(
                            choices,
                            Size(width, height),
                            naturalWidth,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMarkerToolbar(List<DdMarkerChoice> choices) {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: choices.asMap().entries.map((entry) {
              final index = entry.key;
              final choice = entry.value;
              final count = _pointsFor(choice).length;
              return ChoiceChip(
                label:
                    Text(count > 0 ? '${choice.text} ($count)' : choice.text),
                selected: index == _activeChoiceIndex,
                onSelected: widget.disabled
                    ? null
                    : (_) => setState(() => _activeChoiceIndex = index),
                selectedColor: AppTheme.primary,
                backgroundColor: AppTheme.bgDark,
                labelStyle: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                side: BorderSide(color: AppTheme.bgCardAlt),
              );
            }).toList(),
          ),
        ),
        Tooltip(
          message: 'Limpar marcadores',
          child: IconButton(
            onPressed: widget.disabled ? null : _clearMarkers,
            icon: const Icon(Icons.clear_all_rounded),
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildPlacedMarkers(
    List<DdMarkerChoice> choices,
    Size displaySize,
    double naturalWidth,
  ) {
    final scale = displaySize.width / naturalWidth;
    final markers = <Widget>[];

    for (final choice in choices) {
      final points = _pointsFor(choice);
      for (var i = 0; i < points.length; i++) {
        final point = points[i];
        markers.add(Positioned(
          left: point.x * scale,
          top: point.y * scale,
          child: GestureDetector(
            onTap: widget.disabled ? null : () => _removeMarker(choice, i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.bgDark, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.my_location_rounded,
                    size: 12,
                    color: AppTheme.bgDark,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    choice.text,
                    style: const TextStyle(
                      color: AppTheme.bgDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
      }
    }

    return markers;
  }

  void _addMarker(DdMarkerChoice choice, Offset localPosition, Size size) {
    final naturalWidth = _imageInfo?.image.width.toDouble();
    if (naturalWidth == null || naturalWidth <= 0) return;

    final scale = size.width / naturalWidth;
    final x = (localPosition.dx / scale).round().clamp(0, naturalWidth.round());
    final naturalHeight = _imageInfo?.image.height.toDouble() ?? size.height;
    final y =
        (localPosition.dy / scale).round().clamp(0, naturalHeight.round());
    final points = [
      ..._pointsFor(choice),
      _MarkerPoint(x.toDouble(), y.toDouble())
    ];
    widget.onChanged(choice.inputName, _formatPoints(points));
  }

  void _removeMarker(DdMarkerChoice choice, int index) {
    final points = [..._pointsFor(choice)];
    if (index < 0 || index >= points.length) return;
    points.removeAt(index);
    widget.onChanged(choice.inputName, _formatPoints(points));
  }

  void _clearMarkers() {
    for (final choice in widget.data.choices) {
      widget.onChanged(choice.inputName, '');
    }
  }

  List<_MarkerPoint> _pointsFor(DdMarkerChoice choice) {
    final raw = widget.selectedAnswers[choice.inputName] ?? '';
    if (raw.trim().isEmpty) return const [];
    final points = <_MarkerPoint>[];
    for (final item in raw.split(';')) {
      final parts = item.split(',');
      if (parts.length != 2) continue;
      final x = double.tryParse(parts[0].trim());
      final y = double.tryParse(parts[1].trim());
      if (x == null || y == null) continue;
      points.add(_MarkerPoint(x, y));
    }
    return points;
  }

  String _formatPoints(List<_MarkerPoint> points) {
    return points
        .map((point) => '${point.x.round()},${point.y.round()}')
        .join(';');
  }
}

class _MarkerPoint {
  final double x;
  final double y;

  const _MarkerPoint(this.x, this.y);
}

class _AnswerDropdown extends StatefulWidget {
  final String? value;
  final List<ParsedChoice> options;
  final String hint;
  final bool compact;
  final bool isExpanded;
  final bool disabled;
  final ValueChanged<String?> onChanged;

  const _AnswerDropdown({
    required this.value,
    required this.options,
    required this.hint,
    required this.compact,
    required this.isExpanded,
    required this.disabled,
    required this.onChanged,
  });

  static String? selectedValue(String? value, List<ParsedChoice> options) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    for (final option in options) {
      if (option.value.trim() == normalized) return option.value;
    }
    return null;
  }

  @override
  State<_AnswerDropdown> createState() => _AnswerDropdownState();
}

class _AnswerDropdownState extends State<_AnswerDropdown> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = _AnswerDropdown.selectedValue(widget.value, widget.options);
  }

  @override
  void didUpdateWidget(covariant _AnswerDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _AnswerDropdown.selectedValue(widget.value, widget.options);
    if (next != _selected) _selected = next;
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: _selected,
      isExpanded: widget.isExpanded,
      isDense: widget.compact,
      underline: const SizedBox.shrink(),
      dropdownColor: AppTheme.bgCard,
      hint: Text(
        widget.hint,
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 13,
          fontWeight: widget.compact ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      selectedItemBuilder: (context) => widget.options
          .map(
            (option) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                option.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
          .toList(),
      items: widget.options
          .map(
            (option) => DropdownMenuItem<String>(
              value: option.value,
              child: Text(
                option.text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
            ),
          )
          .toList(),
      onChanged: widget.disabled
          ? null
          : (value) {
              setState(() => _selected =
                  _AnswerDropdown.selectedValue(value, widget.options));
              widget.onChanged(value);
            },
    );
  }
}

class _QuestionUiSpec {
  final String title;
  final String instruction;
  final IconData icon;
  final Color color;

  const _QuestionUiSpec({
    required this.title,
    required this.instruction,
    required this.icon,
    required this.color,
  });
}

class _OrderingInput extends StatefulWidget {
  final List<MoodleAnswerControl> controls;
  final Map<String, String> selectedAnswers;
  final bool disabled;
  final bool compact;
  final TextStyle textStyle;
  final void Function(String inputName, String value) onChanged;

  const _OrderingInput({
    required this.controls,
    required this.selectedAnswers,
    required this.disabled,
    required this.compact,
    required this.textStyle,
    required this.onChanged,
  });

  @override
  State<_OrderingInput> createState() => _OrderingInputState();
}

class _OrderingInputState extends State<_OrderingInput> {
  late List<MoodleAnswerControl> _ordered;

  @override
  void initState() {
    super.initState();
    _ordered = _buildOrderedControls();
  }

  @override
  void didUpdateWidget(covariant _OrderingInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controls != widget.controls ||
        oldWidget.selectedAnswers != widget.selectedAnswers) {
      _ordered = _buildOrderedControls();
    }
  }

  List<MoodleAnswerControl> _buildOrderedControls() {
    final entries = widget.controls.asMap().entries.map((entry) {
      final index = entry.key;
      final control = entry.value;
      return MapEntry(
        control,
        _rankForControl(control) ?? (index + 1),
      );
    }).toList();

    entries.sort((a, b) {
      final byRank = a.value.compareTo(b.value);
      if (byRank != 0) return byRank;
      return widget.controls
          .indexOf(a.key)
          .compareTo(widget.controls.indexOf(b.key));
    });
    return entries.map((entry) => entry.key).toList(growable: true);
  }

  int? _rankForValue(String value, List<ParsedChoice> options) {
    if (value.trim().isEmpty) return null;

    for (final option in options) {
      if (option.value == value) {
        final numericFromText = int.tryParse(option.text.trim());
        if (numericFromText != null && numericFromText > 0) {
          return numericFromText;
        }
        final numericFromValue = int.tryParse(option.value.trim());
        if (numericFromValue != null && numericFromValue > 0) {
          return numericFromValue;
        }
      }
    }

    final numeric = int.tryParse(value.trim());
    return (numeric != null && numeric > 0) ? numeric : null;
  }

  String _valueForRank(MoodleAnswerControl control, int rank) {
    for (final option in control.options) {
      if (option.value.trim() == '$rank' || option.text.trim() == '$rank') {
        return option.value;
      }
    }

    final index = rank - 1;
    if (index >= 0 && index < control.options.length) {
      return control.options[index].value;
    }

    return control.options.isNotEmpty ? control.options.first.value : '';
  }

  int? _rankForControl(MoodleAnswerControl control) {
    return _rankForValue(
        widget.selectedAnswers[control.name] ?? '', control.options);
  }

  void _move(int index, int delta) {
    if (widget.disabled) return;
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= _ordered.length) return;

    setState(() {
      final item = _ordered.removeAt(index);
      _ordered.insert(nextIndex, item);
    });

    for (var i = 0; i < _ordered.length; i++) {
      final control = _ordered[i];
      widget.onChanged(control.name, _valueForRank(control, i + 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ordered.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Use as setas para ajustar a ordem final dos itens.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: widget.compact ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Column(
            children: List.generate(_ordered.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _orderingTile(index),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _orderingTile(int index) {
    final control = _ordered[index];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.bgCardAlt),
      ),
      child: Row(
        children: [
          Icon(
            Icons.drag_handle_rounded,
            color: AppTheme.textSecondary.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 10),
          Expanded(child: _orderingLabel(control, null)),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Subir',
            child: IconButton(
              onPressed:
                  widget.disabled || index == 0 ? null : () => _move(index, -1),
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
              color: AppTheme.textPrimary,
              disabledColor: AppTheme.textSecondary.withValues(alpha: 0.35),
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
            ),
          ),
          Tooltip(
            message: 'Descer',
            child: IconButton(
              onPressed: widget.disabled || index == _ordered.length - 1
                  ? null
                  : () => _move(index, 1),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              color: AppTheme.textPrimary,
              disabledColor: AppTheme.textSecondary.withValues(alpha: 0.35),
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderingLabel(MoodleAnswerControl control, Color? color) {
    if (control.htmlLabel.isNotEmpty) {
      return MoodleHtmlRenderer(
        html: control.htmlLabel,
        textStyle: widget.textStyle.copyWith(
          fontSize: 15,
          color: color ?? AppTheme.textPrimary,
        ),
      );
    }
    return Text(
      control.label.isNotEmpty ? control.label : 'Item',
      overflow: TextOverflow.ellipsis,
      style: widget.textStyle.copyWith(
        fontSize: 15,
        color: color ?? AppTheme.textPrimary,
      ),
    );
  }
}
