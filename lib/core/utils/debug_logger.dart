import 'package:flutter/foundation.dart';

/// Logger global para debug do fluxo de submissão de respostas.
/// Captura eventos em tempo real para exibição no painel de debug.
class DebugLogger extends ChangeNotifier {
  static final DebugLogger instance = DebugLogger._();
  DebugLogger._();

  final List<DebugEntry> _entries = [];
  static const int _maxEntries = 500;

  List<DebugEntry> get entries => List.unmodifiable(_entries);

  void log(String tag, String message, {Map<String, dynamic>? data}) {
    final entry = DebugEntry(
      timestamp: DateTime.now(),
      tag: tag,
      message: message,
      data: data,
    );
    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }

    // Também imprime no console para debug via terminal
    debugPrint('[DEBUG][$tag] $message');
    if (data != null && data.isNotEmpty) {
      for (final e in data.entries) {
        debugPrint('  ${e.key}: ${e.value}');
      }
    }

    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  void separator(String label) {
    log('━━━', '━━ $label ━━');
  }
}

class DebugEntry {
  final DateTime timestamp;
  final String tag;
  final String message;
  final Map<String, dynamic>? data;

  const DebugEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
    this.data,
  });

  String get timeStr => timestamp.toIso8601String().substring(11, 23);

  @override
  String toString() {
    final buf = StringBuffer('[$timeStr][$tag] $message');
    if (data != null) {
      for (final e in data!.entries) {
        buf.write('\n  ${e.key}: ${e.value}');
      }
    }
    return buf.toString();
  }
}
