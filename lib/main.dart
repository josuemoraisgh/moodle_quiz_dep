import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/database/app_database.dart';
import 'core/router/app_router.dart';
import 'core/services/quiz_state_service.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/local_datasource.dart';
import 'data/datasources/offline_local_server.dart';
import 'data/repositories/local_auth_repository_impl.dart';
import 'data/repositories/local_quiz_repository_impl.dart';
import 'presentation/controllers/auth_controller.dart';
import 'presentation/controllers/professor_controller.dart';
import 'presentation/controllers/student_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Banco de dados local ──────────────────────────────────────────────────
  final db = AppDatabase.instance;
  final ds = LocalDatasource(db);

  // ── Estado compartilhado (professor ↔ aluno no mesmo processo) ────────────
  final stateService = QuizStateService();

  // ── Servidor HTTP local (professor) ───────────────────────────────────────
  final server = OfflineLocalServer(port: AppConfig.localServerPort);
  await server.start();

  // ── Repositórios ──────────────────────────────────────────────────────────
  final authRepo = LocalAuthRepositoryImpl(ds);
  final quizRepo = LocalQuizRepository(ds, stateService);

  // ── Controllers ───────────────────────────────────────────────────────────
  final authCtrl = AuthController(authRepo);
  await authCtrl.init(); // carrega settings + sessão salva

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: stateService),
        ChangeNotifierProvider.value(value: authCtrl),
        ChangeNotifierProvider(
          create: (_) => ProfessorController(
            quizRepo: quizRepo,
            stateService: stateService,
            server: server,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => StudentController(
            quizRepo: quizRepo,
            stateService: stateService,
          ),
        ),
      ],
      child: const _App(),
    ),
  );
}

class _App extends StatelessWidget {
  const _App();

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
