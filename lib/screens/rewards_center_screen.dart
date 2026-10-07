import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/admin_service.dart';
import '../services/invite_service.dart';
import '../services/social_service.dart';
import '../theme/klayk_theme.dart';
import '../widgets/klayk_ux.dart';
import 'achievements_screen.dart';
import 'chests_screen.dart';
import 'missions_screen.dart';
import 'wallet_sheet.dart';

/// Central de Recompensas: agrega em uma única tela as fontes de ganho do
/// KLAY K — carteira multi-moeda (backend), missões, baús, conquistas e
/// convites pendentes. Nada aqui decide valores; tudo vem das RPCs do banco.
class RewardsCenterScreen extends StatefulWidget {
  const RewardsCenterScreen({super.key});

  @override
  State<RewardsCenterScreen> createState() => _RewardsCenterScreenState();
}

class _RewardsCenterScreenState extends State<RewardsCenterScreen> {
  bool _loading = true;
  Map<String, dynamic> _wallet = const {};
  LevelProgress _progress = LevelProgress.empty();
  int _unlockedCount = 0;
  int _pendingInvites = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final inviteSummary = await InviteService.instance.summary();
    try {
      final wallet = await AdminService.instance.myWallet();
      final progress = await SocialService.instance.fetchMyProgress();
      final achievements = await SocialService.instance
          .fetchAchievements()
          .catchError((_) => const <Achievement>[]);
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _progress = progress;
        _unlockedCount = achievements.where((a) => a.unlocked).length;
        _pendingInvites = inviteSummary.pendingRewards;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = kcolors(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: Text(l10n.rewardsCenterTitle)),
      body: _loading
          ? const Center(child: KlaykLoader())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _walletCard(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _shortcut(
                        colors,
                        Icons.military_tech_rounded,
                        l10n.missionsTab,
                        l10n.missionsInPeriod(_progress.missions.length),
                        () {
                          KlaykNav.push(context, const MissionsScreen());
                        },
                      ),
                      const SizedBox(width: 10),
                      _shortcut(
                        colors,
                        Icons.inventory_2_rounded,
                        l10n.chests,
                        l10n.openDailyChest,
                        () {
                          KlaykNav.push(context, const ChestsScreen());
                        },
                      ),
                      const SizedBox(width: 10),
                      _shortcut(
                        colors,
                        Icons.emoji_events_rounded,
                        l10n.achievements,
                        l10n.achievementsUnlocked(_unlockedCount),
                        () {
                          KlaykNav.push(context, const AchievementsScreen());
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _rewardsStatus(colors),
                ],
              ),
            ),
    );
  }

  Widget _walletCard() {
    final l10n = AppLocalizations.of(context)!;
    final currencies = [
      'credits',
      'diamonds',
      'crystals',
      'rubies',
      'emeralds',
    ];
    final labels = {
      'credits': '🪙',
      'diamonds': '💎',
      'crystals': '🔮',
      'rubies': '🔴',
      'emeralds': '💚',
    };
    return KlaykCard(
      onTap: () => KlaykNav.push(context, const WalletSheet()),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFF8B5CF6),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.yourWallet,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                l10n.viewStatement,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: currencies.map((c) {
              final value = (_wallet[c] is num)
                  ? ((_wallet[c] as num?)?.toInt() ?? 0)
                  : 0;
              return Expanded(
                child: Column(
                  children: [
                    Text(
                      labels[c] ?? '•',
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$value',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _currencyName(c, l10n),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _shortcut(
    KlaykColors colors,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: KlaykCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        onTap: onTap,
        child: Column(
          children: [
            Icon(icon, color: colors.primary),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 10, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rewardsStatus(KlaykColors colors) {
    final l10n = AppLocalizations.of(context)!;
    return KlaykCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.howToEarnTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _row(
            Icons.star_rounded,
            '${l10n.levelLabel} ${_progress.level}',
            l10n.xpAccumulated(_progress.xpTotal),
            colors.gold,
          ),
          const SizedBox(height: 10),
          _row(
            Icons.military_tech_rounded,
            l10n.completeMissions,
            l10n.missionsProgramDesc,
            colors.info,
          ),
          const SizedBox(height: 10),
          _row(
            Icons.card_giftcard_rounded,
            l10n.invites,
            l10n.pendingRewards(_pendingInvites),
            colors.success,
          ),
          const SizedBox(height: 10),
          _row(
            Icons.games_rounded,
            l10n.games,
            l10n.rankUpEarnCrystals,
            colors.warning,
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String title, String subtitle, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _currencyName(String id, AppLocalizations l10n) {
    return switch (id) {
      'credits' => l10n.coinsSection,
      'diamonds' => l10n.diamonds,
      'crystals' => l10n.crystals,
      'rubies' => l10n.rubies,
      'emeralds' => l10n.emeralds,
      _ => id,
    };
  }
}
