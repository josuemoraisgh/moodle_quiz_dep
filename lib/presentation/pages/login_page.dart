import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../controllers/auth_controller.dart';

/// Tela de login Moodle – responsiva (mobile e desktop).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlCtrl = TextEditingController(text: AppConfig.moodleBaseUrl);
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthController>();
    await auth.login(
      baseUrl: _urlCtrl.text.trim().replaceAll(RegExp(r'/+$'), ''),
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
    );
    if (!mounted) return;
    if (auth.error != null) return;

    if (auth.user!.isTeacher) {
      if (mounted) context.go(AppRouter.professorCourses);
    } else {
      if (mounted) context.go(AppRouter.studentCourses);
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
                builder: (context, auth, _) => Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _AppLogo(),
                      const SizedBox(height: 16),
                      Text('MoodleQuiz Live',
                          style: AppTheme.headlineLarge,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      const Text(
                        'Entre com suas credenciais do Moodle',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),

                      // ── URL do Moodle ────────────────────────────────────
                      TextFormField(
                        controller: _urlCtrl,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'URL do Moodle',
                          prefixIcon: Icon(Icons.public),
                          hintText: 'https://moodle.suainstituicao.edu.br',
                          hintStyle: TextStyle(color: AppTheme.textSecondary),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Informe a URL do Moodle';
                          }
                          if (!v.startsWith('http')) {
                            return 'URL deve começar com http';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // ── Usuário ──────────────────────────────────────────
                      TextFormField(
                        controller: _userCtrl,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Usuário',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => (v?.trim().isEmpty ?? true)
                            ? 'Informe o usuário'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // ── Senha ────────────────────────────────────────────
                      TextFormField(
                        controller: _passCtrl,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        obscureText: _obscurePass,
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
                        validator: (v) =>
                            (v?.isEmpty ?? true) ? 'Informe a senha' : null,
                      ),

                      // ── Erro ─────────────────────────────────────────────
                      if (auth.error != null) ...[
                        const SizedBox(height: 16),
                        _ErrorBox(message: auth.error!),
                      ],

                      const SizedBox(height: 24),

                      // ── Botão login ──────────────────────────────────────
                      ElevatedButton(
                        onPressed: auth.isLoading ? null : _login,
                        child: auth.isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5))
                            : const Text('Entrar'),
                      ),
                    ],
                  ),
                ),
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
          )
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
                style: const TextStyle(color: AppTheme.danger, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
