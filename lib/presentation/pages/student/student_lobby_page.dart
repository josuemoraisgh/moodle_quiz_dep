import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/entities/quiz_state_entity.dart';
import '../../../domain/entities/score_entity.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/student_controller.dart';
import '../../widgets/debug_panel.dart';
import 'student_question_page.dart';

/// Tela do estudante – lobby de espera e questão ativa.
class StudentLobbyPage extends StatefulWidget {
  const StudentLobbyPage({super.key});

  @override
  State<StudentLobbyPage> createState() => _StudentLobbyPageState();
}

class _StudentLobbyPageState extends State<StudentLobbyPage> {
  @override
  void dispose() {
    context.read<StudentController>().stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<StudentController, AuthController>(
      builder: (context, student, auth, _) {
        final state = student.quizState;

        return Scaffold(
          body: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
                child: SafeArea(
                  child: Column(
                    children: [
                      _TopBar(
                        title: state.quizTitle,
                        fullname: auth.user!.fullname,
                        onBack: () => context.go(AppRouter.studentCourses),
                        onLogout: () async {
                          student.stopPolling();
                          await auth.logout();
                          if (context.mounted) context.go(AppRouter.login);
                        },
                      ),
                      Expanded(
                        child: _buildBody(context, state, student, auth),
                      ),
                    ],
                  ),
                ),
              ),
              // Painel de debug flutuante
              const DebugPanel(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    QuizStateEntity state,
    StudentController student,
    AuthController auth,
  ) {
    final myScore = student.myScore(auth.user!.id.toString());

    // Questão ativa → mostra tela de resposta
    if (state.isActive && student.currentQuestion != null) {
      return StudentQuestionPage(
        question: student.currentQuestion!,
        endsAt: state.endsAt,
        selectedAnswers: student.selectedAnswers,
        hasAnswered: student.hasAnswered,
        isSubmitting: student.isSubmitting,
        onSelectAnswer: student.selectAnswer,
        onSubmit: () => student.submitAnswer(auth.user!),
      );
    }

    // Carregando questão
    if (state.isActive && student.isLoadingQuestion) {
      return const Center(child: CircularProgressIndicator());
    }

    // Questão fechada → mostra resultado
    if (state.isClosed) {
      return _ClosedQuestionView(
        wasCorrect: student.lastAnswerCorrect,
        wasGraded: student.lastAnswerGraded,
        answered: student.hasAnswered,
        selectedText: student.selectedChoiceText,
        myScore: myScore,
        totalPages: state.totalPages,
      );
    }

    // Finalizado → tela de fim
    if (state.isFinished) {
      return _FinalView(myScore: myScore, totalPages: state.totalPages);
    }

    // Erro de rede / questão (não bloqueia quando quiz está ativo aguardando tentativa)
    if (student.error != null && !state.isActive) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text(
            'Erro: ${student.error}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: student.clearError,
            child: const Text('Tentar novamente'),
          ),
        ],
      );
    }

    // Aguardando (estado idle ou quiz ativo ainda carregando tentativa)
    return _WaitingView(
      title: state.quizTitle,
      userName: auth.user!.fullname,
      currentPage: state.currentPage,
      totalPages: state.totalPages,
      myScore: myScore,
      attemptError: student.attemptError,
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final String fullname;
  final VoidCallback onBack;
  final VoidCallback onLogout;

  const _TopBar({
    required this.title,
    required this.fullname,
    required this.onBack,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: AppTheme.textSecondary, size: 18),
            onPressed: onBack,
            tooltip: 'Trocar disciplina',
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.quiz_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            fullname.split(' ').first,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.logout,
                color: AppTheme.textSecondary, size: 20),
            onPressed: onLogout,
            tooltip: 'Sair',
          ),
        ],
      ),
    );
  }
}

class _WaitingView extends StatelessWidget {
  final String title;
  final String userName;
  final int currentPage;
  final int totalPages;
  final ScoreEntity? myScore;
  final String? attemptError;

  const _WaitingView({
    required this.title,
    required this.userName,
    required this.currentPage,
    required this.totalPages,
    required this.myScore,
    this.attemptError,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Responsive.horizontalPadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: AppTheme.cardDecoration(
                  gradient: AppTheme.primaryGradient, glowing: true),
              child: const Icon(Icons.hourglass_top_rounded,
                  color: Colors.white, size: 60),
            )
                .animate(onPlay: (c) => c.repeat())
                .shimmer(duration: 2000.ms, color: AppTheme.primaryLight),
            const SizedBox(height: 32),
            Text(
              'Olá, ${userName.split(' ').first}!',
              style: AppTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Aguardando o professor liberar\na próxima questão...',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 16, height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (attemptError != null) ...[
              const SizedBox(height: 24),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.orange, size: 20),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'O quiz ainda não está visível para você.\nPeça ao professor para liberar a atividade no Moodle.',
                        style: const TextStyle(
                            color: Colors.orange, fontSize: 13, height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (currentPage >= 0) ...[
              const SizedBox(height: 24),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: AppTheme.cardDecoration(),
                child: Text(
                  'Questão ${currentPage + 1}'
                  '${totalPages > 0 ? ' de $totalPages' : ''} concluída',
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 15),
                ),
              ),
            ],
            if (myScore != null) ...[
              const SizedBox(height: 16),
              _ScoreSummaryCard(score: myScore!, totalPages: totalPages),
            ],
            const SizedBox(height: 40),
            const _PulseDots(),
          ],
        ),
      ),
    );
  }
}

class _PulseDots extends StatelessWidget {
  const _PulseDots();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: const BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
          ),
        )
            .animate(
                delay: Duration(milliseconds: i * 200),
                onPlay: (c) => c.repeat(reverse: true))
            .scaleXY(end: 0.5, duration: 600.ms)
            .fadeOut(duration: 600.ms),
      ),
    );
  }
}

class _ScoreSummaryCard extends StatelessWidget {
  final ScoreEntity score;
  final int totalPages;
  const _ScoreSummaryCard({required this.score, required this.totalPages});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: AppTheme.gold, size: 20),
          const SizedBox(width: 8),
          Text(
            '${score.score} pts',
            style: const TextStyle(
                color: AppTheme.gold,
                fontWeight: FontWeight.w800,
                fontSize: 16),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.check_circle_rounded,
              color: AppTheme.success, size: 18),
          const SizedBox(width: 6),
          Text(
            '${score.correctCount}'
            '${totalPages > 0 ? '/$totalPages' : ''} corretas',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.leaderboard_rounded,
              color: AppTheme.accent, size: 18),
          const SizedBox(width: 6),
          Text(
            '${score.rank}º',
            style: const TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w700,
                fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _ClosedQuestionView extends StatelessWidget {
  final bool wasCorrect;
  final bool wasGraded;
  final bool answered;
  final String? selectedText;
  final ScoreEntity? myScore;
  final int totalPages;

  const _ClosedQuestionView({
    required this.wasCorrect,
    required this.wasGraded,
    required this.answered,
    required this.selectedText,
    required this.myScore,
    required this.totalPages,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Responsive.horizontalPadding(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: answered
                        ? (!wasGraded
                            ? [AppTheme.accent, AppTheme.primary]
                            : (wasCorrect
                                ? [AppTheme.success, const Color(0xFF00A152)]
                                : [AppTheme.danger, const Color(0xFFB71C1C)]))
                        : [AppTheme.warning, const Color(0xFFF57F17)],
                  ),
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: [
                    BoxShadow(
                      color: (answered
                              ? (!wasGraded
                                  ? AppTheme.accent
                                  : (wasCorrect
                                      ? AppTheme.success
                                      : AppTheme.danger))
                              : AppTheme.warning)
                          .withValues(alpha: 0.4),
                      blurRadius: 24,
                    )
                  ],
                ),
                child: Icon(
                  answered
                      ? (!wasGraded
                          ? Icons.check_circle
                          : (wasCorrect ? Icons.check_circle : Icons.cancel))
                      : Icons.timer_off,
                  color: Colors.white,
                  size: 52,
                ),
              ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
              const SizedBox(height: 24),
              Text(
                answered
                    ? (!wasGraded
                        ? 'Resposta enviada!'
                        : (wasCorrect ? 'Correto! +1000 pts' : 'Incorreto!'))
                    : 'Tempo esgotado!',
                style: AppTheme.headlineMedium,
              ),
              if (selectedText != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: (wasCorrect ? AppTheme.success : AppTheme.danger)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (wasCorrect ? AppTheme.success : AppTheme.danger)
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Sua resposta:',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selectedText!,
                        style: TextStyle(
                          color: !wasGraded
                              ? AppTheme.accent
                              : (wasCorrect
                                  ? AppTheme.success
                                  : AppTheme.danger),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
              if (myScore != null) ...[
                const SizedBox(height: 20),
                _ScoreSummaryCard(score: myScore!, totalPages: totalPages),
              ],
              const SizedBox(height: 24),
              const Text(
                'Aguardando próxima questão...',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FinalView extends StatelessWidget {
  final ScoreEntity? myScore;
  final int totalPages;
  const _FinalView({required this.myScore, required this.totalPages});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Responsive.horizontalPadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events, color: AppTheme.gold, size: 80)
                .animate()
                .scale(duration: 600.ms, curve: Curves.elasticOut)
                .then()
                .shimmer(duration: 1500.ms, color: Colors.white),
            const SizedBox(height: 20),
            Text('Quiz Finalizado!', style: AppTheme.headlineLarge),
            const SizedBox(height: 8),
            const Text(
              'Obrigado por participar!',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
            ),
            if (myScore != null) ...[
              const SizedBox(height: 32),
              _ScoreSummaryCard(score: myScore!, totalPages: totalPages),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.cardDecoration(),
                child: Column(
                  children: [
                    _StatRow(
                      icon: Icons.format_list_numbered_rounded,
                      label: 'Questões respondidas',
                      value: '${myScore!.totalAnswered}'
                          '${totalPages > 0 ? ' de $totalPages' : ''}',
                      color: AppTheme.textPrimary,
                    ),
                    const SizedBox(height: 8),
                    _StatRow(
                      icon: Icons.check_circle_rounded,
                      label: 'Respostas corretas',
                      value: '${myScore!.correctCount}',
                      color: AppTheme.success,
                    ),
                    const SizedBox(height: 8),
                    _StatRow(
                      icon: Icons.cancel_rounded,
                      label: 'Respostas erradas',
                      value:
                          '${myScore!.totalAnswered - myScore!.correctCount}',
                      color: AppTheme.danger,
                    ),
                    const SizedBox(height: 8),
                    _StatRow(
                      icon: Icons.star_rounded,
                      label: 'Pontuação total',
                      value: '${myScore!.score} pts',
                      color: AppTheme.gold,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14))),
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 15)),
      ],
    );
  }
}
