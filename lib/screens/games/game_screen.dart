import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/admin_service.dart';
import '../../services/game_service.dart';
import '../../services/social_service.dart';
import '../../theme/klayk_theme.dart';
import '../../widgets/ad_spot.dart';
import '../../widgets/ad_widgets.dart';
import '../../widgets/klayk_game_card.dart';
import '../../widgets/klayk_ux.dart';
import '../achievements_screen.dart';
import '../missions_screen.dart';
import '../rankings_screen.dart';
import '../rewards_center_screen.dart';
import '../wallet_sheet.dart';
import 'engines/engine_common.dart';
import 'game_leaderboard_screen.dart';
import 'game_router.dart';

/// Categorias exibidas como filtro (padronizadas com o catálogo do backend).
const _categories = <({String id, String label, String icon})>[
  (id: 'trivia', label: 'Trivia', icon: '🧠'),
  (id: 'reflexo', label: 'Reflexo', icon: '⚡'),
  (id: 'memoria', label: 'Memória', icon: '🃏'),
  (id: 'matematica', label: 'Matemática', icon: '🔢'),
  (id: 'palavras', label: 'Palavras', icon: '🔤'),
  (id: 'arcade', label: 'Arcade', icon: '🕹️'),
  (id: 'estrategia', label: 'Estratégia', icon: '♟️'),
  (id: 'esportes', label: 'Esportes', icon: '⚽'),
  (id: 'musica', label: 'Música', icon: '🎵'),
  (id: 'quebra-cabeca', label: 'Quebra-cabeça', icon: '🧩'),
  (id: 'cartas', label: 'Cartas', icon: '🃏'),
  (id: 'construcao', label: 'Construção', icon: '🏗️'),
  (id: 'aventura', label: 'Aventura', icon: '🗺️'),
  (id: 'corrida', label: 'Corrida', icon: '🏎️'),
];

/// Catálogo de jogos do KLAY K (aba Jogos) — redesign premium.
///
/// Header com saldo 🪙 / nível ⭐ / XP 🏆 reais (backend), categorias, seções
/// 🔥 Em alta (popularidade real), ▶ Continuar jogando (recordes), acesso
/// rápido a Ranking/Recompensas/Conquistas/Missões e lista paginada do
/// catálogo. Cada jogo abre pela engine declarada ([gameScreenFor]); todo
/// placar/recompensa é validado no servidor.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _svc = GameService.instance;
  final _social = SocialService.instance;
  final _admin = AdminService.instance;
  final AdSpot _ads = AdSpot();

  List<GameInfo> _games = [];
  Map<String, int> _records = const {};
  List<GamePopularity> _popularity = const [];
  LevelProgress _progress = LevelProgress.empty();
  int _credits = 0;
  bool _loading = true;
  String? _category;
  int _shown = 18;
  static const _pageStep = 18;

  @override
  void initState() {
    super.initState();
    _load();
    _ads.load(limit: 4);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait<Object>([
      _svc.catalog(),
      _svc.myRecords(),
      _svc.popularity(),
      _safeProgress(),
      _safeWallet(),
    ]);
    if (!mounted) return;
    setState(() {
      _games = (results[0] as List<GameInfo>).cast<GameInfo>();
      _records = results[1] as Map<String, int>;
      _popularity = (results[2] as List<GamePopularity>).cast<GamePopularity>();
      _progress = results[3] as LevelProgress;
      final wallet = results[4] as Map<String, dynamic>;
      _credits = (wallet['credits'] as num?)?.toInt() ?? 0;
      _loading = false;
      _shown = 18;
    });
  }

  Future<Map<String, dynamic>> _safeWallet() async {
    try {
      return await _admin.myWallet();
    } catch (_) {
      return const {};
    }
  }

  Future<LevelProgress> _safeProgress() async {
    try {
      return await _social.fetchMyProgress();
    } catch (_) {
      return LevelProgress.empty();
    }
  }

  List<GameInfo> get _filtered {
    final cat = _category;
    return _games.where((g) => cat == null || g.category == cat).toList();
  }

  int _playsOf(GameInfo g) {
    for (final p in _popularity) {
      if (p.gameId == g.id) return p.plays;
    }
    return 0;
  }

  List<GameInfo> get _trending {
    final sorted = _games.where((g) => g.isActive).toList()
      ..sort((a, b) => _playsOf(b).compareTo(_playsOf(a)));
    return sorted.take(6).toList();
  }

  List<GameInfo> get _continuePlaying =>
      _games.where((g) => g.isActive && (_records[g.id] ?? 0) > 0).toList();

  Future<void> _openGame(GameInfo g) async {
    await openGame(context, g);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text(
          l10n.gameTitle,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? Center(child: KlaykLoader(label: l10n.gameLoading))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _headerPremium(colors, l10n),
                  const SizedBox(height: 16),
                  if (_continuePlaying.isNotEmpty) ...[
                    _sectionTitle(colors, '▶', l10n.gameContinuePlaying),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 128,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _continuePlaying.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, i) => _ContinueCard(
                          game: _continuePlaying[i],
                          best: _records[_continuePlaying[i].id] ?? 0,
                          onTap: _continuePlaying[i].isActive
                              ? () => _openGame(_continuePlaying[i])
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _sectionTitle(colors, '🔥', l10n.gameTrending),
                  const SizedBox(height: 10),
                  if (_trending.isNotEmpty)
                    SizedBox(
                      height: 132,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _trending.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, i) => _TrendCard(
                          game: _trending[i],
                          plays: _playsOf(_trending[i]),
                          onTap: () => _openGame(_trending[i]),
                        ),
                      ),
                    )
                  else
                    _playlessHint(colors, l10n),
                  const SizedBox(height: 16),
                  _sectionTitle(colors, '🎯', l10n.gameChallenges),
                  const SizedBox(height: 10),
                  _quickAccess(colors, l10n),
                  const SizedBox(height: 18),
                  _sectionTitle(colors, '🎮', l10n.gameExplore),
                  const SizedBox(height: 10),
                  _categoryChips(colors, l10n),
                  const SizedBox(height: 4),
                  if (_filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: KlaykEmptyState(
                        icon: Icons.sports_esports_rounded,
                        title: l10n.gameEmptyTitle,
                        message: l10n.gameEmptyMsg,
                      ),
                    )
                  else
                    for (var i = 0; i < _filtered.length && i < _shown; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _catalogCard(colors, _filtered[i], i),
                      ),
                  if (_shown < _filtered.length)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _shown += _pageStep),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.primarySoft,
                          side: BorderSide(color: colors.primary),
                          minimumSize: const Size.fromHeight(46),
                        ),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(
                          l10n.gameLoadMore(_filtered.length - _shown),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.gameComingSoon,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header premium: saldo / nível / XP
  // ---------------------------------------------------------------------------
  Widget _headerPremium(KlaykColors colors, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryFaint, colors.surfaceAlt, colors.bgElevated],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.primarySoft.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.22),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: colors.primarySoft.withValues(alpha: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.45),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.sports_esports_rounded,
                  color: colors.primarySoft,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.gameHeaderTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.gameHeaderSubtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _statBox(
                colors,
                emoji: '🪙',
                value: _format(_credits),
                label: l10n.gameBalance,
                onTap: () => WalletSheet.show(context),
              ),
              const SizedBox(width: 8),
              _statBox(
                colors,
                emoji: '⭐',
                value: '${_progress.level}',
                label: l10n.gameLevel(_progress.levelTitle),
                onTap: () => KlaykNav.push(context, const AchievementsScreen()),
              ),
              const SizedBox(width: 8),
              _statBox(
                colors,
                emoji: '🏆',
                value: _format(_progress.xpTotal),
                label: l10n.gameXp,
                onTap: () => KlaykNav.push(context, const RankingsScreen()),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _progress.levelFraction,
              minHeight: 7,
              backgroundColor: Colors.white10,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _progress.xpNextLevel == null
                ? l10n.gameMaxLevel
                : l10n.gameXpToNext(_progress.xpToNext, _progress.level + 1),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _statBox(
    KlaykColors colors, {
    required String emoji,
    required String value,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: colors.surface.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 3),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 9.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Acesso rápido a Desafios/Ranking/Recompensas/Conquistas
  // ---------------------------------------------------------------------------
  Widget _quickAccess(KlaykColors colors, AppLocalizations l10n) {
    final items = [
      (
        icon: Icons.emoji_events_rounded,
        label: l10n.gameRanking,
        color: colors.success,
      ),
      (
        icon: Icons.card_giftcard_rounded,
        label: l10n.gameRewards,
        color: colors.warning,
      ),
      (
        icon: Icons.military_tech_rounded,
        label: l10n.gameAchievements,
        color: colors.primarySoft,
      ),
      (
        icon: Icons.flag_rounded,
        label: l10n.gameMissions,
        color: const Color(0xFF38BDF8),
      ),
    ];
    final actions = <VoidCallback>[
      () => KlaykNav.push(context, const RankingsScreen()),
      () => KlaykNav.push(context, const RewardsCenterScreen()),
      () => KlaykNav.push(context, const AchievementsScreen()),
      () => MissionsScreen.show(context),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < items.length - 1 ? 8 : 0),
              child: _QuickTile(
                icon: items[i].icon,
                label: items[i].label,
                color: items[i].color,
                onTap: actions[i],
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Chips de categorias
  // ---------------------------------------------------------------------------
  Widget _categoryChips(KlaykColors colors, AppLocalizations l10n) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(colors, l10n.gameAll, Icons.apps_rounded, null),
          for (final c in _categories) _chip(colors, c.label, null, c.id),
        ],
      ),
    );
  }

  Widget _chip(
    KlaykColors colors,
    String label,
    IconData? icon,
    String? value,
  ) {
    final selected = _category == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: icon != null
            ? Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : Colors.white60,
              )
            : null,
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _category = selected ? null : value),
        backgroundColor: colors.surface,
        selectedColor: colors.primary,
        checkmarkColor: Colors.white,
        side: BorderSide(color: selected ? colors.primary : colors.border),
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        visualDensity: VisualDensity.compact,
        clipBehavior: Clip.antiAlias,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Card do catálogo (com anúncio a cada 5)
  // ---------------------------------------------------------------------------
  Widget _catalogCard(KlaykColors colors, GameInfo g, int index) {
    final children = <Widget>[
      KlaykGameCard(
        game: g,
        best: _records[g.id] ?? 0,
        onPlay: g.isActive ? () => _openGame(g) : null,
        onRanking: g.isActive
            ? () => KlaykNav.push(context, GameLeaderboardScreen(game: g))
            : null,
      ),
      if (index > 0 && index % 5 == 0 && _ads.ads.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: AdCard(
            ad: _ads.ads[index ~/ 5 % _ads.ads.length],
            onHidden: () => setState(() {
              _ads.remove(_ads.ads[index ~/ 5 % _ads.ads.length].id);
            }),
          ),
        ),
    ];
    return Column(children: children);
  }

  Widget _sectionTitle(KlaykColors colors, String emoji, String title) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 15)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _playlessHint(KlaykColors colors, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        l10n.gameTrendingHint,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
    );
  }

  String _format(Object? v) {
    final n = (v is num ? v : 0).toDouble();
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}k';
    return n == n.truncateToDouble()
        ? n.toInt().toString()
        : n.toStringAsFixed(1);
  }
}

// ============================================================================
// Cards do catálogo
// ============================================================================

/// Card horizontal do "Em alta" (popularidade real do backend).
class _TrendCard extends StatelessWidget {
  final GameInfo game;
  final int plays;
  final VoidCallback onTap;

  const _TrendCard({
    required this.game,
    required this.plays,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    final tint = engineColor(game, fallback: colors.primary);
    return KlaykCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 128,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [tint.withValues(alpha: 0.4), colors.surfaceAlt],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tint.withValues(alpha: 0.5)),
              ),
              child: Center(
                child: Text(game.emoji, style: const TextStyle(fontSize: 22)),
              ),
            ),
            const Spacer(),
            Text(
              game.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              '🔥 ${l10n.gamePlays(plays)}',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            Text(
              '${'⭐' * game.difficulty} ${_categoryShort(game.category)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tint.withValues(alpha: 0.9),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryShort(String c) {
    const map = {
      'trivia': 'Trivia',
      'reflexo': 'Reflexo',
      'memoria': 'Memória',
      'matematica': 'Mat.',
      'palavras': 'Palavras',
      'arcade': 'Arcade',
      'estrategia': 'Estrat.',
      'esportes': 'Esportes',
      'musica': 'Música',
      'corrida': 'Corrida',
      'construcao': 'Const.',
      'aventura': 'Aventura',
      'cartas': 'Cartas',
      'quebra-cabeca': 'Quebra',
    };
    return map[c] ?? c;
  }
}

/// Card horizontal do "Continuar jogando" (recordes pessoais reais).
class _ContinueCard extends StatelessWidget {
  final GameInfo game;
  final int best;
  final VoidCallback? onTap;

  const _ContinueCard({required this.game, required this.best, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    final tint = engineColor(game, fallback: colors.primary);
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 118,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tint.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(game.emoji, style: const TextStyle(fontSize: 22)),
              const Spacer(),
              Text(
                game.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.gameRecord(best),
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: _PlayButton(tint: tint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final Color tint;

  const _PlayButton({required this.tint});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(color: tint.withValues(alpha: 0.4), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_arrow_rounded, size: 13, color: Colors.white),
          Text(
            l10n.gamePlay,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tile de acesso rápido do "Desafios".
class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
