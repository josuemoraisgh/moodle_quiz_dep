import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/entities/local_quiz_entity.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/professor_controller.dart';

/// Tela de seleção/importação de quiz para o professor.
class ProfessorQuizSelectionPage extends StatefulWidget {
  const ProfessorQuizSelectionPage({super.key});

  @override
  State<ProfessorQuizSelectionPage> createState() =>
      _ProfessorQuizSelectionPageState();
}

class _ProfessorQuizSelectionPageState
    extends State<ProfessorQuizSelectionPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = context.read<AuthController>().user;
      if (user != null) {
        await context.read<ProfessorController>().init(user);
      }
    });
  }

  Future<void> _importXml(ProfessorController prof) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    await prof.importFromXml(
      bytes: file.bytes!,
      fileName: file.name,
    );
    if (!mounted) return;
    if (prof.error == null) context.go(AppRouter.professor);
  }

  Future<void> _selectQuiz(
      ProfessorController prof, LocalQuizEntity quiz) async {
    await prof.selectQuiz(quiz);
    if (!mounted) return;
    context.go(AppRouter.professor);
  }

  Future<void> _deleteQuiz(
      ProfessorController prof, LocalQuizEntity quiz) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Excluir Quiz',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Excluir "${quiz.name}"?',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) await prof.deleteQuiz(quiz.id);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ProfessorController, AuthController>(
      builder: (context, prof, auth, _) {
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    children: [
                      // ── AppBar ──────────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: AppTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.school_rounded,
                                  color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Selecionar Quiz',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings_outlined,
                                  color: AppTheme.textSecondary),
                              tooltip: 'Configurações',
                              onPressed: () =>
                                  context.go(AppRouter.professorSetup),
                            ),
                            IconButton(
                              icon: const Icon(Icons.logout,
                                  color: AppTheme.textSecondary),
                              tooltip: 'Sair',
                              onPressed: () async {
                                await auth.logout();
                                if (context.mounted) {
                                  context.go(AppRouter.login);
                                }
                              },
                            ),
                          ],
                        ),
                      ),

                      // ── Importar XML ────────────────────────────────────
                      Padding(
                        padding: Responsive.horizontalPadding(context),
                        child: ElevatedButton.icon(
                          onPressed: prof.isLoading
                              ? null
                              : () => _importXml(prof),
                          icon: prof.isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.upload_file_rounded),
                          label: const Text('Importar Quiz (XML Moodle)'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),

                      // ── Erro ────────────────────────────────────────────
                      if (prof.error != null)
                        Padding(
                          padding: Responsive.horizontalPadding(context)
                              .add(const EdgeInsets.only(top: 8)),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: AppTheme.danger.withValues(
                                      alpha: 0.4)),
                            ),
                            child: Text(prof.error!,
                                style: const TextStyle(
                                    color: AppTheme.danger, fontSize: 13)),
                          ),
                        ),

                      const SizedBox(height: 16),

                      // ── Lista de quizzes ────────────────────────────────
                      Expanded(
                        child: prof.quizzes.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.quiz_outlined,
                                        color: AppTheme.textSecondary,
                                        size: 64),
                                    SizedBox(height: 16),
                                    Text(
                                      'Nenhum quiz importado.\nImporte um arquivo XML do Moodle.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 14),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: Responsive.horizontalPadding(context)
                                    .add(const EdgeInsets.only(bottom: 24)),
                                itemCount: prof.quizzes.length,
                                itemBuilder: (_, i) {
                                  final quiz = prof.quizzes[i];
                                  return _QuizCard(
                                    quiz: quiz,
                                    onSelect: () =>
                                        _selectQuiz(prof, quiz),
                                    onDelete: () =>
                                        _deleteQuiz(prof, quiz),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuizCard extends StatelessWidget {
  final LocalQuizEntity quiz;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  const _QuizCard({
    required this.quiz,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.cardDecoration(),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.quiz_rounded,
              color: Colors.white, size: 22),
        ),
        title: Text(quiz.name,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${quiz.totalQuestions} questão(ões)',
          style:
              const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppTheme.danger, size: 20),
              onPressed: onDelete,
              tooltip: 'Excluir',
            ),
            ElevatedButton(
              onPressed: onSelect,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Usar'),
            ),
          ],
        ),
        onTap: onSelect,
      ),
    );
  }
}
