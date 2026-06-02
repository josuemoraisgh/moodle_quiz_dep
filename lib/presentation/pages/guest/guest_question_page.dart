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
/// Expõe callbacks via notifiers para que o [PresentationViewer] exiba os
/// botões de login/logout na sua própria toolbar — evitando barra dupla no
/// modo embedado:
///   • [quizLoginNotifier]  — não autenticado → botão "Entrar"
///   • [quizLogoutNotifier] — autenticado    → botão "Sair"
class GuestQuestionPage extends StatefulWidget {
  const GuestQuestionPage({super.key});

  @override
  State<GuestQuestionPage> createState() => _GuestQuestionPageState();
}

class _GuestQuestionPageState extends State<GuestQuestionPage> {
  AuthController? _auth;

  VoidCallback? _activeLoginCb;
  VoidCallback? _activeLogoutCb;

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

      final loggedIn = _auth?.isLoggedIn ?? false;

      // Login callback: só quando não autenticado.
      final loginCb = loggedIn
          ? null
          : () {
              try {
                if (context.mounted) context.go(AppRouter.login);
              } catch (_) {}
            };

      // Logout callback: só quando autenticado.
      final logoutCb = loggedIn
          ? () async {
              try {
                await _auth?.logout();
              } catch (_) {}
            }
          : null;

      _activeLoginCb = loginCb;
      _activeLogoutCb = logoutCb;
      quizLoginNotifier.value = loginCb;
      quizLogoutNotifier.value = logoutCb;
    });
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    // Limpa apenas se ainda é nosso callback — evita apagar valor da instância
    // entrante durante transição de AnimatedSwitcher.
    if (quizLoginNotifier.value == _activeLoginCb) {
      quizLoginNotifier.value = null;
    }
    if (quizLogoutNotifier.value == _activeLogoutCb) {
      quizLogoutNotifier.value = null;
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
            decoration: BoxDecoration(gradient: context.appColors.bgGradient),
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
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: colors.cardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.quiz_outlined, color: colors.textSecondary, size: 48),
          const SizedBox(height: 10),
          Text(
            'Nenhuma questão foi fornecida para visualização.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
