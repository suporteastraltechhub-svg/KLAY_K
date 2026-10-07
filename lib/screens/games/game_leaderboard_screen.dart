import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/game_service.dart';
import '../../theme/klayk_theme.dart';
import '../../widgets/klayk_ux.dart';
import '../../widgets/verified_badge.dart';

/// Ranking real do jogo (top 20) — retornado do backend pela RPC
/// `game_leaderboard` (security definer). Nenhum dado local.
class GameLeaderboardScreen extends StatefulWidget {
  const GameLeaderboardScreen({super.key, required this.game});

  final GameInfo game;

  @override
  State<GameLeaderboardScreen> createState() => _GameLeaderboardScreenState();
}

class _GameLeaderboardScreenState extends State<GameLeaderboardScreen> {
  List<GameRankEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await GameService.instance.leaderboard(widget.game.id);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: Text(l10n.gameRankingOf(widget.game.name))),
      body: _loading
          ? const Center(child: KlaykLoader())
          : _entries.isEmpty
          ? KlaykEmptyState(
              icon: Icons.leaderboard_rounded,
              title: l10n.gameRankEmpty,
              message: l10n.gameRankEmptyMsg,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _entries.length,
                itemBuilder: (context, i) => _entryTile(_entries[i]),
              ),
            ),
    );
  }

  Widget _entryTile(GameRankEntry e) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    final medal = switch (e.rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KlaykCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: medal != null
                  ? Text(medal, style: const TextStyle(fontSize: 22))
                  : Text(
                      '${e.rank}°',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Colors.white54,
                      ),
                    ),
            ),
            CircleAvatar(
              radius: 16,
              backgroundColor: colors.surfaceAlt,
              backgroundImage: e.avatarUrl.isNotEmpty
                  ? NetworkImage(e.avatarUrl)
                  : null,
              child: e.avatarUrl.isEmpty
                  ? const Icon(Icons.person_rounded, size: 18)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          e.displayName.isEmpty
                              ? l10n.gameParticipant
                              : e.displayName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (e.isVerified) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 14),
                      ],
                    ],
                  ),
                  Text(
                    e.bestScore.toString(),
                    style: const TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                ],
              ),
            ),
            Text(
              l10n.gamePoints(e.bestScore),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
