import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../domain/entities/score_entity.dart';
import '../../controllers/professor_controller.dart';

/// Tela de ranking – altamente visual, animada e responsiva.
class RankingPage extends StatelessWidget {
  const RankingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfessorController>(
      builder: (context, prof, _) {
        final scores = prof.scores;

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
            child: SafeArea(
              child: Column(
                children: [
                  _RankingAppBar(
                      title: prof.quizState.quizTitle,
                      questionNum: prof.quizState.currentPage >= 0
                          ? prof.quizState.currentPage + 1
                          : 0,
                      total: prof.quizState.totalPages),
                  Expanded(
                    child: scores.isEmpty
                        ? const _EmptyRanking()
                        : _RankingContent(scores: scores),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── AppBar ─────────────────────────────────────────────────────────────────────

class _RankingAppBar extends StatelessWidget {
  final String title;
  final int questionNum;
  final int total;

  const _RankingAppBar({
    required this.title,
    required this.questionNum,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppTheme.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          // Trofeu animado
          const Icon(Icons.emoji_events_rounded, color: AppTheme.gold, size: 28)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .shimmer(duration: 2000.ms, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ranking',
                  style: GoogleFonts.nunito(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (questionNum > 0)
                  Text(
                    'Após questão $questionNum${total > 0 ? ' de $total' : ''}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          // Badge de participantes
          Consumer<ProfessorController>(
            builder: (_, prof, __) => _StatBadge(
              icon: Icons.people_alt_rounded,
              value: '${prof.scores.length}',
              label: 'alunos',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatBadge(
      {required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.accent, size: 16),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
              Text(label,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Conteúdo principal ─────────────────────────────────────────────────────────

class _RankingContent extends StatelessWidget {
  final List<ScoreEntity> scores;
  const _RankingContent({required this.scores});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return isMobile
        ? _MobileRanking(scores: scores)
        : _DesktopRanking(scores: scores);
  }
}

// ── Desktop: pódio à esquerda + lista à direita ────────────────────────────────

class _DesktopRanking extends StatelessWidget {
  final List<ScoreEntity> scores;
  const _DesktopRanking({required this.scores});

  @override
  Widget build(BuildContext context) {
    final top3 = scores.take(3).toList();
    final rest = scores.skip(3).toList();

    // Quando não há lista (< 4 participantes), centraliza o pódio
    if (rest.isEmpty) {
      return Center(child: _PodiumSection(top3: top3));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pódio
        SizedBox(
          width: 380,
          child: _PodiumSection(top3: top3),
        ),
        // Lista
        Expanded(
          child: _ScoreList(scores: rest, startRank: 4),
        ),
      ],
    );
  }
}

// ── Mobile: pódio no topo + lista abaixo ─────────────────────────────────────

class _MobileRanking extends StatelessWidget {
  final List<ScoreEntity> scores;
  const _MobileRanking({required this.scores});

  @override
  Widget build(BuildContext context) {
    final top3 = scores.take(3).toList();
    final rest = scores.skip(3).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _PodiumSection(top3: top3),
        ),
        if (rest.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _ScoreRow(score: rest[i], rank: i + 4),
                childCount: rest.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Pódio ──────────────────────────────────────────────────────────────────────

class _PodiumSection extends StatelessWidget {
  final List<ScoreEntity> top3;
  const _PodiumSection({required this.top3});

  @override
  Widget build(BuildContext context) {
    // Garantir 3 posições mesmo que não haja participantes suficientes
    final p1 = top3.isNotEmpty ? top3[0] : null;
    final p2 = top3.length > 1 ? top3[1] : null;
    final p3 = top3.length > 2 ? top3[2] : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          // Título da seção
          Text(
            '🏆  Pódio',
            style: GoogleFonts.nunito(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppTheme.gold,
            ),
          ).animate().fadeIn(delay: 100.ms),
          const SizedBox(height: 20),

          // Barras do pódio
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 2° lugar
              Expanded(
                child: _PodiumColumn(
                  player: p2,
                  rank: 2,
                  height: 140,
                  gradient: AppTheme.silverGradient,
                  rankColor: AppTheme.silver,
                  delay: 200.ms,
                ),
              ),
              // 1° lugar
              Expanded(
                child: _PodiumColumn(
                  player: p1,
                  rank: 1,
                  height: 180,
                  gradient: AppTheme.goldGradient,
                  rankColor: AppTheme.gold,
                  delay: 100.ms,
                  isCrown: true,
                ),
              ),
              // 3° lugar
              Expanded(
                child: _PodiumColumn(
                  player: p3,
                  rank: 3,
                  height: 110,
                  gradient: AppTheme.bronzeGradient,
                  rankColor: AppTheme.bronze,
                  delay: 300.ms,
                ),
              ),
            ],
          ),

          // Linha de base do pódio
          Container(
            height: 6,
            decoration: const BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _PodiumColumn extends StatelessWidget {
  final ScoreEntity? player;
  final int rank;
  final double height;
  final LinearGradient gradient;
  final Color rankColor;
  final Duration delay;
  final bool isCrown;

  const _PodiumColumn({
    required this.player,
    required this.rank,
    required this.height,
    required this.gradient,
    required this.rankColor,
    required this.delay,
    this.isCrown = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Avatar + nome ────────────────────────────────────────────
        if (player != null) ...[
          // Coroa para o 1°
          if (isCrown)
            const Text('👑', style: TextStyle(fontSize: 28))
                .animate(delay: delay + 400.ms)
                .fadeIn()
                .slideY(begin: -0.5),

          // Avatar
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: rankColor.withValues(alpha: 0.5),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Center(
              child: Text(
                player!.initials,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          )
              .animate(delay: delay)
              .scale(duration: 500.ms, curve: Curves.elasticOut),

          const SizedBox(height: 6),

          // Nome
          Text(
            player!.studentName.split(' ').first,
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ).animate(delay: delay + 100.ms).fadeIn(),

          const SizedBox(height: 4),

          // Pontuação
          Text(
            '${player!.score}',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: rankColor,
            ),
          ).animate(delay: delay + 200.ms).fadeIn(),

          // Acertos
          Text(
            '${player!.correctCount}/${player!.totalAnswered} ✓',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ).animate(delay: delay + 250.ms).fadeIn(),
        ] else
          SizedBox(height: isCrown ? 90 : 70),

        const SizedBox(height: 8),

        // ── Coluna do pódio ──────────────────────────────────────────
        Stack(
          alignment: Alignment.topCenter,
          children: [
            Container(
              height: height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    gradient.colors.first.withValues(alpha: 0.9),
                    gradient.colors.last.withValues(alpha: 0.6),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: rankColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  )
                ],
              ),
            ).animate(delay: delay).slideY(
                begin: 1.0, duration: 600.ms, curve: Curves.easeOutBack),
            // Número do rank
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '#$rank',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Lista de posições ─────────────────────────────────────────────────────────

class _ScoreList extends StatelessWidget {
  final List<ScoreEntity> scores;
  final int startRank;

  const _ScoreList({required this.scores, required this.startRank});

  @override
  Widget build(BuildContext context) {
    if (scores.isEmpty) {
      return const Center(
        child: Text('Apenas os 3 primeiros!',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: scores.length,
      itemBuilder: (_, i) => _ScoreRow(score: scores[i], rank: startRank + i),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final ScoreEntity score;
  final int rank;

  const _ScoreRow({required this.score, required this.rank});

  @override
  Widget build(BuildContext context) {
    // Cor da barra de pontuação baseada na posição
    final barColor = rank <= 5
        ? AppTheme.primary
        : rank <= 10
            ? AppTheme.accent
            : AppTheme.textSecondary;

    // Indicador de movimento no ranking
    Widget? movementIndicator;
    if (score.movedUp) {
      movementIndicator = const Icon(Icons.arrow_upward_rounded,
          color: AppTheme.success, size: 16);
    } else if (score.movedDown) {
      movementIndicator = const Icon(Icons.arrow_downward_rounded,
          color: AppTheme.danger, size: 16);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.bgCardAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$rank',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Avatar
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                score.initials,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Nome + barra de progresso
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  score.studentName,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(
                              begin: 0,
                              end: score.totalAnswered > 0
                                  ? score.correctCount / score.totalAnswered
                                  : 0),
                          duration: const Duration(milliseconds: 800),
                          builder: (_, val, __) => LinearProgressIndicator(
                            value: val,
                            backgroundColor: AppTheme.bgCardAlt,
                            valueColor: AlwaysStoppedAnimation<Color>(barColor),
                            minHeight: 5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${score.correctCount}/${score.totalAnswered}',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Pontuação
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: score.score),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOut,
                builder: (_, val, __) => Text(
                  '$val',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: barColor,
                  ),
                ),
              ),
              const Text('pts',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
            ],
          ),

          // Seta de movimento
          if (movementIndicator != null) ...[
            const SizedBox(width: 6),
            movementIndicator,
          ],
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: (rank - 4) * 60))
        .fadeIn()
        .slideX(begin: 0.1, duration: 350.ms);
  }
}

// ── Estado vazio ───────────────────────────────────────────────────────────────

class _EmptyRanking extends StatelessWidget {
  const _EmptyRanking();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.leaderboard_outlined,
                  color: AppTheme.textSecondary, size: 64)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fadeIn(duration: 1000.ms),
          const SizedBox(height: 16),
          const Text(
            'Nenhuma pontuação ainda.',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Libere uma questão para começar.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
