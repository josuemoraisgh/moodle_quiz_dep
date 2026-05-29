import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/entities/moodle_quiz.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/professor_controller.dart';

class QuizSelectionPage extends StatelessWidget {
  const QuizSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: Responsive.contentWidth(context)),
              child: Padding(
                padding: Responsive.horizontalPadding(context)
                    .add(const EdgeInsets.symmetric(vertical: 24)),
                child: Consumer<ProfessorController>(
                  builder: (_, ctrl, __) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(courseName: ctrl.selectedCourse?.fullname ?? ''),
                      const SizedBox(height: 24),
                      if (ctrl.error != null) _ErrorCard(ctrl.error!),
                      if (ctrl.isLoading)
                        const Expanded(
                            child: Center(child: CircularProgressIndicator()))
                      else
                        Expanded(child: _QuizList(quizzes: ctrl.quizzes)),
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

class _Header extends StatelessWidget {
  final String courseName;
  const _Header({required this.courseName});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => context.go(AppRouter.professorCourses),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: AppTheme.cardDecoration(
              gradient: AppTheme.primaryGradient, glowing: true),
          child: const Icon(Icons.quiz, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Selecionar Questionário', style: AppTheme.headlineMedium),
              if (courseName.isNotEmpty)
                Text(courseName,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.upload_file_rounded,
              color: AppTheme.textSecondary),
          tooltip: 'Carregar questionario de XML',
          onPressed: () => _importXmlQuiz(context),
        ),
      ],
    );
  }
}

Future<void> _importXmlQuiz(BuildContext context) async {
  final user = context.read<AuthController>().user;
  if (user == null) return;
  final controller = context.read<ProfessorController>();
  final router = GoRouter.of(context);
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xml'],
    withData: true,
  );
  if (!context.mounted) return;
  final file = picked?.files.single;
  final bytes = file?.bytes;
  if (file == null || bytes == null) return;

  await controller.selectQuizFromXml(
    user,
    bytes: bytes,
    fileName: file.name,
  );
  if (context.mounted) router.go(AppRouter.professor);
}

class _QuizList extends StatelessWidget {
  final List<MoodleQuiz> quizzes;
  const _QuizList({required this.quizzes});

  @override
  Widget build(BuildContext context) {
    if (quizzes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz_outlined, size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text('Nenhum questionário nesta disciplina',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          ],
        ),
      );
    }

    final compatible = quizzes.where((q) => q.isCompatible).toList();
    final incompatible = quizzes.where((q) => !q.isCompatible).toList();

    return ListView(
      children: [
        if (compatible.isNotEmpty) ...[
          ...compatible.map((q) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _QuizTile(quiz: q),
              )),
        ],
        if (incompatible.isNotEmpty) ...[
          if (compatible.isNotEmpty) const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: AppTheme.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Questionários incompatíveis (configuração necessária no Moodle):',
                    style: TextStyle(
                        color: AppTheme.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...incompatible.map((q) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _QuizTile(quiz: q),
              )),
        ],
      ],
    );
  }
}

class _QuizTile extends StatelessWidget {
  final MoodleQuiz quiz;
  const _QuizTile({required this.quiz});

  @override
  Widget build(BuildContext context) {
    final timeLabel = quiz.timeLimit != null
        ? '${(quiz.timeLimit! ~/ 60)} min'
        : 'Sem limite';
    final compatible = quiz.isCompatible;
    final reasons = quiz.incompatibilityReasons;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: compatible
            ? () async {
                final user = context.read<AuthController>().user;
                if (user == null) return;
                final router = GoRouter.of(context);
                await context
                    .read<ProfessorController>()
                    .selectQuiz(user, quiz);
                router.go(AppRouter.professor);
              }
            : () => _showIncompatibleDialog(context, reasons),
        child: Opacity(
          opacity: compatible ? 1.0 : 0.5,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration(),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: compatible
                        ? AppTheme.primaryGradient
                        : const LinearGradient(
                            colors: [Color(0xFF555555), Color(0xFF444444)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    compatible ? Icons.quiz : Icons.block,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(quiz.name,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined,
                              size: 14, color: AppTheme.textSecondary),
                          const SizedBox(width: 4),
                          Text(timeLabel,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 12)),
                          const SizedBox(width: 16),
                          const Icon(Icons.repeat,
                              size: 14, color: AppTheme.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                              quiz.attempts == 0
                                  ? 'Ilimitadas'
                                  : '${quiz.attempts} tent.',
                              style: const TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 12)),
                        ],
                      ),
                      if (!compatible) ...[
                        const SizedBox(height: 6),
                        ...reasons.map((r) => Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    size: 12, color: AppTheme.warning),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(r,
                                      style: TextStyle(
                                          color: AppTheme.warning,
                                          fontSize: 11)),
                                ),
                              ],
                            )),
                      ],
                    ],
                  ),
                ),
                Icon(
                  compatible ? Icons.chevron_right : Icons.info_outline,
                  color: compatible ? AppTheme.textSecondary : AppTheme.warning,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showIncompatibleDialog(BuildContext context, List<String> reasons) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Questionário Incompatível',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Este questionário precisa de ajustes no Moodle para funcionar com o MoodleQuiz Live:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            ...reasons.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style:
                              TextStyle(color: AppTheme.warning, fontSize: 13)),
                      Expanded(
                        child: Text(r,
                            style: const TextStyle(
                                color: AppTheme.textPrimary, fontSize: 13)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.cardDecoration(
          color: AppTheme.danger.withValues(alpha: 0.2)),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style:
                      const TextStyle(color: AppTheme.danger, fontSize: 13))),
        ],
      ),
    );
  }
}
