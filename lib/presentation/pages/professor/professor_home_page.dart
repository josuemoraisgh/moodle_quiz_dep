import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/entities/question_entity.dart';
import '../../../domain/entities/quiz_state_entity.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/professor_controller.dart';
import '../../../core/utils/fullscreen_button.dart';
import '../../widgets/question_engine_widget.dart';
import '../../widgets/moodle_html_renderer.dart';
import '../../widgets/timer_widget.dart';

/// Painel do professor – controle de questões + status do quiz.
class ProfessorHomePage extends StatefulWidget {
  const ProfessorHomePage({super.key});

  @override
  State<ProfessorHomePage> createState() => _ProfessorHomePageState();
}

class _ProfessorHomePageState extends State<ProfessorHomePage> {
  int _questionIndex = 0; // índice da questão atualmente selecionada
  bool _showQuestionThumbnails = false;
  late ProfessorController _prof;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prof = context.read<ProfessorController>();
      if (mounted) {
        setState(() {
          _questionIndex = _prof.selectedQuestionIndex;
          _showQuestionThumbnails = _prof.showQuestionThumbnails;
        });
      }
      _prof.startPolling();
    });
  }

  /// Quando a questão passa de ativa → encerrada, avança automaticamente
  /// para a próxima questão na lista (se existir).
  void _selectQuestion(ProfessorController prof, int index) {
    if (index < 0 || index >= prof.questions.length) return;
    prof.setSelectedQuestionIndex(index);
    setState(() => _questionIndex = index);
    prof.logQuestionDiagnostics(prof.questions[index], index);
  }

  void _moveQuestion(ProfessorController prof, int delta) {
    if (prof.questions.isEmpty) return;
    final next = (_questionIndex + delta).clamp(0, prof.questions.length - 1);
    if (next == _questionIndex) return;
    _selectQuestion(prof, next);
  }

  @override
  void dispose() {
    _prof.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ProfessorController, AuthController>(
      builder: (context, prof, auth, _) {
        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _moveQuestion(prof, -1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _moveQuestion(prof, 1);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Scaffold(
          body: Container(
            decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
            child: SafeArea(
              child: Responsive.isDesktop(context)
                  ? _DesktopLayout(
                      prof: prof,
                      auth: auth,
                      questionIndex: _questionIndex,
                      showQuestionThumbnails: _showQuestionThumbnails,
                      onToggleQuestionThumbnails: () => setState(
                        () {
                          _showQuestionThumbnails = !_showQuestionThumbnails;
                          prof.setShowQuestionThumbnails(
                              _showQuestionThumbnails);
                        },
                      ),
                      onIndexChanged: (i) => _selectQuestion(prof, i),
                    )
                  : _MobileLayout(
                      prof: prof,
                      auth: auth,
                      questionIndex: _questionIndex,
                      onIndexChanged: (i) => _selectQuestion(prof, i),
                    ),
            ),
          ),
        ));
      },
    );
  }
}

// ── Desktop: side-by-side ─────────────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  final ProfessorController prof;
  final AuthController auth;
  final int questionIndex;
  final bool showQuestionThumbnails;
  final VoidCallback onToggleQuestionThumbnails;
  final void Function(int) onIndexChanged;

  const _DesktopLayout({
    required this.prof,
    required this.auth,
    required this.questionIndex,
    required this.showQuestionThumbnails,
    required this.onToggleQuestionThumbnails,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Painel lateral – lista de questões
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: showQuestionThumbnails ? 320 : 56,
          child: showQuestionThumbnails
              ? _QuestionListPanel(
                  questions: prof.questions,
                  selectedIndex: questionIndex,
                  quizState: prof.quizState,
                  onSelect: onIndexChanged,
                  onToggleVisibility: onToggleQuestionThumbnails,
                )
              : _CollapsedQuestionListHandle(
                  onShow: onToggleQuestionThumbnails,
                  questions: prof.questions,
                  selectedIndex: questionIndex,
                  quizState: prof.quizState,
                  onSelect: onIndexChanged,
                ),
        ),
        const VerticalDivider(width: 1, color: AppTheme.bgCard),
        // Painel principal – controles
        Expanded(
          child: _ControlPanel(
            prof: prof,
            auth: auth,
            selectedIndex: questionIndex,
            onIndexChanged: onIndexChanged,
          ),
        ),
      ],
    );
  }
}

// ── Mobile: abas ──────────────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  final ProfessorController prof;
  final AuthController auth;
  final int questionIndex;
  final void Function(int) onIndexChanged;

  const _MobileLayout({
    required this.prof,
    required this.auth,
    required this.questionIndex,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          _ProfessorAppBar(auth: auth, prof: prof),
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.list_alt), text: 'Questões'),
              Tab(icon: Icon(Icons.tune), text: 'Controle'),
            ],
            indicatorColor: AppTheme.primary,
            labelColor: AppTheme.textPrimary,
            unselectedLabelColor: AppTheme.textSecondary,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _QuestionListPanel(
                  questions: prof.questions,
                  selectedIndex: questionIndex,
                  quizState: prof.quizState,
                  onSelect: onIndexChanged,
                ),
                _ControlPanel(
                  prof: prof,
                  auth: auth,
                  selectedIndex: questionIndex,
                  onIndexChanged: onIndexChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── AppBar do professor ───────────────────────────────────────────────────────

class _ProfessorAppBar extends StatelessWidget {
  final AuthController auth;
  final ProfessorController prof;
  const _ProfessorAppBar({required this.auth, required this.prof});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppTheme.textSecondary, size: 20),
            tooltip: 'Voltar para seleção de questionário',
            onPressed: () {
              prof.stopPolling();
              context.go(AppRouter.professorQuiz);
            },
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.school_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              prof.quizState.quizTitle.isNotEmpty
                  ? prof.quizState.quizTitle
                  : (prof.selectedQuiz?.name ?? AppConfig.appName),
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const FullscreenButton(),
          IconButton(
            icon: const Icon(Icons.qr_code_2_rounded,
                color: AppTheme.textSecondary),
            tooltip: 'QR Code do Aluno',
            onPressed: () => context.go(AppRouter.professorQrCode),
          ),
          IconButton(
            icon: const Icon(Icons.fact_check_rounded, color: AppTheme.accent),
            tooltip: 'Mostrar Gabarito',
            onPressed: prof.questions.isEmpty
                ? null
                : () {
                    final index = prof.selectedQuestionIndex
                        .clamp(0, prof.questions.length - 1);
                    final question = prof.questions[index];
                    prof.setRevealQuestion(question);
                    context.push(AppRouter.professorReveal);
                  },
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded, color: AppTheme.accent),
            tooltip: 'Ver Ranking',
            onPressed: () => context.push(AppRouter.professorRank),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.textSecondary),
            tooltip: 'Sair',
            onPressed: () async {
              prof.stopPolling();
              await auth.logout();
              if (context.mounted) context.go(AppRouter.login);
            },
          ),
        ],
      ),
    );
  }
}

// ── Lista de questões ─────────────────────────────────────────────────────────

class _QuestionListPanel extends StatelessWidget {
  final List<QuestionEntity> questions;
  final int selectedIndex;
  final QuizStateEntity quizState;
  final void Function(int) onSelect;
  final VoidCallback? onToggleVisibility;

  const _QuestionListPanel({
    required this.questions,
    required this.selectedIndex,
    required this.quizState,
    required this.onSelect,
    this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Nenhuma questão disponível.\nConsulte o log de carregamento.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: questions.length + (onToggleVisibility == null ? 0 : 1),
      itemBuilder: (_, i) {
        if (onToggleVisibility != null && i == 0) {
          return _QuestionListHeader(
            questionCount: questions.length,
            onToggleVisibility: onToggleVisibility!,
          );
        }
        final questionOffset = onToggleVisibility == null ? i : i - 1;
        final q = questions[questionOffset];
        final isActive = quizState.currentPage == q.page && quizState.isActive;
        final isSelected = questionOffset == selectedIndex;

        return GestureDetector(
          onTap: () => onSelect(questionOffset),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: isActive ? AppTheme.primaryGradient : null,
              color: isActive
                  ? null
                  : (isSelected ? AppTheme.bgCard : AppTheme.bgCardAlt),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppTheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.2)
                        : AppTheme.bgDark,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${questionOffset + 1}',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w800,
                        color: isActive ? Colors.white : AppTheme.primary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    q.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isActive ? Colors.white : AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (isActive)
                  const Icon(Icons.play_circle_fill,
                      color: Colors.white, size: 18),
              ],
            ),
          )
              .animate(delay: Duration(milliseconds: questionOffset * 40))
              .fadeIn()
              .slideX(begin: -0.1, duration: 300.ms),
        );
      },
    );
  }
}

// ── Painel de controle ────────────────────────────────────────────────────────

class _QuestionListHeader extends StatelessWidget {
  final int questionCount;
  final VoidCallback onToggleVisibility;

  const _QuestionListHeader({
    required this.questionCount,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$questionCount questoes',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Tooltip(
            message: 'Ocultar miniaturas',
            child: IconButton(
              onPressed: onToggleVisibility,
              icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
              color: AppTheme.textSecondary,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedQuestionListHandle extends StatelessWidget {
  final VoidCallback onShow;
  final List<QuestionEntity> questions;
  final int selectedIndex;
  final QuizStateEntity quizState;
  final void Function(int) onSelect;

  const _CollapsedQuestionListHandle({
    required this.onShow,
    required this.questions,
    required this.selectedIndex,
    required this.quizState,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bgDark.withValues(alpha: 0.35),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Tooltip(
              message: 'Mostrar miniaturas',
              child: IconButton(
                onPressed: onShow,
                icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: questions.isEmpty
                ? Center(
                    child: Text(
                      '-',
                      style: GoogleFonts.poppins(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: questions.length,
                    itemBuilder: (context, index) {
                      final q = questions[index];
                      final isActive =
                          quizState.currentPage == q.page && quizState.isActive;
                      final isSelected = index == selectedIndex;
                      final color = isActive
                          ? AppTheme.success
                          : isSelected
                              ? AppTheme.primary
                              : AppTheme.textSecondary;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Tooltip(
                          message: 'Questão ${index + 1}',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => onSelect(index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: 38,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected || isActive
                                    ? color.withValues(alpha: 0.14)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected || isActive
                                      ? color.withValues(alpha: 0.75)
                                      : AppTheme.bgCardAlt,
                                ),
                              ),
                              child: Text(
                                '${index + 1}',
                                style: GoogleFonts.poppins(
                                  color: color,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Tooltip(
            message: 'Mostrar miniaturas',
            child: IconButton(
              onPressed: onShow,
              icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlPanel extends StatefulWidget {
  final ProfessorController prof;
  final AuthController auth;
  final int selectedIndex;
  final void Function(int) onIndexChanged;

  const _ControlPanel({
    required this.prof,
    required this.auth,
    required this.selectedIndex,
    required this.onIndexChanged,
  });

  @override
  State<_ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<_ControlPanel> {
  bool _showCorrectAnswer = false;
  bool _showFeedback = false;

  @override
  Widget build(BuildContext context) {
    final prof = widget.prof;
    final auth = widget.auth;
    final selectedIndex = widget.selectedIndex;
    final state = prof.quizState;
    final questions = prof.questions;
    final hasQuestions = questions.isNotEmpty;
    final selectedQ = hasQuestions && selectedIndex < questions.length
        ? questions[selectedIndex]
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfessorTopSection(
            prof: prof,
            auth: auth,
            state: state,
            scores: prof.scores,
          ),
          const SizedBox(height: 16),

          // ── Questão selecionada ──────────────────────────────────────
          if (selectedQ != null) ...[
            _SelectedQuestionCard(
              question: selectedQ,
              index: selectedIndex,
              showCorrect: _showCorrectAnswer,
              showFeedback: _showFeedback,
              onPrevious: selectedIndex > 0
                  ? () => widget.onIndexChanged(selectedIndex - 1)
                  : null,
              onNext: selectedIndex < questions.length - 1
                  ? () => widget.onIndexChanged(selectedIndex + 1)
                  : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _showCorrectAnswer,
                    onChanged: (v) =>
                        setState(() => _showCorrectAnswer = v ?? false),
                    activeColor: AppTheme.success,
                    side: const BorderSide(color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () =>
                      setState(() => _showCorrectAnswer = !_showCorrectAnswer),
                  child: const Text(
                    'Mostrar resposta correta',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: selectedQ.generalFeedback.trim().isEmpty
                      ? null
                      : () => setState(() => _showFeedback = !_showFeedback),
                  icon: Icon(
                    _showFeedback
                        ? Icons.visibility_off_rounded
                        : Icons.feedback_rounded,
                    size: 16,
                  ),
                  label: Text(_showFeedback ? 'Ocultar feedback' : 'Feedback'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _showFeedback
                        ? AppTheme.warning
                        : AppTheme.textSecondary,
                    side: BorderSide(
                      color: _showFeedback
                          ? AppTheme.warning
                          : AppTheme.textSecondary,
                    ),
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ── Botões de ação ───────────────────────────────────────────
          if (state.isActive)
            _ActionButton(
              label: 'Encerrar Questão',
              icon: Icons.stop_circle_rounded,
              color: AppTheme.danger,
              loading: prof.isLoading,
              onPressed: prof.stopQuestion,
            )
          else
            _ActionButton(
              label: selectedQ != null
                  ? 'Liberar Questão ${selectedIndex + 1}'
                  : 'Selecione uma questão',
              icon: Icons.play_circle_fill_rounded,
              color: AppTheme.success,
              loading: prof.isLoading,
              onPressed: (selectedQ != null && !prof.isLoading)
                  ? () => prof.releaseQuestion(selectedQ)
                  : null,
            ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: prof.isLoading
                      ? null
                      : () => prof.runConnectionDiagnostics(
                            question: selectedQ,
                            index: selectedIndex,
                          ),
                  icon: const Icon(Icons.wifi_tethering_rounded,
                      color: AppTheme.accent, size: 18),
                  label: const Text('Testar conexão/logs',
                      style: TextStyle(color: AppTheme.accent)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.accent),
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: selectedQ == null
                      ? null
                      : () => prof.logQuestionDiagnostics(
                            selectedQ,
                            selectedIndex,
                          ),
                  icon: const Icon(Icons.bug_report_rounded,
                      color: AppTheme.warning, size: 18),
                  label: const Text('Diagnosticar questão',
                      style: TextStyle(color: AppTheme.warning)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.warning),
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      prof.isLoading ? null : () => _confirmReset(context, prof),
                  icon: const Icon(Icons.refresh_rounded,
                      color: AppTheme.danger, size: 18),
                  label: const Text('Reiniciar Quiz',
                      style: TextStyle(color: AppTheme.danger)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.danger),
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Erro ─────────────────────────────────────────────────────
          if (prof.error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppTheme.danger.withValues(alpha: 0.4)),
              ),
              child: Text(prof.error!,
                  style: const TextStyle(color: AppTheme.danger, fontSize: 13)),
            ),
          ],

          // ── Log de carregamento — toggle com botão ──
          if (prof.log.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CollapsibleLogPanel(log: prof.log),
          ],

        ],
      ),
    );
  }

  Future<void> _confirmReset(
      BuildContext context, ProfessorController prof) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Reiniciar Quiz',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'Isso apaga todas as respostas e pontuações. Confirma?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );
    if (ok == true) await prof.resetQuiz();
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ProfessorTopSection extends StatelessWidget {
  final ProfessorController prof;
  final AuthController auth;
  final QuizStateEntity state;
  final List<dynamic> scores;

  const _ProfessorTopSection({
    required this.prof,
    required this.auth,
    required this.state,
    required this.scores,
  });

  @override
  Widget build(BuildContext context) {
    final controls = _TopControlsColumn(
      prof: prof,
      auth: auth,
      state: state,
      scores: scores,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide =
            Responsive.isDesktop(context) && constraints.maxWidth >= 760;

        if (!isWide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _CompactQrCard(),
              const SizedBox(height: 12),
              controls,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(flex: 7, child: _CompactQrCard()),
            const SizedBox(width: 16),
            Expanded(flex: 22, child: controls),
          ],
        );
      },
    );
  }
}

class _TopControlsColumn extends StatelessWidget {
  final ProfessorController prof;
  final AuthController auth;
  final QuizStateEntity state;
  final List<dynamic> scores;

  const _TopControlsColumn({
    required this.prof,
    required this.auth,
    required this.state,
    required this.scores,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (Responsive.isDesktop(context))
          _ProfessorAppBar(auth: auth, prof: prof),
        _StatusCard(state: state),
        const SizedBox(height: 16),
        if (state.isActive && state.isTimerPending) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: AppTheme.cardDecoration(),
            child: const Row(
              children: [
                Icon(Icons.hourglass_top_rounded,
                    color: AppTheme.warning, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Aguardando a primeira resposta para iniciar o cronômetro.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (state.isActive && state.endsAt != null) ...[
          TimerWidget(
            endsAt: state.endsAt!,
            onTimeUp: () => prof.stopQuestion(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: prof.isLoading ? null : () => prof.extendQuestion(15),
            icon: const Icon(Icons.add_alarm_rounded, color: AppTheme.accent),
            label: const Text('+15s', style: TextStyle(color: AppTheme.accent)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.accent),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
        ],
        _DurationSelector(
          value: prof.selectedDuration,
          onChange: prof.setDuration,
          enabled: !state.isActive,
        ),
        const SizedBox(height: 12),
        _StartTimerOption(
          value: prof.startTimerOnFirstResponse,
          enabled: !state.isActive,
          onChanged: prof.setStartTimerOnFirstResponse,
        ),
        if (scores.isNotEmpty) ...[
          const SizedBox(height: 16),
          _MiniRanking(scores: scores),
        ],
      ],
    );
  }
}

class _CompactQrCard extends StatelessWidget {
  const _CompactQrCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: Image.asset(
          'assets/qrcode.png',
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.qr_code_2_rounded,
            color: AppTheme.textSecondary,
            size: 96,
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final QuizStateEntity state;
  const _StatusCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state.status) {
      QuizStatus.active => (
          'Questão Ativa',
          AppTheme.success,
          Icons.play_circle_fill
        ),
      QuizStatus.closed => (
          'Questão Encerrada',
          AppTheme.warning,
          Icons.pause_circle_filled
        ),
      QuizStatus.finished => (
          'Quiz Finalizado',
          AppTheme.accent,
          Icons.emoji_events
        ),
      _ => ('Aguardando Início', AppTheme.textSecondary, Icons.hourglass_empty),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(glowing: state.isActive),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w700, fontSize: 15)),
              if (state.currentPage >= 0)
                Text(
                  'Questão ${state.currentPage + 1}'
                  '${state.totalPages > 0 ? ' / ${state.totalPages}' : ''}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                ),
            ],
          ),
          const Spacer(),
          if (state.isActive)
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                  color: AppTheme.success, shape: BoxShape.circle),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(end: 0.5, duration: 600.ms),
        ],
      ),
    );
  }
}

class _DurationSelector extends StatelessWidget {
  final int value;
  final void Function(int) onChange;
  final bool enabled;

  const _DurationSelector({
    required this.value,
    required this.onChange,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final options = AppConfig.questionTimeOptions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tempo por questão',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((sec) {
            final selected = sec == value;
            return GestureDetector(
              onTap: enabled ? () => onChange(sec) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: selected ? AppTheme.primaryGradient : null,
                  color: selected ? null : AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? AppTheme.primary : AppTheme.bgCardAlt,
                  ),
                ),
                child: Text(
                  '${sec}s',
                  style: TextStyle(
                    color: selected ? Colors.white : AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _SelectedQuestionCard extends StatefulWidget {
  final QuestionEntity question;
  final int index;
  final bool showCorrect;
  final bool showFeedback;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  const _SelectedQuestionCard({
    required this.question,
    required this.index,
    this.showCorrect = false,
    this.showFeedback = false,
    this.onPrevious,
    this.onNext,
  });

  @override
  State<_SelectedQuestionCard> createState() => _SelectedQuestionCardState();
}

class _SelectedQuestionCardState extends State<_SelectedQuestionCard> {
  bool _expanded = false;
  final Map<String, String> _selectedAnswers = {};

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    final previewText = _questionPreviewText(question);

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
      padding: const EdgeInsets.fromLTRB(52, 16, 52, 16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Questão ${widget.index + 1}',
                    style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
              IconButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                tooltip:
                    _expanded ? 'Recolher enunciado' : 'Expandir enunciado',
                icon: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: AnimatedCrossFade(
              firstChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    previewText,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
              secondChild: widget.showFeedback
                  ? _QuestionFeedbackView(question: question)
                  : QuestionEngineWidget(
                      question: question,
                      mode: QuestionEngineMode.preview,
                      showCorrect: widget.showCorrect,
                      compact: true,
                      selectedAnswers: _selectedAnswers,
                      onSelectAnswer: (name, value) =>
                          setState(() => _selectedAnswers[name] = value),
                    ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
              _expanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
              size: 18,
            ),
            label: Text(_expanded ? 'Recolher' : 'Expandir'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
        ),
        _QuestionNavArrow(
          alignment: Alignment.centerLeft,
          icon: Icons.chevron_left_rounded,
          tooltip: 'Questão anterior',
          onPressed: widget.onPrevious,
        ),
        _QuestionNavArrow(
          alignment: Alignment.centerRight,
          icon: Icons.chevron_right_rounded,
          tooltip: 'Próxima questão',
          onPressed: widget.onNext,
        ),
      ],
    );
  }

  String _questionPreviewText(QuestionEntity question) {
    if (question.htmlText.isNotEmpty) {
      final parsed = html_parser.parse(question.htmlText);
      final text = parsed.documentElement?.text ?? '';
      final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return question.text.trim();
  }
}

class _QuestionFeedbackView extends StatelessWidget {
  final QuestionEntity question;

  const _QuestionFeedbackView({required this.question});

  @override
  Widget build(BuildContext context) {
    final feedback = question.generalFeedback.trim();
    if (feedback.isEmpty) {
      return const Text(
        'Esta questão não possui feedback cadastrado.',
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: MoodleHtmlRenderer(
        html: feedback,
        textStyle: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }
}

class _QuestionNavArrow extends StatelessWidget {
  final Alignment alignment;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _QuestionNavArrow({
    required this.alignment,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Tooltip(
            message: tooltip,
            child: IconButton(
              onPressed: onPressed,
              icon: Icon(icon, size: 30),
              color: AppTheme.textSecondary,
              disabledColor: AppTheme.textSecondary.withValues(alpha: 0.25),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.bgDark.withValues(alpha: 0.45),
                disabledBackgroundColor:
                    AppTheme.bgDark.withValues(alpha: 0.18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartTimerOption extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _StartTimerOption({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: enabled ? (next) => onChanged(next ?? true) : null,
                side: const BorderSide(color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Começar tempo na 1ª resposta',
                    style: TextStyle(
                      color: enabled
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Marcado por padrão. A questão abre na hora, mas o cronômetro só inicia quando o primeiro aluno responder.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
          : Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _CollapsibleLogPanel extends StatefulWidget {
  final List<String> log;
  const _CollapsibleLogPanel({required this.log});

  @override
  State<_CollapsibleLogPanel> createState() => _CollapsibleLogPanelState();
}

class _CollapsibleLogPanelState extends State<_CollapsibleLogPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.bgDark,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.bgCard),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded,
                    color: AppTheme.accent, size: 14),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Log de carregamento/diagnóstico',
                      style: TextStyle(
                          color: AppTheme.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                if (_expanded)
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    color: AppTheme.textSecondary,
                    tooltip: 'Copiar log',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: widget.log.join('\n')));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Log copiado!'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                const SizedBox(width: 4),
                Text(
                  '${widget.log.length} linhas',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: AppTheme.accent,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) SizedBox(height: 220, child: _LogPanel(log: widget.log)),
      ],
    );
  }
}

class _LogPanel extends StatelessWidget {
  final List<String> log;
  const _LogPanel({required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.bgCard),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          log.join('\n'),
          style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontFamily: 'monospace'),
        ),
      ),
    );
  }
}

class _MiniRanking extends StatelessWidget {
  final List<dynamic> scores;
  const _MiniRanking({required this.scores});

  @override
  Widget build(BuildContext context) {
    final top5 = scores.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Top 5',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...top5.asMap().entries.map((e) {
          final s = e.value;
          final colors = [
            AppTheme.gold,
            AppTheme.silver,
            AppTheme.bronze,
            AppTheme.textSecondary,
            AppTheme.textSecondary,
          ];
          final rankColor = e.key < 3 ? colors[e.key] : AppTheme.textSecondary;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text('${e.key + 1}',
                      style: TextStyle(
                          color: rankColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                ),
                Expanded(
                  child: Text(
                    s.studentName,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${s.score} pts',
                  style: TextStyle(
                      color: rankColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
