import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/entities/quiz_state_entity.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/student_controller.dart';
import '../../widgets/question_engine_widget.dart';
import '../../widgets/timer_widget.dart';

/// Tela do aluno: lobby de espera + visualização de uma questão por vez.
class StudentLobbyPage extends StatefulWidget {
  const StudentLobbyPage({super.key});

  @override
  State<StudentLobbyPage> createState() => _StudentLobbyPageState();
}

class _StudentLobbyPageState extends State<StudentLobbyPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthController>().user;
      if (user != null) {
        context.read<StudentController>().initLocal(user);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<StudentController, AuthController>(
      builder: (context, student, auth, _) {
        final state = student.quizState;
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
            child: SafeArea(
              child: Column(
                children: [
                  _StudentAppBar(auth: auth, student: student),
                  Expanded(child: _body(context, student, state)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body(
      BuildContext ctx, StudentController student, QuizStateEntity state) {
    if (state.isFinished) return const _FinishedView();
    if (state.isActive || state.isClosed) {
      return _QuestionView(student: student, state: state);
    }
    return _WaitingView(title: state.quizTitle);
  }
}

// ── AppBar ────────────────────────────────────────────────────────────────────

class _StudentAppBar extends StatelessWidget {
  final AuthController auth;
  final StudentController student;
  const _StudentAppBar({required this.auth, required this.student});

  @override
  Widget build(BuildContext context) {
    final name = auth.user?.name ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.person_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
          IconButton(
            icon:
                const Icon(Icons.logout, color: AppTheme.textSecondary),
            tooltip: 'Sair',
            onPressed: () async {
              student.dispose();
              await auth.logout();
              if (context.mounted) context.go(AppRouter.login);
            },
          ),
        ],
      ),
    );
  }
}

// ── Lobby de espera ───────────────────────────────────────────────────────────

class _WaitingView extends StatelessWidget {
  final String title;
  const _WaitingView({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Responsive.horizontalPadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.hourglass_top_rounded,
                  color: Colors.white, size: 40),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(
                    end: 0.85,
                    duration: 900.ms,
                    curve: Curves.easeInOut),
            const SizedBox(height: 24),
            Text(
              title.isNotEmpty ? title : 'Quiz Presencial',
              style: AppTheme.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Aguarde o professor liberar a próxima questão…',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Questão ativa ─────────────────────────────────────────────────────────────

class _QuestionView extends StatelessWidget {
  final StudentController student;
  final QuizStateEntity state;
  const _QuestionView({required this.student, required this.state});

  @override
  Widget build(BuildContext context) {
    final q = student.currentQuestion;
    if (q == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Carregando questão…',
                style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: Responsive.horizontalPadding(context)
          .add(const EdgeInsets.symmetric(vertical: 16)),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Timer
              if (state.isActive &&
                  state.endsAt != null &&
                  !student.hasAnswered) ...[
                TimerWidget(endsAt: state.endsAt!, onTimeUp: () {}),
                const SizedBox(height: 12),
              ],

              // Questão
              QuestionEngineWidget(
                question: q,
                mode: (student.hasAnswered || state.isClosed)
                    ? QuestionEngineMode.preview
                    : QuestionEngineMode.answer,
                selectedAnswers: student.selectedAnswers,
                onSelectAnswer: (student.hasAnswered || state.isClosed)
                    ? null
                    : (name, value) => student.selectAnswer(name, value),
              ),
              const SizedBox(height: 16),

              // Feedback
              if (student.hasAnswered)
                _FeedbackCard(
                  correct: student.lastAnswerCorrect,
                  graded: student.lastAnswerGraded,
                  choiceText: student.selectedChoiceText,
                ),

              // Botão enviar
              if (!student.hasAnswered && state.isActive) ...[
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: student.hasAnyAnswer &&
                          !student.isSubmitting
                      ? student.submitAnswer
                      : null,
                  icon: student.isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                  label: const Text('Enviar Resposta'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],

              // Encerrada sem resposta
              if (state.isClosed && !student.hasAnswered) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.warning.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.timer_off_rounded,
                          color: AppTheme.warning),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Tempo esgotado. Aguarde a próxima questão.',
                          style:
                              TextStyle(color: AppTheme.warning),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (student.error != null) ...[
                const SizedBox(height: 8),
                Text(student.error!,
                    style: const TextStyle(
                        color: AppTheme.danger, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final bool correct;
  final bool graded;
  final String? choiceText;
  const _FeedbackCard(
      {required this.correct,
      required this.graded,
      this.choiceText});

  @override
  Widget build(BuildContext context) {
    if (!graded) {
      return _card(AppTheme.accent, Icons.pending_rounded,
          'Resposta registrada', 'Será avaliada posteriormente.');
    }
    return _card(
      correct ? AppTheme.success : AppTheme.danger,
      correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
      correct ? 'Correto!' : 'Incorreto',
      choiceText != null ? 'Você respondeu: $choiceText' : null,
    );
  }

  Widget _card(Color color, IconData icon, String title,
      String? subtitle) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                if (subtitle != null)
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(
            begin: 0.3,
            duration: 400.ms,
            curve: Curves.easeOut);
  }
}

// ── Quiz finalizado ───────────────────────────────────────────────────────────

class _FinishedView extends StatelessWidget {
  const _FinishedView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_rounded,
              color: AppTheme.gold, size: 72),
          const SizedBox(height: 16),
          Text('Quiz Finalizado!',
              style:
                  AppTheme.headlineLarge.copyWith(color: AppTheme.gold)),
          const SizedBox(height: 8),
          const Text('Obrigado por participar!',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 15)),
        ],
      )
          .animate()
          .fadeIn(duration: 600.ms)
          .scale(
              begin: const Offset(0.8, 0.8), duration: 600.ms),
    );
  }
}
