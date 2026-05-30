import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/quiz_runtime_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/fullscreen_button.dart';
import '../../../core/utils/quiz_nav_notifier.dart';
import '../../controllers/auth_controller.dart';
import '../../widgets/question_engine_widget.dart';

/// Tela da apresentação (Port A / singleQuestionByDependency).
///
/// Expõe o callback de login via [quizLoginNotifier] para que o viewer
/// externo (PresentationViewer) exiba o botão na sua própria toolbar —
/// evitando barra dupla no modo embedado.
class GuestQuestionPage extends StatefulWidget {
  const GuestQuestionPage({super.key});

  @override
  State<GuestQuestionPage> createState() => _GuestQuestionPageState();
}

class _GuestQuestionPageState extends State<GuestQuestionPage> {
  AuthController? _auth;

  // Callback atual registrado no notifier — usado para evitar que dispose()
  // de uma instância sainte sobreponha o valor já definido pela instância
  // entrante (race durante AnimatedSwitcher).
  VoidCallback? _activeCallback;

  // Deduplica registros de addPostFrameCallback para evitar acúmulo em
  // rebuilds rápidos (ex: polling de QuizStateService).
  bool _pendingUpdate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newAuth = context.read<AuthController>();
    if (_auth != newAuth) {
      _auth?.removeListener(_onAuthChanged);
      _auth = newAuth;
      _auth!.addListener(_onAuthChanged);
    }
    _scheduleNotifierUpdate();
  }

  void _onAuthChanged() => _scheduleNotifierUpdate();

  void _scheduleNotifierUpdate() {
    if (_pendingUpdate) return;
    _pendingUpdate = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingUpdate = false;
      if (!mounted) return;
      final canLogin = !(_auth?.isLoggedIn ?? true);
      final cb = canLogin
          ? () {
              try {
                if (context.mounted) context.go(AppRouter.login);
              } catch (_) {}
            }
          : null;
      _activeCallback = cb;
      quizLoginNotifier.value = cb;
    });
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    // Só limpa o notifier se ainda contém nosso callback — evita apagar
    // o valor definido pela instância entrante durante uma transição.
    if (quizLoginNotifier.value == _activeCallback) {
      quizLoginNotifier.value = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = context.watch<QuizRuntimeConfig>();
    final question =
        runtime.questions.isNotEmpty ? runtime.questions.first : null;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 34, 24, 8),
                  child: question == null
                      ? const _NoQuestionCard()
                      : QuestionEngineWidget(
                          question: question,
                          mode: QuestionEngineMode.preview,
                          showTypeHeader: false,
                          baseFontSize: 25,
                          choiceSpacing: 6,
                          selectedAnswers: const {},
                          onSelectAnswer: null,
                        ),
                ),
              ),
            ),
          ),
          // Fullscreen apenas no modo standalone — no embedded o viewer tem o seu.
          if (!runtime.embeddedInPresentation)
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(child: const FullscreenButton()),
            ),
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
