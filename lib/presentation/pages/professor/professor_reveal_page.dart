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
  final QuestionEntity? question;

  const ProfessorRevealPage({
    super.key,
    this.question,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfessorController>(
      builder: (context, prof, _) {
        final state = prof.quizState;

        final explicitQuestion = question;
        final targetSlot = explicitQuestion?.slot ??
            prof.revealQuestionSlot ??
            state.currentSlot;
        final QuestionEntity? resolvedQuestion = explicitQuestion ??
            (prof.questions.isEmpty
                ? null
                : prof.questions.cast<QuestionEntity?>().firstWhere(
                      (q) => q!.slot == targetSlot,
                      orElse: () => prof.questions.first,
                    ));

        return _RevealScaffold(
          state: state,
          question: resolvedQuestion,
          questionIndex: resolvedQuestion == null
              ? -1
              : prof.questions.indexOf(resolvedQuestion),
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
    final question = widget.question;
    final hasFeedback = question != null && question.generalFeedback.isNotEmpty;
    final questionNumber = widget.questionIndex >= 0
        ? 'Questão ${widget.questionIndex + 1}'
        : 'Questão';

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(gradient: context.appColors.bgGradient),
            child: SafeArea(
              child: Column(
                children: [
                  // ── AppBar ────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_ios_new_rounded,
                              color: context.appColors.textSecondary, size: 20),
                          onPressed: () => context.pop(),
                        ),
                        const SizedBox(width: 4),
                        RichText(
                          text: TextSpan(children: [
                            TextSpan(
                              text: 'Gabarito — $questionNumber',
                              style: const TextStyle(
                                color: AppTheme.accent,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            if (question != null) ...[
                              TextSpan(
                                text: ' — ${_plainText(question)}',
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ]),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        if (question != null) ...[
                          IconButton(
                            icon: Icon(
                              _showCorrectAnswer
                                  ? Icons.check_circle_rounded
                                  : Icons.check_circle_outline_rounded,
                              color: _showCorrectAnswer
                                  ? AppTheme.success
                                  : AppTheme.textSecondary,
                            ),
                            tooltip: _showCorrectAnswer
                                ? 'Ocultar resposta correta'
                                : 'Mostrar resposta correta',
                            onPressed: () => setState(
                                () => _showCorrectAnswer = !_showCorrectAnswer),
                          ),
                          if (hasFeedback)
                            IconButton(
                              icon: Icon(
                                _showFeedback
                                    ? Icons.visibility_off_rounded
                                    : Icons.feedback_rounded,
                                color: _showFeedback
                                    ? AppTheme.warning
                                    : AppTheme.accent,
                              ),
                              tooltip: _showFeedback
                                  ? 'Ocultar feedback'
                                  : 'Ver feedback',
                              onPressed: () => setState(
                                  () => _showFeedback = !_showFeedback),
                            ),
                        ],
                      ],
                    ),
                  ),

                  // ── Conteúdo ─────────────────────────────────────────
                  Expanded(
                    child: question == null
                        ? const Center(
                            child: Text('Nenhuma questão disponível.',
                                style: TextStyle(
                                    color: AppTheme.textSecondary)),
                          )
                        : Align(
                            alignment: Alignment.topCenter,
                            child: SingleChildScrollView(
                              padding: Responsive.horizontalPadding(context)
                                  .add(const EdgeInsets.symmetric(vertical: 8)),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 760),
                                child: _showFeedback
                                    ? _FeedbackView(question: question)
                                    : QuestionEngineWidget(
                                        question: question,
                                        mode: QuestionEngineMode.reveal,
                                        showCorrect: _showCorrectAnswer,
                                        showTypeHeader: false,
                                        baseFontSize: 25,
                                        choiceSpacing: 6,
                                        selectedAnswers: const {},
                                        onSelectAnswer: null,
                                      ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _plainText(QuestionEntity question) {
    if (question.htmlText.isNotEmpty) {
      final parsed = html_parser.parse(question.htmlText);
      final text = parsed.documentElement?.text ?? '';
      final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.isNotEmpty) return normalized;
    }
    return question.text.trim();
  }
}

class _FeedbackView extends StatelessWidget {
  final QuestionEntity question;
  const _FeedbackView({required this.question});

  @override
  Widget build(BuildContext context) {
    final feedback = question.generalFeedback.trim();
    if (feedback.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum feedback disponível para esta questão.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: context.appColors.cardDecoration(),
      child: _MoodleFeedbackHtml(
        html: feedback,
        textStyle: const TextStyle(
          fontSize: 20,
          color: AppTheme.textPrimary,
          height: 1.6,
        ),
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
