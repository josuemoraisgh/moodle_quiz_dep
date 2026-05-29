import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/debug_logger.dart';

/// Painel de debug flutuante que mostra logs em tempo real.
/// Pode ser minimizado/expandido com o FAB.
class DebugPanel extends StatefulWidget {
  const DebugPanel({super.key});

  @override
  State<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel> {
  bool _expanded = false;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    DebugLogger.instance.addListener(_onLogChanged);
  }

  @override
  void dispose() {
    DebugLogger.instance.removeListener(_onLogChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogChanged() {
    if (mounted) {
      setState(() {});
      // Auto-scroll para o final
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _copyLogs() {
    final text = DebugLogger.instance.entries.map((e) => e.toString()).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs copiados!'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return Positioned(
        bottom: 16,
        right: 16,
        child: FloatingActionButton.small(
          heroTag: 'debug_fab',
          backgroundColor: Colors.deepPurple,
          onPressed: () => setState(() => _expanded = true),
          child: const Icon(Icons.bug_report, color: Colors.white, size: 20),
        ),
      );
    }

    final entries = DebugLogger.instance.entries;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: MediaQuery.of(context).size.height * 0.45,
      child: Material(
        elevation: 16,
        color: const Color(0xFF1A1A2E),
        child: Column(
          children: [
            // Barra de título
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: const Color(0xFF16213E),
              child: Row(
                children: [
                  const Icon(Icons.bug_report, color: Colors.amber, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Debug Log (${entries.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.white54, size: 18),
                    onPressed: _copyLogs,
                    tooltip: 'Copiar logs',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep, color: Colors.white54, size: 18),
                    onPressed: () => DebugLogger.instance.clear(),
                    tooltip: 'Limpar logs',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                    onPressed: () => setState(() => _expanded = false),
                    tooltip: 'Minimizar',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
            // Conteúdo
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: Text(
                        'Nenhum log ainda.\nResponda uma questão para ver os logs.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return _LogEntryWidget(entry: entry);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogEntryWidget extends StatelessWidget {
  final DebugEntry entry;

  const _LogEntryWidget({required this.entry});

  Color _tagColor(String tag) {
    switch (tag) {
      case 'SUBMIT':
        return Colors.orangeAccent;
      case 'PROCESS':
        return Colors.cyanAccent;
      case 'QUESTION':
        return Colors.lightGreenAccent;
      case 'STUDENT':
        return Colors.pinkAccent;
      case '━━━':
        return Colors.amber;
      default:
        return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSeparator = entry.tag == '━━━';

    if (isSeparator) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          entry.message,
          style: const TextStyle(
            color: Colors.amber,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              children: [
                TextSpan(
                  text: '[${entry.timeStr}]',
                  style: const TextStyle(color: Colors.white38),
                ),
                TextSpan(
                  text: '[${entry.tag}] ',
                  style: TextStyle(
                    color: _tagColor(entry.tag),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: entry.message,
                  style: TextStyle(
                    color: entry.message.contains('✗')
                        ? Colors.redAccent
                        : entry.message.contains('✓') || entry.message.contains('CORRETO')
                            ? Colors.greenAccent
                            : entry.message.contains('⚠')
                                ? Colors.orangeAccent
                                : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          if (entry.data != null)
            ...entry.data!.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  '${e.key}: ${e.value}',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
