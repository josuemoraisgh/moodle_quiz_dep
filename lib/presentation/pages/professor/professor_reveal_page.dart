import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:go_router/go_router.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/entities/question_entity.dart';
import '../../controllers/professor_controller.dart';
import '../../widgets/moodle_image.dart';
import '../../widgets/question_engine_widget.dart';

/// Tela de revisão da questão para o professor apresentar aos alunos.
/// Mostra o enunciado completo (HTML rico) e as alternativas com a
/// resposta correta destacada em verde.
class ProfessorRevealPage extends StatelessWidget {
  const ProfessorRevealPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfessorController>(
      builder: (context, prof, _) {
        final state = prof.quizState;

        // Encontra a questão que estava ativa pelo slot (identificador único Moodle)
        final targetSlot = prof.revealQuestionSlot ?? state.currentSlot;
        final QuestionEntity? question = prof.questions.isEmpty
            ? null
            : prof.questions.cast<QuestionEntity?>().firstWhere(
                  (q) => q!.slot == targetSlot,
                  orElse: () => prof.questions.first,
                );

        return _RevealScaffold(
          state: state,
          question: question,
          questionIndex:
              question == null ? -1 : prof.questions.indexOf(question),
        );
      },
    );
  }
}

class _RevealScaffold extends StatefulWidget {
  final dynamic state;
  final QuestionEntity? question;
  final int questionIndex;
  const _RevealScaffold({
    required this.state,
    required this.question,
    required this.questionIndex,
  });

  @override
  State<_RevealScaffold> createState() => _RevealScaffoldState();
}

class _RevealScaffoldState extends State<_RevealScaffold> {
  bool _showFeedback = false;
  bool _showCorrectAnswer = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final question = widget.question;
    final hasFeedback = question != null && question.generalFeedback.isNotEmpty;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              // ── AppBar ────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppTheme.textSecondary, size: 20),
                      onPressed: () => context.pop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.questionIndex >= 0
                            ? 'Gabarito — Questão ${widget.questionIndex + 1}'
                                '${state.totalPages > 0 ? ' de ${state.totalPages}' : ''}'
                            : 'Gabarito',
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 17),
                      ),
                    ),
                    if (question != null) ...[
                      const SizedBox(width: 8),
                      FilterChip(
                        selected: _showCorrectAnswer,
                        onSelected: (value) =>
                            setState(() => _showCorrectAnswer = value),
                        avatar: Icon(
                          _showCorrectAnswer
                              ? Icons.check_circle_rounded
                              : Icons.visibility_rounded,
                          size: 16,
                          color: _showCorrectAnswer
                              ? AppTheme.success
                              : AppTheme.textSecondary,
                        ),
                        label: const Text('Resposta correta'),
                        selectedColor: AppTheme.success.withValues(alpha: 0.18),
                        backgroundColor: AppTheme.bgCardAlt,
                        side: BorderSide(
                          color: _showCorrectAnswer
                              ? AppTheme.success
                              : AppTheme.bgCardAlt,
                        ),
                        labelStyle: TextStyle(
                          color: _showCorrectAnswer
                              ? AppTheme.success
                              : AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (hasFeedback)
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _showFeedback = !_showFeedback),
                        icon: Icon(
                          _showFeedback
                              ? Icons.list_alt_rounded
                              : Icons.feedback_outlined,
                          size: 16,
                        ),
                        label: Text(
                          _showFeedback
                              ? 'Ver alternativas'
                              : 'Ver feedback geral',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.textSecondary,
                          backgroundColor: AppTheme.bgCardAlt,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Conteúdo ─────────────────────────────────────────
              Expanded(
                child: question == null
                    ? const Center(
                        child: Text('Nenhuma questão disponível.',
                            style: TextStyle(color: AppTheme.textSecondary)),
                      )
                    : _QuestionReveal(
                        question: question,
                        showFeedback: _showFeedback,
                        showCorrect: _showCorrectAnswer,
                      ),
              ),

              // ── Checkbox mostrar resposta correta ─────────────────
              if (question != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: _showCorrectAnswer,
                          onChanged: (v) =>
                              setState(() => _showCorrectAnswer = v ?? false),
                          activeColor: AppTheme.success,
                          side: const BorderSide(color: AppTheme.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(
                            () => _showCorrectAnswer = !_showCorrectAnswer),
                        child: const Text(
                          'Mostrar resposta correta',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionReveal extends StatelessWidget {
  final QuestionEntity question;
  final bool showFeedback;
  final bool showCorrect;
  const _QuestionReveal({
    required this.question,
    required this.showFeedback,
    this.showCorrect = false,
  });

  static const _letters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final questionTextStyle = TextStyle(
      fontSize: isMobile ? 16 : 20,
      color: AppTheme.textPrimary,
      height: 1.5,
    );

    // Decide qual HTML usar para o enunciado
    final questionHtml = question.isMultiChoice
        ? (question.htmlText.isNotEmpty ? question.htmlText : '')
        : (question.displayHtml.isNotEmpty
            ? question.displayHtml
            : question.htmlText);

    if (!showFeedback) {
      return SingleChildScrollView(
        padding:
            Responsive.horizontalPadding(context).copyWith(top: 8, bottom: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: QuestionEngineWidget(
              question: question,
              mode: QuestionEngineMode.reveal,
              showCorrect: showCorrect,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding:
          Responsive.horizontalPadding(context).copyWith(top: 8, bottom: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Enunciado ────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: AppTheme.cardDecoration(glowing: false),
                child: questionHtml.isNotEmpty
                    ? MoodleHtml(
                        html: questionHtml, textStyle: questionTextStyle)
                    : Text(
                        question.text,
                        style: TextStyle(
                          fontSize: isMobile ? 17 : 21,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                          height: 1.5,
                        ),
                      ),
              ),

              const SizedBox(height: 16),

              if (!showFeedback) ...[
                // ── Gabarito por tipo ────────────────────────────────────

                // Múltipla escolha / V-F / Calculada múltipla: lista de alternativas
                if (question.isMultiChoice && question.choices.isNotEmpty)
                  ..._buildChoicesList(isMobile),

                // Associação (Match): tabela premissa → resposta
                if (question.isMatch) _buildMatchReveal(isMobile),

                // Numérica / Calculada / Resposta curta: rightAnswerHtml
                if ((question.isNumerical || question.isShortAnswer) &&
                    showCorrect &&
                    question.rightAnswerHtml.isNotEmpty)
                  _buildRightAnswerCard(isMobile),

                // GapSelect / DDwtos / Cloze / Ordering / GeoGebra / DDImage:
                // mostra o rightAnswerHtml se disponível
                if (!question.isMultiChoice &&
                    !question.isMatch &&
                    !question.isNumerical &&
                    !question.isShortAnswer &&
                    showCorrect &&
                    question.rightAnswerHtml.isNotEmpty)
                  _buildRightAnswerCard(isMobile),
              ] else
                // ── Feedback geral ───────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: AppTheme.cardDecoration(glowing: false),
                  child: question.generalFeedback.isNotEmpty
                      ? _MoodleFeedbackHtml(
                          html: question.generalFeedback,
                          textStyle: TextStyle(
                            fontSize: isMobile ? 15 : 17,
                            color: AppTheme.textPrimary,
                            height: 1.6,
                          ),
                        )
                      : const Text(
                          'Nenhum feedback disponível para esta questão.',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 15),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildChoicesList(bool isMobile) {
    return question.choices.asMap().entries.map((e) {
      final idx = e.key;
      final choice = e.value;
      final letter = idx < _letters.length ? _letters[idx] : '${idx + 1}';
      final correct = showCorrect && choice.isCorrect;

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: correct
              ? AppTheme.success.withValues(alpha: 0.18)
              : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: correct ? AppTheme.success : AppTheme.bgCardAlt,
            width: correct ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: correct ? AppTheme.success : AppTheme.bgDark,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  letter,
                  style: TextStyle(
                    color: correct ? Colors.white : AppTheme.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: choice.htmlText.isNotEmpty
                  ? MoodleHtml(
                      html: choice.htmlText,
                      textStyle: TextStyle(
                        color:
                            correct ? AppTheme.success : AppTheme.textPrimary,
                        fontSize: isMobile ? 14 : 16,
                        fontWeight: correct ? FontWeight.w700 : FontWeight.w500,
                        height: 1.4,
                      ),
                    )
                  : Text(
                      choice.text,
                      style: TextStyle(
                        color:
                            correct ? AppTheme.success : AppTheme.textPrimary,
                        fontSize: isMobile ? 14 : 16,
                        fontWeight: correct ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
            ),
            if (correct)
              const Icon(Icons.check_circle_rounded,
                  color: AppTheme.success, size: 24),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildMatchReveal(bool isMobile) {
    final matchData = question.matchData;
    if (matchData == null || matchData.subQuestions.isEmpty) {
      return _buildRightAnswerCard(isMobile);
    }

    // Mapa de value → texto da opção
    final optionText = {
      for (final o in matchData.options) o.value: o.text,
    };
    // Se temos o HTML de revisão, usa o rightAnswerHtml; caso contrário monta da estrutura
    if (question.rightAnswerHtml.isNotEmpty && showCorrect) {
      return _buildRightAnswerCard(isMobile);
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.bgCardAlt),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabeçalho
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.bgDark,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.compare_arrows_rounded,
                    color: AppTheme.accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Associação',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: isMobile ? 13 : 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!showCorrect)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '(ative "Mostrar resposta correta" para ver o gabarito)',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: isMobile ? 11 : 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Linhas de premissa → opção correta
          ...matchData.subQuestions.asMap().entries.map((e) {
            final idx = e.key;
            final sub = e.value;
            final correctText = sub.correctValue != null
                ? optionText[sub.correctValue] ?? '?'
                : '—';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: idx > 0
                      ? BorderSide(color: AppTheme.bgCardAlt)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  // Premissa
                  Expanded(
                    flex: 3,
                    child: sub.htmlText.isNotEmpty
                        ? MoodleHtml(
                            html: sub.htmlText,
                            textStyle: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: isMobile ? 13 : 15),
                          )
                        : Text(sub.text,
                            style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: isMobile ? 13 : 15)),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded,
                        color: AppTheme.accent, size: 16),
                  ),
                  // Resposta correta
                  Expanded(
                    flex: 2,
                    child: Text(
                      showCorrect ? correctText : '______',
                      style: TextStyle(
                        color: showCorrect
                            ? AppTheme.success
                            : AppTheme.textSecondary,
                        fontSize: isMobile ? 13 : 15,
                        fontWeight:
                            showCorrect ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRightAnswerCard(bool isMobile) {
    if (question.rightAnswerHtml.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.success, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppTheme.success, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: MoodleHtml(
              html: question.rightAnswerHtml,
              textStyle: TextStyle(
                color: AppTheme.success,
                fontSize: isMobile ? 15 : 17,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodleFeedbackHtml extends StatelessWidget {
  final String html;
  final TextStyle textStyle;

  const _MoodleFeedbackHtml({
    required this.html,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final fragment = html_parser.parseFragment(html);
    final blocks = _buildBlocks(fragment.nodes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks,
    );
  }

  List<Widget> _buildBlocks(List<dom.Node> nodes) {
    final blocks = <Widget>[];

    for (final node in nodes) {
      if (node is dom.Text) {
        final text = node.text.trim();
        if (text.isNotEmpty) blocks.add(_textParagraph([node]));
        continue;
      }

      if (node is! dom.Element) continue;

      switch (node.localName) {
        case 'div':
          blocks.addAll(_buildBlocks(node.nodes));
          break;
        case 'p':
          blocks.add(_paragraph(node));
          break;
        case 'br':
          blocks.add(const SizedBox(height: 8));
          break;
        default:
          blocks.add(_htmlBlock(node.outerHtml));
      }
    }

    return blocks;
  }

  Widget _paragraph(dom.Element element) {
    final plainText = element.text.trim();
    final displayLatex = _displayLatexFromText(plainText);
    if (displayLatex != null) return _mathBlock(displayLatex);

    return _textParagraph(element.nodes);
  }

  Widget _textParagraph(List<dom.Node> nodes) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text.rich(
        TextSpan(children: _inlineSpans(nodes, textStyle)),
        style: textStyle,
      ),
    );
  }

  Widget _htmlBlock(String html) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: MoodleHtml(html: html, textStyle: textStyle),
    );
  }

  Widget _mathBlock(String latex) {
    final normalized = MoodleHtml._normalizeLatex(latex);
    final math = Math.tex(
      normalized,
      mathStyle: MathStyle.display,
      textStyle: textStyle.copyWith(color: AppTheme.textPrimary),
      onErrorFallback: (error) => Text(
        MoodleHtml._latexFallbackText(normalized),
        style: textStyle.copyWith(color: AppTheme.textPrimary),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: math,
      ),
    );
  }

  List<InlineSpan> _inlineSpans(List<dom.Node> nodes, TextStyle style) {
    final spans = <InlineSpan>[];

    for (final node in nodes) {
      if (node is dom.Text) {
        spans.addAll(_textWithMathSpans(node.text, style));
        continue;
      }

      if (node is! dom.Element) continue;

      final localName = node.localName;
      if (localName == 'br') {
        spans.add(const TextSpan(text: '\n'));
        continue;
      }

      var childStyle = style;
      if (localName == 'strong' || localName == 'b') {
        childStyle = childStyle.copyWith(fontWeight: FontWeight.w800);
      } else if (localName == 'em' || localName == 'i') {
        childStyle = childStyle.copyWith(fontStyle: FontStyle.italic);
      }

      spans.addAll(_inlineSpans(node.nodes, childStyle));
    }

    return spans;
  }

  List<InlineSpan> _textWithMathSpans(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    var index = 0;

    while (index < text.length) {
      final match = _nextInlineLatex(text, index);
      if (match == null) {
        spans.add(TextSpan(
          text: MoodleHtml._cleanPlainLatexText(text.substring(index)),
          style: style,
        ));
        break;
      }

      if (match.start > index) {
        spans.add(TextSpan(
          text: MoodleHtml._cleanPlainLatexText(
            text.substring(index, match.start),
          ),
          style: style,
        ));
      }

      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Math.tex(
          MoodleHtml._normalizeLatex(match.content),
          mathStyle: MathStyle.text,
          textStyle: style.copyWith(color: AppTheme.textPrimary),
          onErrorFallback: (error) => Text(
            MoodleHtml._latexFallbackText(match.content),
            style: style.copyWith(color: AppTheme.textPrimary),
          ),
        ),
      ));

      index = match.end;
    }

    return spans;
  }

  _LatexMatch? _nextInlineLatex(String text, int from) {
    final delimited = MoodleHtml._nextLatex(text, from);
    final loose = MoodleHtml._nextLooseLatexFragment(text, from);

    if (delimited == null) return loose;
    if (loose == null) return delimited;
    return delimited.start <= loose.start ? delimited : loose;
  }

  String? _displayLatexFromText(String text) {
    final line = text.trim();
    if (line.isEmpty) return null;

    final delimited = MoodleHtml._nextLatex(line, 0);
    if (delimited != null &&
        delimited.start == 0 &&
        delimited.end == line.length) {
      return delimited.content;
    }

    if (MoodleHtml._looksLikeLatexLine(line)) return line;

    return null;
  }
}

class MoodleHtml extends StatelessWidget {
  final String html;
  final TextStyle textStyle;

  const MoodleHtml({
    super.key,
    required this.html,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return HtmlWidget(
      _withLatexTags(html),
      textStyle: textStyle,
      customWidgetBuilder: (element) {
        if (element.localName == 'img') {
          final src = element.attributes['src'];
          if (src == null || src.isEmpty) return null;

          // Mesma regra do aluno: ignora assets decorativos do Moodle.
          if (src.startsWith('data:') ||
              src.contains('/pix/') ||
              src.contains('theme/image.php')) {
            return const SizedBox.shrink();
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: MoodleImage(
              src: src,
              alt: element.attributes['alt'],
              maxHeight: 260,
            ),
          );
        }

        if (element.localName != 'mq-latex') return null;

        final latex = element.attributes['data-latex'];
        if (latex == null) return null;

        final decoded = Uri.decodeComponent(latex);
        final display = element.attributes['data-display'] == 'true';
        final math = Math.tex(
          decoded,
          mathStyle: display ? MathStyle.display : MathStyle.text,
          textStyle: textStyle.copyWith(color: AppTheme.textPrimary),
          onErrorFallback: (error) => Text(
            _latexFallbackText(decoded),
            style: textStyle.copyWith(color: AppTheme.textPrimary),
          ),
        );

        if (!display) return InlineCustomWidget(child: math);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: math,
          ),
        );
      },
      customStylesBuilder: (element) {
        if (element.localName == 'table') {
          return {'border-collapse': 'collapse', 'width': '100%'};
        }
        if (element.localName == 'td' || element.localName == 'th') {
          return {'border': '1px solid #444', 'padding': '6px 10px'};
        }
        if (element.localName == 'img') {
          return {'max-width': '100%', 'height': 'auto'};
        }
        return null;
      },
    );
  }

  static String _withLatexTags(String source) {
    final buffer = StringBuffer();
    var index = 0;

    while (index < source.length) {
      final tagStart = source.indexOf('<', index);
      if (tagStart < 0) {
        buffer.write(_replaceLatexInText(source.substring(index)));
        break;
      }

      if (tagStart > index) {
        buffer.write(_replaceLatexInText(source.substring(index, tagStart)));
      }

      final tagEnd = source.indexOf('>', tagStart);
      if (tagEnd < 0) {
        buffer.write(source.substring(tagStart));
        break;
      }

      buffer.write(source.substring(tagStart, tagEnd + 1));
      index = tagEnd + 1;
    }

    return buffer.toString();
  }

  static String _replaceLatexInText(String text) {
    final decoded = _decodeHtmlEntities(text);
    final delimited = _replaceDelimitedLatex(decoded);
    if (delimited != null) return delimited;

    final replaced = decoded.split('\n').map(_replaceLooseLatexLine).join('\n');
    if (replaced != decoded) return replaced;

    final cleaned = _cleanPlainLatexText(decoded);
    if (cleaned != decoded) return _escapeHtmlText(cleaned);

    return text;
  }

  static String? _replaceDelimitedLatex(String text) {
    final buffer = StringBuffer();
    var index = 0;
    var changed = false;

    while (index < text.length) {
      final match = _nextLatex(text, index);
      if (match == null) {
        buffer.write(_escapeHtmlText(_cleanPlainLatexText(
          text.substring(index),
        )));
        break;
      }

      changed = true;
      buffer.write(_escapeHtmlText(_cleanPlainLatexText(
        text.substring(index, match.start),
      )));
      buffer.write(_latexTag(match.content, display: match.display));
      index = match.end;
    }

    return changed ? buffer.toString() : null;
  }

  static String _replaceLooseLatexLine(String text) {
    final leading = RegExp(r'^\s*').firstMatch(text)?.group(0) ?? '';
    final trailing = RegExp(r'\s*$').firstMatch(text)?.group(0) ?? '';
    final line = text.trim();

    if (line.isEmpty) return text;

    if (_looksLikeLatexLine(line)) {
      return '$leading${_latexTag(line, display: true)}$trailing';
    }

    final fragments = _findLooseLatexFragments(line);
    if (fragments.isEmpty) return text;

    final buffer = StringBuffer(leading);
    var index = 0;
    for (final fragment in fragments) {
      if (fragment.start < index) continue;

      buffer.write(_escapeHtmlText(_cleanPlainLatexText(
        line.substring(index, fragment.start),
      )));
      buffer.write(_latexTag(fragment.content, display: false));
      index = fragment.end;
    }
    buffer.write(_escapeHtmlText(_cleanPlainLatexText(line.substring(index))));
    buffer.write(trailing);

    return buffer.toString();
  }

  static bool _looksLikeLatexLine(String line) {
    final startsAsMath = RegExp(
      r'^(?:\\(?:Delta|delta|frac|sqrt|sum|int|left|right)\b|[A-Za-z]\s*=|\d)',
    ).hasMatch(line);
    if (!startsAsMath) return false;

    if (RegExp(
            r'\\(?:Delta|delta|frac|cdot|times|div|sqrt|circ|pi|alpha|beta|gamma|theta|lambda|mu|sigma|sum|int|left|right)\b')
        .hasMatch(line)) {
      return true;
    }

    return RegExp(r'^[A-Za-z\\][A-Za-z0-9\\\s{}.,+\-*/^=()]+$')
            .hasMatch(line) &&
        line.contains('=') &&
        (line.contains(r'\') || line.contains('{') || line.contains('^'));
  }

  static List<_LatexMatch> _findLooseLatexFragments(String line) {
    final fragments = <_LatexMatch>[];
    var index = 0;

    while (index < line.length) {
      final match = _nextLooseLatexFragment(line, index);
      if (match == null) break;

      fragments.add(match);
      index = match.end;
    }

    return fragments;
  }

  static _LatexMatch? _nextLooseLatexFragment(String line, int from) {
    final patterns = <RegExp>[
      RegExp(
        r'\d+(?:\{,\}\d+)?(?:\\,)?\^?\{?\\circ\}?\s*[A-Za-z]',
      ),
      RegExp(
        r'\\(?:Delta|delta|frac|cdot|times|div|sqrt|circ|pi|alpha|beta|gamma|theta|lambda|mu|sigma|sum|int|left|right)\b(?:\{,\}|[^.;\n])*',
      ),
      RegExp(
        r'[A-Za-z\\][A-Za-z0-9\\\s{},+\-*/^=()]*=\s*[A-Za-z0-9\\\s{},+\-*/^()]+',
      ),
    ];

    _LatexMatch? best;
    for (final pattern in patterns) {
      final match = pattern.matchAsPrefix(line, from) ??
          pattern.allMatches(line, from).firstOrNull;
      if (match == null) continue;

      final content = match.group(0)?.trim() ?? '';
      if (content.isEmpty) continue;
      if (!_looksLikeLatexFragment(content)) continue;

      final candidate = _LatexMatch(
        start: match.start,
        end: match.end,
        content: content,
        display: false,
      );

      if (best == null || candidate.start < best.start) best = candidate;
    }

    return best;
  }

  static bool _looksLikeLatexFragment(String text) {
    return text.contains(r'\') ||
        text.contains('{') ||
        text.contains('^') ||
        text.contains('=');
  }

  static _LatexMatch? _nextLatex(String text, int from) {
    final candidates = <_LatexDelimiter>[
      const _LatexDelimiter(r'\(', r'\)', false),
      const _LatexDelimiter(r'\[', r'\]', true),
      const _LatexDelimiter(r'$$', r'$$', true),
    ];

    _LatexMatch? best;
    for (final delimiter in candidates) {
      final start = text.indexOf(delimiter.open, from);
      if (start < 0) continue;

      final contentStart = start + delimiter.open.length;
      final end = text.indexOf(delimiter.close, contentStart);
      if (end < 0) continue;

      final match = _LatexMatch(
        start: start,
        end: end + delimiter.close.length,
        content: text.substring(contentStart, end).trim(),
        display: delimiter.display,
      );

      if (best == null || match.start < best.start) best = match;
    }

    return best;
  }

  static String _latexTag(String latex, {required bool display}) {
    final encoded = Uri.encodeComponent(_normalizeLatex(latex));
    return '<mq-latex data-latex="$encoded" data-display="$display"></mq-latex>';
  }

  static String _normalizeLatex(String latex) {
    final decoded = _decodeHtmlEntities(latex)
        .replaceAll(RegExp(r'\{,\}'), ',')
        .replaceAllMapped(
          RegExp(r'\^\\circ\}?([A-Za-z])'),
          (match) => r'^\circ ' '${match.group(1)}',
        )
        .replaceAllMapped(
          RegExp(r'\^\{\\circ([A-Za-z])'),
          (match) => r'^\circ ' '${match.group(1)}',
        )
        .replaceAllMapped(
          RegExp(r'\^\{\\circ\}([A-Za-z])'),
          (match) => r'^{\circ} ' '${match.group(1)}',
        )
        .replaceAll(r'\,', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final buffer = StringBuffer();
    var balance = 0;
    for (final codeUnit in decoded.codeUnits) {
      final char = String.fromCharCode(codeUnit);
      if (char == '{') {
        balance++;
        buffer.write(char);
      } else if (char == '}') {
        if (balance > 0) {
          balance--;
          buffer.write(char);
        }
      } else {
        buffer.write(char);
      }
    }

    return buffer.toString();
  }

  static String _latexFallbackText(String latex) {
    return _decodeHtmlEntities(latex)
        .replaceAll(RegExp(r'\{,\}'), ',')
        .replaceAll(RegExp(r'\\,'), ' ')
        .replaceAllMapped(
          RegExp(r'\^\{?\\circ\}?\s*([A-Za-z])'),
          (match) => '°${match.group(1)}',
        )
        .replaceAllMapped(
          RegExp(r'\\circ\}?\s*([A-Za-z])'),
          (match) => '°${match.group(1)}',
        )
        .replaceAll(r'\Delta', 'Δ')
        .replaceAll(r'\delta', 'δ')
        .replaceAll(r'\cdot', '·')
        .replaceAll(r'\times', '×')
        .replaceAll(r'\div', '÷')
        .replaceAll(RegExp(r'[{}]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _cleanPlainLatexText(String text) {
    return text.replaceAll(RegExp(r'\{,\}'), ',').replaceAll(r'\,', ' ');
  }

  static String _escapeHtmlText(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  static String _decodeHtmlEntities(String value) {
    final named = value
        .replaceAll('&bsol;', r'\')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    return named.replaceAllMapped(
      RegExp(r'&#(?:x([0-9a-fA-F]+)|([0-9]+));'),
      (match) {
        final hex = match.group(1);
        final decimal = match.group(2);
        final codePoint = hex != null
            ? int.tryParse(hex, radix: 16)
            : int.tryParse(decimal ?? '');

        if (codePoint == null) return match.group(0) ?? '';
        return String.fromCharCode(codePoint);
      },
    );
  }
}

class _LatexDelimiter {
  final String open;
  final String close;
  final bool display;

  const _LatexDelimiter(this.open, this.close, this.display);
}

class _LatexMatch {
  final int start;
  final int end;
  final String content;
  final bool display;

  const _LatexMatch({
    required this.start,
    required this.end,
    required this.content,
    required this.display,
  });
}
