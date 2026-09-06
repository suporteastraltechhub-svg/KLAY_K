import 'package:flutter/material.dart';

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
      final achievements =
          await SocialService.instance.fetchAchievements().catchError((_) => const <Achievement>[]);
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _progress = progress;
        _unlockedCount =
            achievements.where((a) => a.unlocked).length;
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
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(title: const Text('Central de Recompensas')),
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
                      _shortcut(colors, Icons.military_tech_rounded, 'Missões',
                          '${_progress.missions.length} no período', () {
                        KlaykNav.push(context, const MissionsScreen());
                      }),
                      const SizedBox(width: 10),
                      _shortcut(colors, Icons.inventory_2_rounded, 'Baús',
                          'Abra o diário', () {
                        KlaykNav.push(context, const ChestsScreen());
                      }),
                      const SizedBox(width: 10),
                      _shortcut(colors, Icons.emoji_events_rounded, 'Conquistas',
                          '$_unlockedCount desbloqueadas', () {
                        KlaykNav.push(context, const AchievementsScreen());
                      }),
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
    final currencies = ['credits', 'diamonds', 'crystals', 'rubies', 'emeralds'];
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
          const Row(
            children: [
              Icon(Icons.workspace_premium_rounded,
                  color: Color(0xFF8B5CF6)),
              SizedBox(width: 8),
              Text('Sua carteira',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Spacer(),
              Text('Ver extrato',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
              Icon(Icons.chevron_right_rounded, size: 18),
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
                    Text(labels[c] ?? '•',
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 4),
                    Text('$value',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(_currencyName(c),
                        style:
                            const TextStyle(fontSize: 10, color: Colors.white38)),
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
      KlaykColors colors, IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Expanded(
      child: KlaykCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        onTap: onTap,
        child: Column(
          children: [
            Icon(icon, color: colors.primary),
            const SizedBox(height: 8),
            Text(title,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(fontSize: 10, color: Colors.white38)),
          ],
        ),
      ),
    );
  }

  Widget _rewardsStatus(KlaykColors colors) {
    return KlaykCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Como ganhar',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _row(
            Icons.star_rounded,
            'Nível ${_progress.level}',
            '${_progress.xpTotal} XP acumulados',
            colors.gold,
          ),
          const SizedBox(height: 10),
          _row(
            Icons.military_tech_rounded,
            'Complete missões',
            'Programa missões diárias e semanais',
            colors.info,
          ),
          const SizedBox(height: 10),
          _row(
            Icons.card_giftcard_rounded,
            'Convites',
            '$_pendingInvites recompensas pendentes',
            colors.success,
          ),
          const SizedBox(height: 10),
          _row(
            Icons.games_rounded,
            'Jogos',
            'Suba no ranking e ganhe cristais',
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
              Text(title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              Text(subtitle,
                  style:
                      const TextStyle(fontSize: 12, color: Colors.white54)),
            ],
          ),
        ),
      ],
    );
  }

  String _currencyName(String id) {
    return switch (id) {
      'credits' => 'Moedas',
      'diamonds' => 'Diamantes',
      'crystals' => 'Cristais',
      'rubies' => 'Rubis',
      'emeralds' => 'Esmeraldas',
      _ => id,
    };
  }
}