import 'package:flutter/material.dart';

import '../models/gift_models.dart';
import '../models/post_models.dart';
import '../screens/missions_screen.dart';
import '../screens/wallet_sheet.dart';
import '../services/content_service.dart';
import '../services/experience_settings.dart';
import '../services/gift_service.dart';
import '../services/live_premium_service.dart';
import '../services/supabase_service.dart';
import 'bubble_dismissal.dart';
import 'verified_badge.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Bolinha flutuante premium do KLAY K (destacada da QuestBubble).
///
/// Painel com abas de presentes, ranking por moeda real, missões, alertas,
/// bot de voz (configuração honesta) e ajustes. Arrasta e persiste posição em
/// `user_settings` (RLS owner), no mesmo padrão da QuestBubble. Nenhum dado é
/// inventado: presentes custam moedas reais validadas no backend e rankings
/// vêm das RPCs `currency_ranking`/`live_ranking`.
class LivePremiumBubble extends StatefulWidget {
  const LivePremiumBubble({super.key});

  @override
  State<LivePremiumBubble> createState() => _LivePremiumBubbleState();
}

class _LivePremiumBubbleState extends State<LivePremiumBubble> {
  static const double _size = 58;

  LiveBubblePrefs _prefs = const LiveBubblePrefs();
  bool _loading = true;
  final BubbleDismissal _dismissal = BubbleDismissal(
    'live_premium_bubble_hidden_until',
  );

  @override
  void initState() {
    super.initState();
    _dismissal.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    final prefs = await LivePremiumService.instance.fetchBubblePrefs();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (!SupabaseService.instance.isConfigured) return const SizedBox.shrink();
    // Cooldown local: enquanto selado pelo X (ou Config), a bolinha fica
    // oculta temporariamente e SEMPRE volta — nunca fica invisível para sempre.
    if (_dismissal.isHidden()) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;
    final maxX = (size.width - _size).clamp(0.0, double.infinity);
    final maxY = (size.height - 96 - _size).clamp(0.0, double.infinity);
    final defaultX = (size.width - _size - 16).clamp(0.0, maxX);
    final defaultY = 200.0.clamp(0.0, maxY);
    final saved = _prefs.positionX == 0 && _prefs.positionY == 0;
    final pos = Offset(
      (saved ? defaultX : _prefs.positionX).clamp(0.0, maxX),
      (saved ? defaultY : _prefs.positionY).clamp(0.0, maxY),
    );

    return Positioned(
      left: 0,
      top: 0,
      child: SizedBox(
        width: size.width,
        height: size.height - 96,
        child: Stack(
          children: [
            Positioned(
              left: pos.dx,
              top: pos.dy,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openPanel,
                    onPanUpdate: (d) {
                      setState(
                        () => _prefs = _prefs.copyWith(
                          positionX: pos.dx + d.delta.dx,
                          positionY: pos.dy + d.delta.dy,
                        ),
                      );
                    },
                    onPanEnd: (_) => _persist(),
                    child: _bubbleWidget(),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _dismissBubble,
                    child: const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(Icons.close, size: 14, color: Colors.white38),
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

  Widget _bubbleWidget() {
    Widget bubble = Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171717), Color(0xFF1D1D1D)],
        ),
        border: Border.all(color: _kAccent, width: 2),
        boxShadow: [
          BoxShadow(
            color: _kAccent.withValues(alpha: 0.25),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.paid_rounded, color: Color(0xFFFFD700), size: 30),
          Positioned(
            right: 6,
            bottom: 6,
            child: Icon(Icons.star_rounded, color: _kAccent, size: 12),
          ),
        ],
      ),
    );

    if (ExperienceSettings.instance.reduceAnimations) return bubble;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.9, end: 1.0),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeInOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: bubble,
    );
  }

  void _persist() {
    LivePremiumService.instance
        .saveBubblePrefs(_prefs.copyWith(enabled: true))
        .catchError((_) {});
  }

  /// Fecha a bolinha por um cooldown (4h). Ela volta sozinha depois.
  void _dismissBubble() {
    _dismissal.dismiss();
    setState(() {});
  }

  Future<void> _openPanel() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF100C18),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _PremiumPanel(onConfigChanged: _load),
    );
    _load();
  }
}

// ============================================================
// PAINEL
// ============================================================

class _PremiumPanel extends StatefulWidget {
  final VoidCallback onConfigChanged;

  const _PremiumPanel({required this.onConfigChanged});

  @override
  State<_PremiumPanel> createState() => _PremiumPanelState();
}

class _PremiumPanelState extends State<_PremiumPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 6, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.72;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Painel Premium',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          const _QuickWalletBar(),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: _kAccent,
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            tabs: const [
              Tab(text: 'Presentes'),
              Tab(text: 'Ranking'),
              Tab(text: 'Missões'),
              Tab(text: 'Alertas'),
              Tab(text: 'Bot de voz'),
              Tab(text: 'Config'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                const _GiftsTab(),
                const _RankingTab(),
                const _MissionsTab(),
                const _AlertsTab(),
                _VoiceBotTab(onChanged: widget.onConfigChanged),
                _ConfigTab(onChanged: widget.onConfigChanged),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BARRA DE CARTEIRA RÁPIDA (painel rápido de saldos)
// ============================================================

class _QuickWalletBar extends StatefulWidget {
  const _QuickWalletBar();

  @override
  State<_QuickWalletBar> createState() => _QuickWalletBarState();
}

class _QuickWalletBarState extends State<_QuickWalletBar> {
  Map<String, dynamic> _wallet = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final w = await GiftService.instance.fetchWalletCurrencies();
      if (!mounted) return;
      setState(() {
        _wallet = w;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int _b(String k) => (_wallet[k] as num?)?.toInt() ?? 0;

  void _openWallet() {
    WalletSheet.show(context);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _openWallet,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF111111), Color(0xFF1D1D1D)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kAccent.withValues(alpha: 0.4)),
        ),
        child: _loading
            ? const SizedBox(
                height: 22,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFFD700),
                    ),
                  ),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Color(0xFFFFD700),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _chip('🪙 ${_fmt(_b('credits'))}'),
                        _chip('💎 ${_fmt(_b('diamonds'))}'),
                        _chip('🔮 ${_fmt(_b('crystals'))}'),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white54,
                    size: 18,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFFFD700),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _fmt(Object? v) {
    final n = (v is num ? v : 0).toDouble();
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}k';
    return n == n.truncateToDouble()
        ? n.toInt().toString()
        : n.toStringAsFixed(1);
  }
}

// ============================================================
// ABA PRESENTES
// ============================================================

class _GiftsTab extends StatefulWidget {
  const _GiftsTab();

  @override
  State<_GiftsTab> createState() => _GiftsTabState();
}

class _GiftsTabState extends State<_GiftsTab> {
  List<Gift> _gifts = const [];
  Map<String, dynamic> _wallet = const {};
  bool _loading = true;
  String? _error;

  static const List<(String, String)> _currencies = [
    ('credits', 'Créditos'),
    ('diamonds', 'Diamantes'),
    ('crystals', 'Cristais'),
    ('rubies', 'Rubis'),
    ('emeralds', 'Esmeraldas'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final gifts = await GiftService.instance.fetchGifts(
        page: 0,
        pageSize: 24,
      );
      final wallet = await GiftService.instance.fetchWalletCurrencies();
      if (!mounted) return;
      setState(() {
        _gifts = gifts;
        _wallet = wallet;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int _balance(String currency) => (_wallet[currency] as num?)?.toInt() ?? 0;

  Future<void> _send(Gift gift, int amount) async {
    final requestId =
        '${SupabaseService.instance.client.auth.currentUser?.id ?? 'anon'}'
        '-${DateTime.now().microsecondsSinceEpoch}';
    // Presente sem live: ainda é cobrado com moedas reais e fica no histórico,
    // com o mesmo padrão idempotente do envio dentro das lives.
    final result = await GiftService.instance.sendGift(
      gift: gift,
      amount: amount,
      requestId: requestId,
    );
    if (!mounted) return;
    GiftService.instance.invalidateWalletCache();
    setState(() {
      if (result.balance > 0) _wallet['credits'] = result.balance;
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.duplicate
              ? 'Presente já enviado anteriormente (nada foi debitado de novo).'
              : result.unlimited
              ? '${gift.icon} ${gift.name} x$amount enviado! (fundador ilimitado — grátis)'
              : '${gift.icon} ${gift.name} x$amount enviado! ${-result.creditsSpent} créditos',
        ),
      ),
    );
  }

  Future<void> _pickAmount(Gift gift) async {
    final balance = _balance('credits');
    final amount = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1A1424),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${gift.icon} ${gift.name}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${gift.credits} créditos cada',
                style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'Saldo: $balance',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                children: [1, 5, 10, 66, 99].map((n) {
                  final ok = n * gift.credits <= balance;
                  return ChoiceChip(
                    label: Text(
                      'x$n',
                      style: const TextStyle(color: Colors.white),
                    ),
                    selected: false,
                    backgroundColor: const Color(0xFF2A2A35),
                    selectedColor: _kAccent,
                    onSelected: ok ? (_) => Navigator.of(ctx).pop(n) : null,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
    if (amount == null || !mounted) return;
    try {
      await _send(gift, amount);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Não foi possível carregar os presentes.\n$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _walletChips(),
        const SizedBox(height: 12),
        if (_gifts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Nenhum presente ativo no catálogo.',
              style: TextStyle(color: Colors.white54),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.8,
            ),
            itemCount: _gifts.length,
            itemBuilder: (context, index) {
              final g = _gifts[index];
              final afford = _balance('credits') >= g.credits;
              return InkWell(
                onTap: afford ? () => _pickAmount(g) : null,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF23232E),
                    borderRadius: BorderRadius.circular(12),
                    border: g.isExclusive
                        ? Border.all(color: const Color(0xFF00E5FF), width: 1)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(g.icon, style: const TextStyle(fontSize: 28)),
                      const SizedBox(height: 4),
                      Text(
                        g.name,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${g.credits}',
                        style: TextStyle(
                          color: afford
                              ? const Color(0xFFFFD700)
                              : const Color(0xFFFF5252),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _walletChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _currencies.map((c) {
        final (code, label) = c;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1A2A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(
            '$label: ${_balance(code)}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        );
      }).toList(),
    );
  }
}

// ============================================================
// ABA RANKING
// ============================================================

class _RankingTab extends StatefulWidget {
  const _RankingTab();

  @override
  State<_RankingTab> createState() => _RankingTabState();
}

class _RankingTabState extends State<_RankingTab>
    with SingleTickerProviderStateMixin {
  static const List<(String, String)> _currencies = [
    ('credits', '💎'),
    ('diamonds', '💠'),
    ('crystals', '🔷'),
    ('rubies', '🔴'),
    ('emeralds', '🟢'),
  ];

  late final TabController _tabs = TabController(
    length: _currencies.length,
    vsync: this,
  );
  int _currencyIndex = 0;
  List<LiveRankRecord> _top = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      setState(() {
        _currencyIndex = _tabs.index;
        _top = const [];
        _loading = true;
        _error = null;
      });
      _load();
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final (currency, _) = _currencies[_currencyIndex];
    try {
      final top = await LivePremiumService.instance.fetchCurrencyRanking(
        currency,
        limit: 15,
      );
      if (!mounted) return;
      setState(() {
        _top = top;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: _kAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          tabs: _currencies.map((c) => Tab(text: c.$2)).toList(),
        ),
        const SizedBox(height: 4),
        const Text(
          'Rankings reais por moeda (carteiras validadas no backend).',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              if (_loading) {
                return const Center(
                  child: CircularProgressIndicator(color: _kAccent),
                );
              }
              if (_error != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Não foi possível carregar o ranking.\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
                );
              }
              if (_top.isEmpty) {
                return const Center(
                  child: Text(
                    'Ainda não há apoiadores com saldo nesta moeda.',
                    style: TextStyle(color: Colors.white54),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _top.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final r = _top[index];
                  final color = index == 0
                      ? const Color(0xFFFFD700)
                      : index == 1
                      ? const Color(0xFFC0C0C0)
                      : index == 2
                      ? const Color(0xFFCD7F32)
                      : Colors.white54;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1724),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '#${r.rank}',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 10),
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: _kAccent.withValues(alpha: 0.35),
                          backgroundImage: r.avatarUrl != null
                              ? NetworkImage(r.avatarUrl!)
                              : null,
                          child: const Icon(
                            Icons.person,
                            color: Colors.white70,
                            size: 13,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  r.displayName ?? r.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              if (r.isVerified) ...[
                                const SizedBox(width: 4),
                                const VerifiedBadge(size: 14),
                              ],
                            ],
                          ),
                        ),
                        Text(
                          '${r.value.toStringAsFixed(0)} ${_currencies[_currencyIndex].$2}',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================
// ABA MISSÕES
// ============================================================

class _MissionsTab extends StatelessWidget {
  const _MissionsTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎯', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            const Text(
              'Missões e níveis do KLAY K',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Complete missões para subir de nível, ganhar XP e desbloquear conquistas reais.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => MissionsScreen.show(context),
              style: FilledButton.styleFrom(backgroundColor: _kAccent),
              icon: const Icon(Icons.bolt_rounded),
              label: const Text('Abrir missões'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ABA ALERTAS
// ============================================================

class _AlertsTab extends StatefulWidget {
  const _AlertsTab();

  @override
  State<_AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<_AlertsTab> {
  List<AppNotification> _alerts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ContentService.instance.fetchNotifications();
      if (!mounted) return;
      setState(() {
        _alerts = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_alerts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhum alerta no momento.',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _alerts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final a = _alerts[index];
        final isGift = a.type == 'gift';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1724),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: a.read ? Colors.white10 : _kAccent.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isGift
                    ? Icons.card_giftcard_rounded
                    : Icons.notifications_rounded,
                color: isGift ? const Color(0xFFFFD700) : _kAccent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  a.message,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _timeLabel(a.createdAt),
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        );
      },
    );
  }

  String _timeLabel(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}

// ============================================================
// ABA BOT DE VOZ (configuração honesta)
// ============================================================

class _VoiceBotTab extends StatefulWidget {
  final VoidCallback onChanged;

  const _VoiceBotTab({required this.onChanged});

  @override
  State<_VoiceBotTab> createState() => _VoiceBotTabState();
}

class _VoiceBotTabState extends State<_VoiceBotTab> {
  VoiceBotConfig _config = const VoiceBotConfig();
  final TextEditingController _provider = TextEditingController();
  final TextEditingController _voice = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _provider.dispose();
    _voice.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await LivePremiumService.instance.fetchVoiceBot();
    if (!mounted) return;
    setState(() {
      _config = config;
      _provider.text = config.provider ?? '';
      _voice.text = config.voice ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    final next = VoiceBotConfig(
      enabled: _config.enabled,
      provider: _provider.text.trim().isEmpty ? null : _provider.text.trim(),
      voice: _voice.text.trim().isEmpty ? null : _voice.text.trim(),
    );
    await LivePremiumService.instance.saveVoiceBot(next);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          value: _config.enabled,
          onChanged: (v) async {
            setState(
              () => _config = VoiceBotConfig(
                enabled: v,
                provider: _config.provider,
                voice: _config.voice,
              ),
            );
            await _save();
          },
          title: const Text(
            'Bot de voz',
            style: TextStyle(color: Colors.white),
          ),
          subtitle: const Text(
            'Participa da live comentando falado (requer provedor real).',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          activeTrackColor: _kAccent,
        ),
        const SizedBox(height: 10),
        const Text(
          'Provedor de voz',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _provider,
          onChanged: (_) => _save(),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'ex.: ElevenLabs / Azure',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF1E1A2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Voz',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _voice,
          onChanged: (_) => _save(),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'ex.: Aria / Rodrigo',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF1E1A2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2012),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
            ),
          ),
          child: const Text(
            'Transparência: o bot de voz só produz áudio quando a equipe do '
            'KLAY K configurar um provedor de voz real no backend. Sem provedor, '
            'esta opção fica registrada sem gerar voz falsa.',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// ABA CONFIG
// ============================================================

class _ConfigTab extends StatefulWidget {
  final VoidCallback onChanged;

  const _ConfigTab({required this.onChanged});

  @override
  State<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<_ConfigTab> {
  LiveBubblePrefs _prefs = const LiveBubblePrefs();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await LivePremiumService.instance.fetchBubblePrefs();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await LivePremiumService.instance.saveBubblePrefs(_prefs);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          value: _prefs.enabled,
          onChanged: (v) {
            setState(() => _prefs = _prefs.copyWith(enabled: v));
            // Desligar esconde a bolinha por um COOLDOWN (não para sempre):
            // depois de algumas horas ela volta a aparecer sozinha.
            final d = BubbleDismissal('live_premium_bubble_hidden_until');
            if (v) {
              d.reenable();
            } else {
              d.dismiss();
            }
            _save();
          },
          title: const Text(
            'Bolinha premium',
            style: TextStyle(color: Colors.white),
          ),
          subtitle: const Text(
            'Atalho flutuante com presentes, ranking e alertas. '
            'Ao desligar, fica oculta por algumas horas e volta depois.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          activeTrackColor: _kAccent,
        ),
        SwitchListTile(
          value: _prefs.minimized,
          onChanged: (v) {
            setState(() => _prefs = _prefs.copyWith(minimized: v));
            _save();
          },
          title: const Text(
            'Minimizada',
            style: TextStyle(color: Colors.white),
          ),
          subtitle: const Text(
            'Abre fechada, sem expandir automaticamente o painel.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          activeTrackColor: _kAccent,
        ),
      ],
    );
  }
}
