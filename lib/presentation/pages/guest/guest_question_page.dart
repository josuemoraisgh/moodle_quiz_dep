import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/quiz_runtime_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../controllers/auth_controller.dart';
import '../../widgets/question_engine_widget.dart';

/// Tela da apresentação (Port A / singleQuestionByDependency).
///
/// Não autenticado → questão em leitura + botão Login (quando há backend).
/// Professor logado → redirecionado pelo router para telas de gestão.
/// Não-professor logado → questão em leitura (sem botão Login).
/// Hospedagem estática / sem BD → apenas leitura, sem botão Login.
class GuestQuestionPage extends StatelessWidget {
  const GuestQuestionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final runtime = context.watch<QuizRuntimeConfig>();
    final auth = context.watch<AuthController>();
    final question =
        runtime.questions.isNotEmpty ? runtime.questions.first : null;

    // Botão Login só aparece quando não está logado E há backend disponível.
    final canLogin =
        !auth.isLoggedIn && (auth.isOnlineMode || auth.students.isNotEmpty);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: Responsive.horizontalPadding(context)
                  .add(const EdgeInsets.symmetric(vertical: 16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HeaderCard(
                      title: runtime.initialQuizName,
                      loggedInName: auth.user?.name,
                      onLogin:
                          canLogin ? () => context.go(AppRouter.login) : null,
                    ),
                    const SizedBox(height: 16),
                    if (question == null)
                      const _NoQuestionCard()
                    else
                      QuestionEngineWidget(
                        question: question,
                        mode: QuestionEngineMode.preview,
                        selectedAnswers: const {},
                        onSelectAnswer: null,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String title;
  final String? loggedInName;
  final VoidCallback? onLogin;

  const _HeaderCard({
    required this.title,
    required this.loggedInName,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? 'Questão' : title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (loggedInName != null)
            Text(
              'Visualização de $loggedInName — respostas desabilitadas nesta porta.',
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            )
          else
            const Text(
              'Visualização de convidado: respostas e feedback estão desabilitados.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          if (onLogin != null) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login_rounded),
                label: const Text('Fazer login'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoQuestionCard extends StatelessWidget {
  const _NoQuestionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.cardDecoration(),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.quiz_outlined, color: AppTheme.textSecondary, size: 48),
          SizedBox(height: 10),
          Text(
            'Nenhuma questão foi fornecida para visualização.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
