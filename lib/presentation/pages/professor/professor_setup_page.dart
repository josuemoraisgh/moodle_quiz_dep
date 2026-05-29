import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/file_import_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/entities/app_settings_entity.dart';
import '../../../domain/entities/student_entity.dart';
import '../../controllers/auth_controller.dart';

/// Tela de configuração inicial do professor.
/// Acessível diretamente da LoginPage mesmo sem senha definida.
class ProfessorSetupPage extends StatefulWidget {
  const ProfessorSetupPage({super.key});

  @override
  State<ProfessorSetupPage> createState() => _ProfessorSetupPageState();
}

class _ProfessorSetupPageState extends State<ProfessorSetupPage> {
  final FileImportService _fileImportService = createFileImportService();
  final _teacherPassCtrl = TextEditingController();
  final _studentPassCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _studentNameCtrl = TextEditingController();

  List<StudentEntity> _students = [];
  bool _saving = false;
  String? _error;
  bool _obscureTeacher = true;
  bool _obscureStudent = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    await auth.init();
    if (!mounted) return;
    final s = auth.settings;
    _teacherPassCtrl.text = s.teacherPassword;
    _studentPassCtrl.text = s.studentPassword;
    _titleCtrl.text = s.quizTitle;
    _students = List.from(auth.students);
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final auth = context.read<AuthController>();
    if (auth.needsTeacherPassword && _teacherPassCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Informe a senha do professor.');
      return;
    }
    if (auth.needsStudentPassword && _studentPassCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Informe a senha dos alunos.');
      return;
    }
    if (auth.needsStudents && _students.isEmpty) {
      setState(() => _error = 'Informe ao menos um aluno.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final current = auth.settings;
      final resolvedTitle = _titleCtrl.text.trim().isEmpty
          ? current.quizTitle
          : _titleCtrl.text.trim();
      await auth.saveSettings(AppSettingsEntity(
        teacherPassword: _teacherPassCtrl.text.trim().isEmpty
            ? current.teacherPassword
            : _teacherPassCtrl.text.trim(),
        studentPassword: _studentPassCtrl.text.trim().isEmpty
            ? current.studentPassword
            : _studentPassCtrl.text.trim(),
        quizTitle: resolvedTitle.isEmpty ? 'Quiz Presencial' : resolvedTitle,
        defaultDurationSeconds: current.defaultDurationSeconds,
        durationOptions: current.durationOptions,
      ));
      if (auth.needsStudents) {
        await auth.saveStudents(_students.map((s) => s.name).toList());
      }
      if (mounted) context.go(AppRouter.login);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _importStudents() async {
    final imported = await _fileImportService.pickTextFile(
      allowedExtensions: const ['txt', 'csv'],
      dialogTitle: 'Importar alunos',
    );
    if (!mounted) return;
    if (imported != null) {
      _appendStudentsFromRaw(imported.content);
      return;
    }

    if (_fileImportService.supportsNativePicker) {
      return;
    }

    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text(
          'Importar alunos',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          minLines: 8,
          maxLines: 16,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText:
                'Cole nomes separados por linha, virgula ou ponto e virgula',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (raw == null || raw.trim().isEmpty) return;

    _appendStudentsFromRaw(raw);
  }

  void _appendStudentsFromRaw(String raw) {
    final lines = raw
        .split(RegExp(r'[\n,;]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    setState(() {
      for (final name in lines) {
        if (!_students.any((s) => s.name == name)) {
          _students.add(StudentEntity(id: _students.length + 1, name: name));
        }
      }
    });
  }

  void _addStudent() {
    final name = _studentNameCtrl.text.trim();
    if (name.isEmpty) return;
    if (_students.any((s) => s.name == name)) {
      _studentNameCtrl.clear();
      return;
    }
    setState(() {
      _students.add(StudentEntity(id: _students.length + 1, name: name));
      _studentNameCtrl.clear();
    });
  }

  void _removeStudent(int index) => setState(() => _students.removeAt(index));

  @override
  void dispose() {
    _teacherPassCtrl.dispose();
    _studentPassCtrl.dispose();
    _titleCtrl.dispose();
    _studentNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
        child: SafeArea(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: Responsive.horizontalPadding(context).add(
                    const EdgeInsets.symmetric(vertical: 24),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Cabeçalho ──────────────────────────────────
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    color: AppTheme.textSecondary),
                                onPressed: () => context.go(AppRouter.login),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text('Configuração Inicial',
                                    style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          Consumer<AuthController>(
                            builder: (context, auth, _) {
                              final needsTitle = auth.needsQuizTitle;
                              final needsTeacherPass =
                                  auth.needsTeacherPassword;
                              final needsStudentPass =
                                  auth.needsStudentPassword;
                              final needsStudents = auth.needsStudents;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (needsTitle) ...[
                                    _SectionCard(
                                      title: 'Nome do Quiz',
                                      icon: Icons.quiz_rounded,
                                      child: TextFormField(
                                        controller: _titleCtrl,
                                        style: const TextStyle(
                                            color: AppTheme.textPrimary),
                                        decoration: const InputDecoration(
                                          labelText: 'Título exibido na tela',
                                          hintText: 'Quiz Presencial',
                                          hintStyle: TextStyle(
                                              color: AppTheme.textSecondary),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (needsTeacherPass || needsStudentPass) ...[
                                    _SectionCard(
                                      title: 'Senhas de Acesso',
                                      icon: Icons.lock_outline,
                                      child: Column(
                                        children: [
                                          if (needsTeacherPass) ...[
                                            TextFormField(
                                              controller: _teacherPassCtrl,
                                              obscureText: _obscureTeacher,
                                              style: const TextStyle(
                                                  color: AppTheme.textPrimary),
                                              decoration: InputDecoration(
                                                labelText: 'Senha do professor',
                                                prefixIcon: const Icon(Icons
                                                    .admin_panel_settings_outlined),
                                                suffixIcon: IconButton(
                                                  icon: Icon(_obscureTeacher
                                                      ? Icons.visibility_off
                                                      : Icons.visibility),
                                                  onPressed: () => setState(
                                                      () => _obscureTeacher =
                                                          !_obscureTeacher),
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (needsTeacherPass &&
                                              needsStudentPass)
                                            const SizedBox(height: 12),
                                          if (needsStudentPass)
                                            TextFormField(
                                              controller: _studentPassCtrl,
                                              obscureText: _obscureStudent,
                                              style: const TextStyle(
                                                  color: AppTheme.textPrimary),
                                              decoration: InputDecoration(
                                                labelText:
                                                    'Senha dos alunos (única)',
                                                prefixIcon: const Icon(
                                                    Icons.group_outlined),
                                                suffixIcon: IconButton(
                                                  icon: Icon(_obscureStudent
                                                      ? Icons.visibility_off
                                                      : Icons.visibility),
                                                  onPressed: () => setState(
                                                      () => _obscureStudent =
                                                          !_obscureStudent),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (needsStudents) ...[
                                    _SectionCard(
                                      title:
                                          'Lista de Alunos (${_students.length})',
                                      icon: Icons.people_outline,
                                      trailing: TextButton.icon(
                                        onPressed: _importStudents,
                                        icon: const Icon(Icons.upload_file,
                                            size: 16),
                                        label: const Text(
                                            'Importar arquivo/texto'),
                                        style: TextButton.styleFrom(
                                            foregroundColor: AppTheme.accent),
                                      ),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextFormField(
                                                  controller: _studentNameCtrl,
                                                  style: const TextStyle(
                                                      color:
                                                          AppTheme.textPrimary),
                                                  decoration:
                                                      const InputDecoration(
                                                    labelText: 'Nome do aluno',
                                                    hintText: 'Ex: Maria Silva',
                                                    hintStyle: TextStyle(
                                                        color: AppTheme
                                                            .textSecondary),
                                                  ),
                                                  onFieldSubmitted: (_) =>
                                                      _addStudent(),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                onPressed: _addStudent,
                                                icon: const Icon(
                                                    Icons.add_circle,
                                                    color: AppTheme.success,
                                                    size: 32),
                                                tooltip: 'Adicionar aluno',
                                              ),
                                            ],
                                          ),
                                          if (_students.isNotEmpty) ...[
                                            const SizedBox(height: 12),
                                            ListView.builder(
                                              shrinkWrap: true,
                                              physics:
                                                  const NeverScrollableScrollPhysics(),
                                              itemCount: _students.length,
                                              itemBuilder: (_, i) => ListTile(
                                                dense: true,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 4),
                                                leading: CircleAvatar(
                                                  backgroundColor: AppTheme
                                                      .primary
                                                      .withValues(alpha: 0.15),
                                                  child: Text(
                                                    '${i + 1}',
                                                    style: const TextStyle(
                                                        color: AppTheme.primary,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 13),
                                                  ),
                                                ),
                                                title: Text(_students[i].name,
                                                    style: const TextStyle(
                                                        color: AppTheme
                                                            .textPrimary,
                                                        fontSize: 14)),
                                                trailing: IconButton(
                                                  icon: const Icon(
                                                      Icons.delete_outline,
                                                      color: AppTheme.danger,
                                                      size: 20),
                                                  onPressed: () =>
                                                      _removeStudent(i),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                ],
                              );
                            },
                          ),

                          if (_error != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: AppTheme.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color:
                                        AppTheme.danger.withValues(alpha: 0.4)),
                              ),
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: AppTheme.danger, fontSize: 13)),
                            ),

                          ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.save_rounded),
                            label: const Text('Salvar e continuar'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 52),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
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

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
