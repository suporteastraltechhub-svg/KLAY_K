import 'package:flutter/material.dart';

import '../../services/game_service.dart';
import '../../theme/klayk_theme.dart';
import '../../widgets/ad_spot.dart';
import '../../widgets/ad_widgets.dart';
import '../../widgets/klayk_ux.dart';
import 'game_leaderboard_screen.dart';
import 'quiz_game_screen.dart';
import 'reaction_game_screen.dart';
import 'tic_tac_toe_screen.dart';

/// Catálogo de jogos do KLAY K (aba Jogos). Lista o catálogo do backend
/// (`games`), mostra recompensas/recordes de cada jogo e abre o jogo.
/// O ranking e as recompensas são sempre validados pelo backend.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _svc = GameService.instance;
  final AdSpot _ads = AdSpot();
  List<GameInfo> _games = [];
  Map<String, int> _records = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _ads.load(limit: 4);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final games = await _svc.catalog();
    final records = await _svc.myRecords();
    if (!mounted) return;
    setState(() {
      _games = games;
      _records = records;
      _loading = false;
    });
  }

  void _openGame(GameInfo g) {
    final Widget screen = switch (g.id) {
      'quiz' => const QuizGameScreen(),
      'velha' => const TicTacToeScreen(),
      'toque' => const ReactionGameScreen(),
      _ => QuizGameScreen(gameOverride: g),
    };
    KlaykNav.push(context, screen).then((_) => _load());
  }

  void _openLeaderboard(GameInfo g) {
    KlaykNav.push(context, GameLeaderboardScreen(game: g));
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: const Text(
          'Jogos',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: KlaykLoader())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _header(colors),
                  const SizedBox(height: 16),
                  for (var i = 0; i < _games.length; i++) ...[
                    _gameCard(colors, _games[i]),
                    const SizedBox(height: 12),
                    if ((i + 1) % 3 == 0 && _ads.ads.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AdCard(
                          ad: _ads.ads[i ~/ 3 % _ads.ads.length],
                          onHidden: () => setState(() {
                            final adId = _ads.ads[i ~/ 3 % _ads.ads.length].id;
                            _ads.remove(adId);
                          }),
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Novos jogos em breve no ranking 👀',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _header(KlaykColors colors) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryFaint,
            colors.surfaceAlt,
            colors.bgElevated,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.primarySoft.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.4),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Icon(Icons.sports_esports_rounded, color: colors.primarySoft, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Divirta-se e ganhe cristais',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Complete jogos, suba no ranking e troque por recompensas '
                  'na Central de Recompensas. Pontuação validada no servidor.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gameCard(KlaykColors colors, GameInfo g) {
    final best = _records[g.id] ?? 0;
    final rewardText = _rewardHint(g);
    return KlaykCard(
      onTap: g.isActive ? () => _openGame(g) : null,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(g.emoji, style: const TextStyle(fontSize: 28)),
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
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (g.isSoon) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'em breve',
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.warning,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  g.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  rewardText,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFB794FF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              if (best > 0)
                Text(
                  'Recorde: $best',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white38,
                  ),
                ),
              const SizedBox(height: 6),
              g.isActive
                  ? FilledButton(
                      onPressed: () => _openGame(g),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        elevation: 0,
                        shadowColor: colors.glow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: colors.primarySoft.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                      child: const Text('Jogar',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    )
                  : const SizedBox(height: 20),
              const SizedBox(height: 4),
              if (g.isActive)
                TextButton.icon(
                  onPressed: () => _openLeaderboard(g),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(20, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.leaderboard_rounded, size: 14),
                  label: const Text('Ranking', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _rewardHint(GameInfo g) {
    final rewards = g.rules['rewards'];
    if (rewards is! List || rewards.isEmpty) return 'Sem recompensa';
    final entries = rewards.map((r) {
      if (r is Map) {
        final min = (r['min_score'] as num?)?.toInt() ?? 0;
        final crystals = (r['crystals'] as num?)?.toInt() ?? 0;
        return '$min+ → $crystals🔮';
      }
      return '';
    }).where((s) => s.isNotEmpty).toList();
    return entries.isEmpty ? '' : 'Recompensas: ${entries.join('  •  ')}';
  }
}