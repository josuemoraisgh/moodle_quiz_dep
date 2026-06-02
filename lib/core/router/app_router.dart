import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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
  static const String professorHome = '/professor';
  static const String professorRank = '/professor/rank';
  static const String studentLobby = '/student/lobby';
  static const String guestQuestion = '/guest/question';

  static GoRouter build(BuildContext context) {
    return GoRouter(
      initialLocation: login,
      redirect: (context, state) {
        final auth = context.read<AuthController>();
        final loc = state.matchedLocation;

        // ── /guest/question ──────────────────────────────────────────────────
        if (loc == guestQuestion) {
          if (!auth.isLoggedIn) return login;
          if (auth.user!.isTeacher) return professorQuiz;
          // Somente convidado fica em guestQuestion (leitura dos slides).
          // Aluno vai sempre para o lobby: espera → questão → resultado.
          if (auth.user!.isGuest) return null;
          return studentLobby;
        }

        // ── /professor/setup ─────────────────────────────────────────────────
        if (loc == professorSetup) {
          final force = state.uri.queryParameters.containsKey('force');
          if (force || auth.requiresSetup) return null;
          if (!auth.isLoggedIn) return login;
          return auth.user!.isTeacher ? professorQuiz : studentLobby;
        }

        // ── Não autenticado → login ──────────────────────────────────────────
        if (!auth.isLoggedIn && loc != login) return login;

        // ── Redirecionamentos por perfil ─────────────────────────────────────
        if (auth.isLoggedIn) {
          final user = auth.user!;

          // Convidado vai sempre para guestQuestion — nunca fica no login.
          if (user.isGuest && loc != guestQuestion) return guestQuestion;

          // Na tela de login → vai para dashboard adequado
          if (loc == login) {
            return user.isTeacher ? professorQuiz : studentLobby;
          }

          // Aluno tentando acessar área do professor
          if (!user.isTeacher && loc.startsWith('/professor')) {
            return studentLobby;
          }

          // Professor tentando acessar área do aluno
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
