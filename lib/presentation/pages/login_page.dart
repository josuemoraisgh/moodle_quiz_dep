import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config/quiz_runtime_config.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../controllers/auth_controller.dart';

/// Tela de autenticação — sempre a primeira tela do sistema.
///
/// Três opções:
///   • Professor  — senha exclusiva, acesso total.
///   • Aluno      — seleciona o nome + senha compartilhada.
///   • Convidado  — acesso somente-leitura, sem senha.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _professorLabel = 'Professor';

  final _baseUrlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String? _selectedName;
  bool _obscurePass = true;

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _nameCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final auth = context.read<AuthController>();
    final name = auth.isOnlineMode ? _nameCtrl.text.trim() : _selectedName;
    if (name == null || name.isEmpty || _passCtrl.text.isEmpty) return;

    await auth.login(
      name: name,
      password: _passCtrl.text,
      baseUrl: auth.isOnlineMode ? _baseUrlCtrl.text : null,
    );
    if (!mounted) return;
    if (auth.error != null) return;

    _navigateAfterLogin(auth);
  }

  Future<void> _loginAsGuest() async {
    final auth = context.read<AuthController>();
    await auth.loginAsGuest();
    if (!mounted) return;
    _navigateAfterLogin(auth);
  }

  void _navigateAfterLogin(AuthController auth) {
    final runtime = context.read<QuizRuntimeConfig>();
    final user = auth.user!;
    if (user.isTeacher) {
      context.go(AppRouter.professorQuiz);
    } else if (user.isGuest || runtime.singleQuestionByDependency) {
      context.go(AppRouter.guestQuestion);
    } else {
      context.go(AppRouter.studentLobby);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
        child: Center(
          child: SingleChildScrollView(
            padding: Responsive.horizontalPadding(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Consumer<AuthController>(
                builder: (context, auth, _) {
                  final runtime = context.watch<QuizRuntimeConfig>();
                  if (_baseUrlCtrl.text.isEmpty &&
                      runtime.moodleBaseUrl.isNotEmpty) {
                    _baseUrlCtrl.text = runtime.moodleBaseUrl;
                  }

                  final names = [
                    _professorLabel,
                    ...auth.students.map((s) => s.name),
                  ];

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _AppLogo(),
                      const SizedBox(height: 16),
                      Text(
                        auth.settings.quizTitle,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Como deseja acessar?',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // ── Modo online ───────────────────────────────────────
                      if (auth.isOnlineMode) ...[
                        TextFormField(
                          controller: _baseUrlCtrl,
                          style: const TextStyle(color: AppTheme.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'URL do Moodle',
                            prefixIcon: Icon(Icons.public_rounded),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _nameCtrl,
                          style: const TextStyle(color: AppTheme.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Usuário Moodle',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          onFieldSubmitted: (_) => _login(),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── Dropdown de nome ──────────────────────────────────
                      if (!auth.isOnlineMode)
                        DropdownButtonFormField<String>(
                          initialValue: _selectedName,
                          decoration: const InputDecoration(
                            labelText: 'Nome',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          dropdownColor: AppTheme.bgCard,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 15),
                          hint: const Text('Selecione…',
                              style:
                                  TextStyle(color: AppTheme.textSecondary)),
                          items: names
                              .map((n) => DropdownMenuItem(
                                    value: n,
                                    child: Row(
                                      children: [
                                        Icon(
                                          n == _professorLabel
                                              ? Icons.school_rounded
                                              : Icons.person_rounded,
                                          color: n == _professorLabel
                                              ? AppTheme.accent
                                              : AppTheme.textSecondary,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(n),
                                      ],
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() {
                            _selectedName = v;
                            _passCtrl.clear();
                          }),
                        ),
                      const SizedBox(height: 16),

                      // ── Senha ─────────────────────────────────────────────
                      TextFormField(
                        controller: _passCtrl,
                        obscureText: _obscurePass,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Senha',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePass
                                ? Icons.visibility_off
                                : Icons.visibility),
                            color: AppTheme.textSecondary,
                            onPressed: () =>
                                setState(() => _obscurePass = !_obscurePass),
                          ),
                        ),
                        onFieldSubmitted: (_) => _login(),
                      ),

                      if (auth.error != null) ...[
                        const SizedBox(height: 16),
                        _ErrorBox(message: auth.error!),
                      ],

                      const SizedBox(height: 24),

                      // ── Botão Entrar ──────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.login_rounded),
                          label: auth.isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text('Entrar',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                          onPressed: (auth.isLoading ||
                                  (auth.isOnlineMode
                                      ? _nameCtrl.text.trim().isEmpty
                                      : _selectedName == null) ||
                                  _passCtrl.text.isEmpty)
                              ? null
                              : _login,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ── Divisor ───────────────────────────────────────────
                      Row(
                        children: [
                          const Expanded(
                              child: Divider(color: AppTheme.textSecondary)),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('ou',
                                style: TextStyle(
                                    color: AppTheme.textSecondary
                                        .withValues(alpha: 0.6),
                                    fontSize: 12)),
                          ),
                          const Expanded(
                              child: Divider(color: AppTheme.textSecondary)),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // ── Botão Convidado ───────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.visibility_outlined,
                              size: 18),
                          label: const Text('Entrar como Convidado',
                              style: TextStyle(fontSize: 14)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textSecondary,
                            side: const BorderSide(
                                color: AppTheme.textSecondary, width: 0.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: auth.isLoading ? null : _loginAsGuest,
                        ),
                      ),

                      // ── Link de configuração (visível ao professor) ────────
                      if (!auth.isOnlineMode) ...[
                        const SizedBox(height: 20),
                        TextButton.icon(
                          onPressed: () =>
                              context.go(AppRouter.professorSetup),
                          icon: const Icon(Icons.settings_rounded,
                              size: 16, color: AppTheme.textSecondary),
                          label: const Text(
                            'Configurar quiz (Professor)',
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.5),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(Icons.quiz_rounded, color: Colors.white, size: 48),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style:
                    const TextStyle(color: AppTheme.danger, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
