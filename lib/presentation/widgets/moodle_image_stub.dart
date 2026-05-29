import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class MoodleImage extends StatelessWidget {
  final String src;
  final String? alt;
  final double maxHeight;

  const MoodleImage({
    super.key,
    required this.src,
    this.alt,
    this.maxHeight = 240,
  });

  @override
  Widget build(BuildContext context) {
    final candidates = _candidateUrls(src);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: _MoodleImageAttempt(
        urls: candidates,
        alt: alt,
      ),
    );
  }

  static List<String> _candidateUrls(String source) {
    final urls = <String>[];

    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || urls.contains(trimmed)) return;
      urls.add(trimmed);
    }

    add(source);
    add(source.replaceAll(' ', '%20'));

    if (source.contains('/pluginfile.php')) {
      add(source.replaceFirst('/pluginfile.php', '/webservice/pluginfile.php'));
    }

    if (source.contains('/webservice/pluginfile.php')) {
      add(source.replaceFirst('/webservice/pluginfile.php', '/pluginfile.php'));
    }

    return urls;
  }
}

class _MoodleImageAttempt extends StatefulWidget {
  final List<String> urls;
  final String? alt;

  const _MoodleImageAttempt({
    required this.urls,
    this.alt,
  });

  @override
  State<_MoodleImageAttempt> createState() => _MoodleImageAttemptState();
}

class _MoodleImageAttemptState extends State<_MoodleImageAttempt> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant _MoodleImageAttempt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls.join('|') != widget.urls.join('|')) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    if (urls.isEmpty) return MoodleImageError(src: '', alt: widget.alt);

    final current = urls[_index.clamp(0, urls.length - 1)];
    return Image.network(
      current,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) {
        if (_index < urls.length - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _index += 1);
          });
          return const SizedBox.shrink();
        }
        return MoodleImageError(src: current, alt: widget.alt);
      },
    );
  }
}

class MoodleImageError extends StatelessWidget {
  final String src;
  final String? alt;

  const MoodleImageError({
    super.key,
    required this.src,
    this.alt,
  });

  @override
  Widget build(BuildContext context) {
    final label =
        (alt?.trim().isNotEmpty ?? false) ? alt!.trim() : 'Imagem da questão';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label não carregada',
        style: const TextStyle(
          color: AppTheme.warning,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
