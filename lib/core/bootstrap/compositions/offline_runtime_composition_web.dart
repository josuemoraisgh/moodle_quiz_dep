import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../data/repositories/in_memory_auth_repository.dart';
import '../../../data/repositories/in_memory_quiz_repository.dart';
import '../../../domain/services/quiz_sync_server.dart';
import '../../config/quiz_runtime_config.dart';
import 'runtime_composition.dart';

Future<RuntimeComposition> buildOfflineRuntimeComposition(
  QuizRuntimeConfig config,
) async {
  // Resolve a URL de forma assíncrona — pode consultar /api/info para obter
  // o IP real da rede local (evita mostrar 127.0.0.1 no QR code).
  final serverUrl = await _resolveServerUrl(config);

  return RuntimeComposition(
    authRepositoryFactory: () => InMemoryAuthRepository(
      settings: config.settings,
      students: config.students,
    ),
    quizRepositoryFactory: (stateService) => InMemoryQuizRepository(
      stateService: stateService,
      students: config.students,
      quizzes: config.quizzes,
      questions: config.questions,
      initialQuizName: config.initialQuizName,
    ),
    syncServerFactory: () => HostedQuizSyncServer(serverUrl: serverUrl),
  );
}

/// Resolve a URL do servidor para o QR code:
/// 1. `config.studentUrl` — configurado explicitamente no PPTX/config.json
/// 2. `/api/info` — endpoint do servidor local que retorna os IPs de rede real
///    (resolve o problema de 127.0.0.1 que não é acessível de outros devices)
/// 3. `Uri.base` como fallback se o servidor não tiver /api/info
Future<String> _resolveServerUrl(QuizRuntimeConfig config) async {
  if (config.studentUrl.trim().isNotEmpty) return config.studentUrl.trim();

  try {
    final base = Uri.base;
    if (base.host.isEmpty) return '';

    // Tenta obter o IP LAN real consultando o servidor local.
    final lanUrl = await _fetchLanUrlFromServer(base);
    if (lanUrl != null) return lanUrl;

    // Fallback: usa o host atual (pode ser 127.0.0.1 se aberto localmente).
    final port = (base.hasPort && base.port != 80 && base.port != 443)
        ? ':${base.port}'
        : '';
    return '${base.scheme}://${base.host}$port';
  } catch (_) {}

  return '';
}

/// Consulta `GET /api/info` no mesmo servidor e extrai a primeira URL de rede.
/// Retorna null se o endpoint não existir ou falhar (timeout 2s).
Future<String?> _fetchLanUrlFromServer(Uri base) async {
  try {
    final infoUri = Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/api/info',
    );
    final response =
        await http.get(infoUri).timeout(const Duration(seconds: 2));
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final urls = (data['urls'] as List<dynamic>?)?.cast<String>() ?? [];

    // Prefere IPs de rede (não loopback).
    final lan = urls.firstWhere(
      (u) => !u.contains('127.') && !u.contains('localhost'),
      orElse: () => '',
    );
    return lan.isEmpty ? null : lan;
  } catch (_) {
    return null;
  }
}
