import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;

import '../../core/theme/app_theme.dart';
import 'moodle_image.dart';

class MoodleHtmlRenderer extends StatelessWidget {
  final String html;
  final TextStyle textStyle;

  const MoodleHtmlRenderer({
    super.key,
    required this.html,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return HtmlWidget(
      prepareHtml(html),
      textStyle: textStyle,
      customWidgetBuilder: (element) {
        return buildMathWidgetForElement(element, textStyle) ??
            buildImageWidgetForElement(element);
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

  static String prepareHtml(String html) {
    return _withLatexTags(_repairBrokenMoodleTexHtml(html));
  }

  static Widget? buildMathWidgetForElement(
    dom.Element element,
    TextStyle textStyle,
  ) {
    if (element.localName == 'span') {
      final repaired = _repairedBrokenTexSpan(element);
      if (repaired != null) {
        return InlineCustomWidget(
          child: Text(
            repaired,
            style: textStyle.copyWith(color: AppTheme.textPrimary),
          ),
        );
      }
    }

    if (element.localName == 'img') {
      final src = element.attributes['src'];
      if (src == null || src.isEmpty) return null;
      final latex = _latexFromImage(element, src);
      if (latex != null) {
        return _mathWidget(
          latex,
          textStyle: textStyle,
          display: _isDisplayLatexImage(element),
        );
      }

      if (src.startsWith('data:') ||
          src.contains('/pix/') ||
          src.contains('theme/image.php')) {
        return const SizedBox.shrink();
      }
    }

    if (element.localName != 'mq-latex') return null;

    final latex = element.attributes['data-latex'];
    if (latex == null) return null;

    final decoded = Uri.decodeComponent(latex);
    final display = element.attributes['data-display'] == 'true';
    return _mathWidget(decoded, textStyle: textStyle, display: display);
  }

  static Widget? buildImageWidgetForElement(dom.Element element) {
    if (element.localName != 'img') return null;
    final src = element.attributes['src'];
    if (src == null || src.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: MoodleImage(
        src: src,
        alt: element.attributes['alt'],
        maxHeight: 260,
      ),
    );
  }

  static Widget _mathWidget(
    String latex, {
    required TextStyle textStyle,
    required bool display,
  }) {
    final normalized = _normalizeLatex(_repairLatex(latex));
    final math = Math.tex(
      normalized,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: textStyle.copyWith(color: AppTheme.textPrimary),
      onErrorFallback: (error) => Text(
        _latexFallbackText(normalized),
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
  }

  static String? _latexFromImage(dom.Element element, String src) {
    final classAttr = element.attributes['class']?.toLowerCase() ?? '';
    final candidate = (element.attributes['alt'] ??
            element.attributes['title'] ??
            element.attributes['aria-label'] ??
            '')
        .trim();
    final isTexImage = classAttr.contains('texrender') ||
        classAttr.contains('latex') ||
        _isMoodleTexSrc(src);

    if (candidate.isEmpty) return null;
    final decoded = _decodeHtmlEntities(candidate);
    if (isTexImage || _looksLikeLatexFragment(decoded)) return decoded;
    return null;
  }

  static bool _isDisplayLatexImage(dom.Element element) {
    final classAttr = element.attributes['class']?.toLowerCase() ?? '';
    return classAttr.contains('display') || classAttr.contains('dtex');
  }

  static String? _repairedBrokenTexSpan(dom.Element element) {
    final src = element.attributes['src'] ?? '';
    if (!_isMoodleTexSrc(src)) return null;

    final markers = <String>[];
    for (final entry in element.attributes.entries) {
      final key = entry.key.toString().toLowerCase();
      if (key == 'alt' || key == 'title' || key == 'src') continue;

      final raw = '${entry.key} ${entry.value}';
      for (final match in RegExp(r'\[\d+\]').allMatches(raw)) {
        final marker = match.group(0);
        if (marker != null && !markers.contains(marker)) {
          markers.add(marker);
        }
      }
    }

    if (markers.isNotEmpty) {
      return markers.join(' ${String.fromCharCode(183)} ');
    }

    final fallback = element.attributes['alt'] ??
        element.attributes['title'] ??
        element.attributes['aria-label'] ??
        '';
    if (fallback.trim().isEmpty) return null;

    return _humanizeBrokenMoodleTexText(fallback);
  }

  static bool _isMoodleTexSrc(String src) {
    return src.contains('/filter/tex/') || src.contains('tex/pix.php');
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
    final repaired = _repairBrokenMoodleTexText(decoded);
    if (repaired != decoded) return _escapeHtmlText(repaired);

    final delimited = _replaceDelimitedLatex(decoded);
    if (delimited != null) return delimited;

    final replaced = decoded.split('\n').map(_replaceLooseLatexLine).join('\n');
    if (replaced != decoded) return replaced;

    final cleaned = _cleanPlainLatexText(decoded);
    if (cleaned != decoded) return _escapeHtmlText(cleaned);

    return text;
  }

  static String _repairBrokenMoodleTexHtml(String source) {
    return source.replaceAllMapped(
      RegExp(
        r'((?:\\[A-Za-z]+|[A-Za-z])[^<]{0,180})<span\s+class=?([^"]*?)"\s+(?:alt|title)="([^"]*)"[^>]*\bsrc="[^"]*(?:filter/tex|tex/pix)[^"]*"[^>]*\/?>',
        caseSensitive: false,
        dotAll: true,
      ),
      (match) {
        final prefix = match.group(1) ?? '';
        final leakedClass = match.group(2) ?? '';
        final alt = match.group(3) ?? '';
        final candidate =
            leakedClass.trim().isNotEmpty ? '$prefix$leakedClass' : alt;

        final repaired = _humanizeBrokenMoodleTexText(candidate);
        return _escapeHtmlText(repaired);
      },
    );
  }

  static String _repairBrokenMoodleTexText(String text) {
    final lower = text.toLowerCase();
    final hasSpanLeak = lower.contains('<span');
    final hasBlankLeak = RegExp(
      r'em\s+branco\s+\d+\s+quest\S*\s+\d+\s*\[\d+\]',
      caseSensitive: false,
    ).hasMatch(text);

    if (!hasSpanLeak || !hasBlankLeak) return text;

    var candidate = text;
    final leakedAttribute = RegExp(
      r'"\s+(?:alt|title|src)=',
      caseSensitive: false,
    ).firstMatch(candidate);
    if (leakedAttribute != null) {
      candidate = candidate.substring(0, leakedAttribute.start);
    }

    final repaired = _humanizeBrokenMoodleTexText(candidate);
    return repaired.isEmpty ? text : repaired;
  }

  static String _humanizeBrokenMoodleTexText(String value) {
    var text = _decodeHtmlEntities(value)
        .replaceAll(RegExp(r'<span\s+class=?', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('"', ' ');

    text = text.replaceAllMapped(
      RegExp(
        r'\bEm\s+branco\s+\d+\s+Quest\S*\s+\d+\s*(\[\d+\])',
        caseSensitive: false,
      ),
      (match) => match.group(1) ?? '',
    );

    text = _latexFallbackText(text);
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
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

  static String _repairLatex(String latex) {
    final text = _decodeHtmlEntities(latex).trim();
    if (RegExp(r'^rho\s*=', caseSensitive: false).hasMatch(text)) {
      return text.replaceFirst(RegExp(r'^rho', caseSensitive: false), r'\rho');
    }
    if (RegExp(r'^ho\s*=').hasMatch(text) &&
        RegExp(r'(?:kg/m|m/s|pa\b)', caseSensitive: false).hasMatch(text)) {
      return text.replaceFirst(RegExp(r'^ho'), r'\rho');
    }
    return text;
  }

  static String _latexFallbackText(String latex) {
    return _decodeHtmlEntities(latex)
        .replaceAll(RegExp(r'\{,\}'), ',')
        .replaceAll(RegExp(r'\\,'), ' ')
        .replaceAllMapped(
          RegExp(r'\^\{?\\circ\}?\s*([A-Za-z])'),
          (match) => '${String.fromCharCode(176)}${match.group(1)}',
        )
        .replaceAllMapped(
          RegExp(r'\\circ\}?\s*([A-Za-z])'),
          (match) => '${String.fromCharCode(176)}${match.group(1)}',
        )
        .replaceAll(r'\Delta', String.fromCharCode(916))
        .replaceAll(r'\delta', String.fromCharCode(948))
        .replaceAll(r'\cdot', String.fromCharCode(183))
        .replaceAll(r'\times', String.fromCharCode(215))
        .replaceAll(r'\div', String.fromCharCode(247))
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
