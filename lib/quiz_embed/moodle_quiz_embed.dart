import 'package:flutter/material.dart';

import '../../data/datasources/local_state_client.dart';
import '../../data/datasources/moodle_datasource.dart';
import '../../data/repositories/quiz_repository_impl.dart';
import '../../domain/entities/question_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../presentation/widgets/question_engine_widget.dart';
import 'quiz_embed_config.dart';

enum _Phase { loading, ready, submitting, done, error }

/// Embeds a single Moodle quiz question inline, without go_router or an
/// external Provider. Drop it anywhere in a widget tree.
///
/// Com [MoodleQuizConfig.stateServerUrl] preenchido, a pontuação é enviada ao
/// servidor local do professor (S23) e aparece no ranking ao vivo. O botão
/// "Resetar Quiz" do app do professor limpa os dados normalmente.
///
/// ```dart
/// MoodleQuizEmbed(
///   config: MoodleQuizConfig(
///     moodleUrl: 'https://moodle.ufu.br',
///     token: authToken,
///     userId: userId,
///     courseId: 42,
///     quizId: 7,
///     questionSlot: 1,
///     stateServerUrl: 'http://192.168.1.100:8080/api', // ranking ao vivo
///   ),
///   onAnswered: (correct, score) { ... },
/// )
/// ```
class MoodleQuizEmbed extends StatefulWidget {
  final MoodleQuizConfig config;

  /// Chamado após o aluno submeter a resposta.
  /// [score] = [MoodleQuizConfig.correctScore] se correto, 0 caso contrário.
  final void Function(bool correct, int score)? onAnswered;

  /// Mostrado enquanto autentica / carrega a questão.
  final Widget? loadingWidget;

  /// Constrói a UI de erro. [retry] re-executa toda a sequência de carregamento.
  final Widget Function(BuildContext ctx, Object error, VoidCallback retry)?
      errorBuilder;

  const MoodleQuizEmbed({
    super.key,
    required this.config,
    this.onAnswered,
    this.loadingWidget,
    this.errorBuilder,
  });

  @override
  State<MoodleQuizEmbed> createState() => _MoodleQuizEmbedState();
}

class _MoodleQuizEmbedState extends State<MoodleQuizEmbed> {
  // Recriado a cada _load() para suportar retry e config dinâmica.
  QuizRepositoryImpl? _repo;

  _Phase _phase = _Phase.loading;
  Object? _error;

  UserEntity? _user;
  int? _attemptId;
  QuestionEntity? _question;

  final Map<String, String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Carregamento ───────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _phase = _Phase.loading;
        _error = null;
        _selected.clear();
      });
    }

    try {
      final cfg = widget.config;
      final baseUrl = cfg.moodleUrl.replaceAll(RegExp(r'/+$'), '');

      // Recria datasources a cada load (suporta retry após erro de rede).
      final moodle = MoodleDatasource();
      final stateDs = LocalStateClient(serverUrl: cfg.stateServerUrl);
      final repo = QuizRepositoryImpl(stateDs, moodle);
      _repo = repo;

      // 1. Autenticar ──────────────────────────────────────────────────────────
      final UserEntity user;
      if (cfg.hasToken) {
        user = UserEntity(
          id: cfg.userId!,
          username: cfg.username ?? '',
          fullname: cfg.fullname ?? '',
          token: cfg.token!,
          baseUrl: baseUrl,
          isTeacher: false,
          availableFunctions: const {},
        );
      } else {
        final data =
            await moodle.login(baseUrl, cfg.loginUsername!, cfg.loginPassword!);
        user = UserEntity(
          id: (data['userId'] as num).toInt(),
          username: cfg.loginUsername!,
          fullname: data['fullname']?.toString() ?? cfg.loginUsername!,
          token: data['token'] as String,
          baseUrl: baseUrl,
          isTeacher: false,
          availableFunctions: Set<String>.from(
            (data['functions'] as List? ?? []).cast<String>(),
          ),
        );
      }
      _user = user;

      // 2. Iniciar / retomar tentativa ─────────────────────────────────────────
      final attemptId = await repo.startAttempt(user, cfg.quizId);
      _attemptId = attemptId;

      // 3. Carregar questão ────────────────────────────────────────────────────
      final question = await repo.getQuestion(user, attemptId, cfg.questionSlot);

      if (mounted) {
        setState(() {
          _question = question;
          _phase = _Phase.ready;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _phase = _Phase.error;
        });
      }
    }
  }

  // ── Submissão ──────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final user = _user;
    final attemptId = _attemptId;
    final question = _question;
    final repo = _repo;
    if (user == null || attemptId == null || question == null || repo == null) {
      return;
    }

    setState(() => _phase = _Phase.submitting);
    try {
      // Moodle avalia a resposta — requer internet.
      final correct =
          await repo.submitPage(user, attemptId, question, Map.of(_selected));

      final score = correct ? widget.config.correctScore : 0;

      // Envia pontuação ao servidor de estado (best-effort — não falha a UI).
      try {
        await repo.submitScore(
          user: user,
          courseId: widget.config.courseId,
          score: score,
          correct: correct,
          page: question.page,
        );
      } catch (_) {
        // Falha silenciosa: questão já foi avaliada, só o ranking não atualiza.
      }

      if (mounted) {
        setState(() => _phase = _Phase.done);
        widget.onAnswered?.call(correct, score);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _phase = _Phase.error;
        });
      }
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.loading:
        return widget.loadingWidget ??
            const Center(child: CircularProgressIndicator());

      case _Phase.error:
        final err = _error!;
        if (widget.errorBuilder != null) {
          return widget.errorBuilder!(context, err, _load);
        }
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Erro ao carregar questão:\n$err',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _load,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        );

      case _Phase.ready:
      case _Phase.submitting:
        return QuestionEngineWidget(
          question: _question!,
          mode: QuestionEngineMode.answer,
          selectedAnswers: Map.of(_selected),
          hasAnswered: false,
          isSubmitting: _phase == _Phase.submitting,
          showCorrect: false,
          onSelectAnswer: (name, value) =>
              setState(() => _selected[name] = value),
          onSubmit: _phase == _Phase.submitting ? null : _submit,
        );

      case _Phase.done:
        return QuestionEngineWidget(
          question: _question!,
          mode: QuestionEngineMode.reveal,
          selectedAnswers: Map.of(_selected),
          hasAnswered: true,
          isSubmitting: false,
          showCorrect: true,
        );
    }
  }
}

