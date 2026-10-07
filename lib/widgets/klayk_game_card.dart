import 'package:flutter/material.dart';

import '../screens/games/engines/engine_common.dart';
import '../services/game_service.dart';
import '../theme/klayk_theme.dart';
import 'klayk_ux.dart';

/// Card de jogo compacto do KLAY K (aba Jogos e área Jogos da Home).
///
/// Identidade preto/grafite + roxo neon: emoji em tile gradiente com a cor da
/// engine, nome, categoria + dificuldade (⭐⭐⭐), recorde pessoal e botão
/// JOGAR. Recompensa real lida das `rules` do backend (apenas informativa).
class KlaykGameCard extends StatelessWidget {
  const KlaykGameCard({
    super.key,
    required this.game,
    this.best = 0,
    this.onPlay,
    this.onRanking,
  });

  final GameInfo game;
  final int best;
  final VoidCallback? onPlay;
  final VoidCallback? onRanking;

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final g = game;
    final tint = engineColor(g, fallback: colors.primary);
    final rewardText = _rewardHint(g);
    return KlaykCard(
      onTap: g.isActive ? onPlay : null,
      padding: const EdgeInsets.all(12),
      borderColor: g.isActive
          ? colors.border
          : colors.border.withValues(alpha: 0.5),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tint.withValues(alpha: 0.35), colors.surfaceAlt],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tint.withValues(alpha: 0.55)),
              boxShadow: [
                BoxShadow(color: tint.withValues(alpha: 0.3), blurRadius: 12),
              ],
            ),
            child: Center(
              child: Text(g.emoji, style: const TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        g.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (g.isSoon) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'em breve',
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  g.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Colors.white54),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _pill(
                      colors,
                      Icons.category_rounded,
                      _categoryLabel(g.category),
                    ),
                    _pill(
                      colors,
                      Icons.star_rounded,
                      'Dificuldade ${'⭐' * g.difficulty}',
                      tint,
                    ),
                    if (best > 0)
                      _pill(
                        colors,
                        Icons.emoji_events_rounded,
                        'Recorde $best',
                        colors.warning,
                      ),
                  ],
                ),
                if (rewardText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    rewardText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: tint.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            children: [
              if (g.isActive && onPlay != null)
                FilledButton(
                  onPressed: onPlay,
                  style: FilledButton.styleFrom(
                    backgroundColor: tint,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    minimumSize: const Size(0, 38),
                    elevation: 0,
                    shadowColor: tint,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'JOGAR',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                )
              else
                const SizedBox(height: 20),
              if (g.isActive && onRanking != null)
                TextButton.icon(
                  onPressed: onRanking,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(20, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(
                    Icons.leaderboard_rounded,
                    size: 13,
                    color: colors.primarySoft,
                  ),
                  label: Text(
                    'Ranking',
                    style: TextStyle(fontSize: 10, color: colors.primarySoft),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(KlaykColors colors, IconData icon, String text, [Color? color]) {
    final c = color ?? Colors.white60;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: c),
          const SizedBox(width: 3),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(String category) {
    const labels = {
      'trivia': 'Trivia',
      'reflexo': 'Reflexo',
      'memoria': 'Memória',
      'matematica': 'Matemática',
      'palavras': 'Palavras',
      'arcade': 'Arcade',
      'estrategia': 'Estratégia',
      'esportes': 'Esportes',
      'musica': 'Música',
      'corrida': 'Corrida',
      'construcao': 'Construção',
      'aventura': 'Aventura',
      'cartas': 'Cartas',
      'quebra-cabeca': 'Quebra-cabeça',
    };
    return labels[category] ?? category;
  }

  /// Resumo das recompensas declaradas nas `rules` do jogo (backend).
  String _rewardHint(GameInfo g) {
    final rewards = g.rules['rewards'];
    if (rewards is! List || rewards.isEmpty) return '';
    final entries = rewards
        .map((r) {
          if (r is Map) {
            final min = (r['min_score'] as num?)?.toInt() ?? 0;
            final crystals = (r['crystals'] as num?)?.toInt() ?? 0;
            return '$min+ → $crystals🔮';
          }
          return '';
        })
        .where((s) => s.isNotEmpty)
        .toList();
    return entries.isEmpty ? '' : 'Recompensas: ${entries.join('  •  ')}';
  }
}
