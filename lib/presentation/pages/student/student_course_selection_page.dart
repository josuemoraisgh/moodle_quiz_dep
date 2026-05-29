import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/entities/moodle_course.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/student_controller.dart';

/// Tela de seleção de disciplina do estudante.
/// Após selecionar, verifica se existe mq_state no curso antes de entrar.
class StudentCourseSelectionPage extends StatefulWidget {
  const StudentCourseSelectionPage({super.key});

  @override
  State<StudentCourseSelectionPage> createState() =>
      _StudentCourseSelectionPageState();
}

class _StudentCourseSelectionPageState
    extends State<StudentCourseSelectionPage> {
  // Guarda qual courseId está sendo verificado para mostrar o spinner inline
  int? _checkingCourseId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCourses());
  }

  Future<void> _loadCourses() async {
    final user = context.read<AuthController>().user;
    if (user == null) return;
    await context.read<StudentController>().loadCourses(user);
  }

  Future<void> _onSelectCourse(MoodleCourse course) async {
    final user = context.read<AuthController>().user;
    if (user == null) return;

    setState(() => _checkingCourseId = course.id);

    final student = context.read<StudentController>();

    // Inicia verificação — o controller notificará hasActivity quando pronto
    student.selectCourse(user, course.id);

    // Aguarda o resultado da verificação
    await _waitForActivity(student);

    if (!mounted) return;
    setState(() => _checkingCourseId = null);

    if (student.hasActivity == true) {
      context.go(AppRouter.studentLobby);
    } else if (student.hasActivity == false) {
      _showNoActivitySnackbar(course.fullname);
    }
    // hasActivity == null → erro de rede → mensagem já está em student.error
  }

  Future<void> _waitForActivity(StudentController student) async {
    // Espera até hasActivity não ser mais null (máx 15 s)
    for (int i = 0; i < 150; i++) {
      if (student.hasActivity != null) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _showNoActivitySnackbar(String courseName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '"$courseName" não possui a atividade de quiz (mq_state).',
        ),
        backgroundColor: AppTheme.bgCardAlt,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

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
                child: Consumer2<StudentController, AuthController>(
                  builder: (_, student, auth, __) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(
                        fullname: auth.user!.fullname,
                        onLogout: () async {
                          student.stopPolling();
                          await auth.logout();
                          if (context.mounted) context.go(AppRouter.login);
                        },
                      ),
                      const SizedBox(height: 24),
                      if (student.error != null && student.hasActivity == null)
                        _ErrorCard(student.error!),
                      if (student.isLoadingCourses)
                        const Expanded(
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        Expanded(
                          child: _CourseList(
                            courses: student.courses,
                            checkingCourseId: _checkingCourseId,
                            onSelect: _onSelectCourse,
                          ),
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

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String fullname;
  final VoidCallback onLogout;
  const _Header({required this.fullname, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: AppTheme.cardDecoration(
              gradient: AppTheme.primaryGradient, glowing: true),
          child: const Icon(Icons.school, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Selecionar Disciplina', style: AppTheme.headlineMedium),
              Text(fullname,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: AppTheme.textSecondary),
          tooltip: 'Sair',
          onPressed: onLogout,
        ),
      ],
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _CourseList extends StatelessWidget {
  final List<MoodleCourse> courses;
  final int? checkingCourseId;
  final void Function(MoodleCourse) onSelect;

  const _CourseList({
    required this.courses,
    required this.checkingCourseId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: AppTheme.textSecondary),
            SizedBox(height: 16),
            Text('Nenhuma disciplina encontrada',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: courses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _CourseTile(
        course: courses[i],
        isChecking: checkingCourseId == courses[i].id,
        onTap: () => onSelect(courses[i]),
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  final MoodleCourse course;
  final bool isChecking;
  final VoidCallback onTap;

  const _CourseTile({
    required this.course,
    required this.isChecking,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isChecking ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.book_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  course.fullname,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              if (isChecking)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
