import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config/quiz_runtime_config.dart';
import '../../presentation/controllers/auth_controller.dart';
import '../../presentation/pages/guest/guest_question_page.dart';
import '../../presentation/pages/login_page.dart';
import '../../presentation/pages/professor/professor_home_page.dart';
import '../../presentation/pages/professor/professor_quiz_selection_page.dart';
import '../../presentation/pages/professor/professor_setup_page.dart';
import '../../presentation/pages/professor/ranking_page.dart';
import '../../presentation/pages/student/student_lobby_page.dart';

class AppRouter {
  static const String login = '/login';
  static const String professorSetup = '/professor/setup';
  static const String professorQuiz = '/professor/quiz';
  static const String professor = '/professor';
  static const String professorHome = '/professor'; // alias
  static const String professorRank = '/professor/rank';
  static const String studentLobby = '/student/lobby';
  static const String guestQuestion = '/guest/question';

  static GoRouter build(BuildContext context) {
    final runtime = context.read<QuizRuntimeConfig>();
    return GoRouter(
      initialLocation:
          runtime.singleQuestionByDependency ? guestQuestion : login,
      redirect: (context, state) {
        final auth = context.read<AuthController>();
        final runtime = context.read<QuizRuntimeConfig>();
        final loc = state.matchedLocation;

        if (loc == guestQuestion) {
          if (!runtime.singleQuestionByDependency) {
            return auth.isLoggedIn
                ? (auth.user!.isTeacher ? professorQuiz : studentLobby)
                : login;
          }
          if (!auth.isLoggedIn) return null;
          // Modo dependência: professor vai para tela de gestão, aluno permanece.
          return auth.user!.isTeacher ? professorQuiz : null;
        }

        // Setup: abre quando há configuração pendente OU ?force (professor panel).
        if (loc == professorSetup) {
          final force = state.uri.queryParameters.containsKey('force');
          if (force || auth.requiresSetup) return null;
          if (!auth.isLoggedIn) return login;
          return auth.user!.isTeacher ? professorQuiz : studentLobby;
        }

        // Não autenticado → login
        if (!auth.isLoggedIn && loc != login) return login;

        if (auth.isLoggedIn) {
          final user = auth.user!;
          if (loc == login) {
            return user.isTeacher ? professorQuiz : studentLobby;
          }
          if (!user.isTeacher && loc.startsWith('/professor')) {
            return studentLobby;
          }
          if (user.isTeacher && loc.startsWith('/student')) {
            return professorQuiz;
          }
        }

        return null;
      },
      routes: [
        GoRoute(
          path: guestQuestion,
          builder: (_, __) => const GuestQuestionPage(),
        ),
        GoRoute(path: login, builder: (_, __) => const LoginPage()),
        GoRoute(
            path: professorSetup,
            builder: (_, state) => ProfessorSetupPage(
                  showAllFields:
                      state.uri.queryParameters.containsKey('force'),
                )),
        GoRoute(
            path: professorQuiz,
            builder: (_, __) => const ProfessorQuizSelectionPage()),
        GoRoute(
          path: professor,
          builder: (_, __) => const ProfessorHomePage(),
          routes: [
            GoRoute(path: 'rank', builder: (_, __) => const RankingPage()),
          ],
        ),
        GoRoute(
            path: studentLobby, builder: (_, __) => const StudentLobbyPage()),
      ],
    );
  }
}
