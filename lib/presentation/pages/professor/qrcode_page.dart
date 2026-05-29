import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/local_ip.dart';
import '../../../main.dart' show localServer;

class QrCodePage extends StatefulWidget {
  const QrCodePage({super.key});

  @override
  State<QrCodePage> createState() => _QrCodePageState();
}

class _QrCodePageState extends State<QrCodePage> {
  String? _localIp;
  List<({String name, String ip})> _allIps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadIps();
  }

  Future<void> _loadIps() async {
    final ip = await getLocalIp();
    final all = await getAllLocalIps();
    if (mounted) {
      setState(() {
        _localIp = ip;
        _allIps = all;
        _loading = false;
      });
    }
  }

  String get _studentUrl {
    if (AppConfig.localMode && _localIp != null) {
      return 'http://$_localIp:${AppConfig.localServerPort}';
    }
    return AppConfig.studentUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppTheme.textSecondary),
                      tooltip: 'Voltar',
                      onPressed: () => context.go(AppRouter.professor),
                    ),
                    const Expanded(
                      child: Text(
                        'QR Code do Aluno',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _QrCodeContent(
                        studentUrl: _studentUrl,
                        localMode: AppConfig.localMode,
                        serverRunning: localServer?.isRunning ?? false,
                        allIps: _allIps,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrCodeContent extends StatelessWidget {
  final String studentUrl;
  final bool localMode;
  final bool serverRunning;
  final List<({String name, String ip})> allIps;

  const _QrCodeContent({
    required this.studentUrl,
    required this.localMode,
    required this.serverRunning,
    required this.allIps,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final qrSize = (screenWidth * 0.65).clamp(200.0, 500.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          // ── Status do servidor local ──────────────────────────────────
          if (localMode) _ServerStatusBadge(running: serverRunning),
          if (localMode) const SizedBox(height: 16),

          // ── QR Code gerado dinamicamente ──────────────────────────────
          Container(
            width: qrSize,
            height: qrSize,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.4),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: QrImageView(
              data: studentUrl,
              version: QrVersions.auto,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),

          const SizedBox(height: 28),

          // ── URL clicável ──────────────────────────────────────────────
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: studentUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('URL copiada!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    studentUrl,
                    style: TextStyle(
                      color: localMode
                          ? AppTheme.primary
                          : AppTheme.textPrimary,
                      fontSize: localMode ? 18 : 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.copy_rounded,
                    size: 18, color: AppTheme.textSecondary),
              ],
            ),
          ),

          // ── Lista de IPs disponíveis (modo local) ─────────────────────
          if (localMode && allIps.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(color: AppTheme.textSecondary),
            const SizedBox(height: 8),
            const Text(
              'Interfaces de rede detectadas:',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 6),
            ...allIps.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${e.name}: ${e.ip}',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],

          // ── Instrução para modo local ─────────────────────────────────
          if (localMode) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Alunos: conecte no Wi-Fi do roteador e escaneie o QR code '
                'ou digite o endereço acima no navegador.',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ServerStatusBadge extends StatelessWidget {
  final bool running;
  const _ServerStatusBadge({required this.running});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: running ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: running ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            running ? Icons.wifi_tethering : Icons.wifi_tethering_off,
            color: running ? Colors.green : Colors.red,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            running ? 'Servidor local ativo' : 'Servidor local inativo',
            style: TextStyle(
              color: running ? Colors.green : Colors.red,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
