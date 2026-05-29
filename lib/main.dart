import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/local_ip.dart';
import 'data/datasources/local_state_client.dart';
import 'data/datasources/local_state_server.dart';
import 'data/datasources/moodle_datasource.dart';
import 'data/datasources/moodle_state_datasource.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'data/repositories/quiz_repository_impl.dart';
import 'domain/usecases/close_question_usecase.dart';
import 'domain/usecases/login_usecase.dart';
import 'domain/usecases/release_question_usecase.dart';
import 'presentation/controllers/auth_controller.dart';
import 'presentation/controllers/professor_controller.dart';
import 'presentation/controllers/student_controller.dart';

/// Servidor local (professor). Exposto globalmente para que a QrCodePage
/// consiga ler o IP e a porta sem precisar de Provider adicional.
LocalStateDatasource? localServer;

/// Ponto de entrada – composição de dependências seguindo princípio D (IoC).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Lê config.json estático ───────────────────────────────────────────────
  try {
    final raw = await rootBundle.loadString('assets/config.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    AppConfig.loadFromMap(map);
  } catch (_) {
    // Arquivo ausente em dev local – segue com valores padrão
  }

  // ── Datasource Moodle (sempre necessário para auth + questões) ────────────
  final moodleDs = MoodleDatasource();

  // ── Escolhe datasource de estado: local ou Moodle ─────────────────────────
  final IStateDatasource stateDs = await _buildStateDatasource(moodleDs);

  // ── Instancia dependências ────────────────────────────────────────────────
  final authRepo = AuthRepositoryImpl(moodleDs);
  final quizRepo = QuizRepositoryImpl(stateDs, moodleDs);

  final loginUseCase = LoginUseCase(authRepo);
  final releaseUseCase = ReleaseQuestionUseCase(quizRepo);
  final closeUseCase = CloseQuestionUseCase(quizRepo);

  final authCtrl = AuthController(
    loginUseCase: loginUseCase,
    repository: authRepo,
  );

  await authCtrl.loadSavedSession();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authCtrl),
        ChangeNotifierProvider(
          create: (_) => ProfessorController(
            quizRepo: quizRepo,
            releaseQuestion: releaseUseCase,
            closeQuestion: closeUseCase,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => StudentController(
            quizRepo: quizRepo,
          ),
        ),
      ],
      child: const MoodleQuizApp(),
    ),
  );
}

/// Decide qual datasource de estado usar:
///
/// • Android/Desktop com local_mode=true  → LocalStateDatasource (sobe servidor HTTP)
/// • Flutter Web em IP de rede local      → LocalStateClient (lê do servidor do professor)
/// • Qualquer outro caso                  → MoodleStateDatasource (comportamento original)
Future<IStateDatasource> _buildStateDatasource(
    IMoodleDatasource moodleDs) async {
  // ── Modo professor (Android) ──────────────────────────────────────────────
  if (!kIsWeb && AppConfig.localMode) {
    final server = LocalStateDatasource(port: AppConfig.localServerPort);
    await server.startServer();
    localServer = server;
    return server;
  }

  // ── Modo aluno via rede local (Flutter Web) ───────────────────────────────
  // Detecta automaticamente: se o app web foi aberto de um IP local,
  // usa o mesmo host como servidor de estado (sem polling ao Moodle).
  if (kIsWeb) {
    final localApiUrl = _detectLocalServerFromBrowser();
    if (localApiUrl != null) {
      return LocalStateClient(serverUrl: localApiUrl);
    }
  }

  // ── Fallback: comportamento original via Moodle ───────────────────────────
  return MoodleStateDatasource(moodleDs);
}

/// Em Flutter Web, lê a URL atual do browser. Se o hostname for um IP de rede
/// local (192.168.x.x, 10.x.x.x, etc.) assume que o servidor do professor está
/// neste mesmo host e retorna a URL da API local.
String? _detectLocalServerFromBrowser() {
  if (!kIsWeb) return null;
  try {
    final base = Uri.base;
    final host = base.host;
    if (isLocalNetworkHost(host)) {
      final port = base.port > 0 ? base.port : AppConfig.localServerPort;
      return '${base.scheme}://$host:$port/api';
    }
  } catch (_) {}
  return null;
}

class MoodleQuizApp extends StatelessWidget {
  const MoodleQuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = AppRouter.build(context);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
