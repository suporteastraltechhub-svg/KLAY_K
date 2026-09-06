import 'package:flutter/material.dart';

import '../services/admin_service.dart';
import '../services/conversion_service.dart';
import '../services/reward_service.dart';
import 'conversion_screen.dart';
import 'store_screen.dart';

/// Carteira virtual premium do KLAY K.
///
/// Tema escuro com glassmorphism, gradientes e bordas brilhantes. Todos os
/// saldos vêm do backend (RPCs/RLS — nunca decididos no cliente). Reaproveita
/// o sistema existente: moedas (`my_wallet`), histórico (`credit_transactions`),
/// baú diário (`claim_daily_chest`) e recompensa assistida
/// (`claim_watch_cycle_reward`). O diagnóstico de "Reais" usa a taxa de
/// conversão/resgate ativa do backend (quando existente), sem inventar saldo.
class WalletSheet extends StatefulWidget {
  const WalletSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12101A),
      isScrollControlled: true,
      isDismissible: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const WalletSheet(),
    );
  }

  @override
  State<WalletSheet> createState() => _WalletSheetState();
}

class _WalletSheetState extends State<WalletSheet> {
  final AdminService _admin = AdminService.instance;
  final ConversionService _conversion = ConversionService.instance;

  Map<String, dynamic> _wallet = const {};
  List<Map<String, dynamic>> _currencies = const [];
  List<Map<String, dynamic>> _tx = const [];
  List<Map<String, dynamic>> _conversions = const [];
  Map<String, dynamic> _progress = const {};
  bool _loading = true;
  String? _error;

  bool _claimingChest = false;
  bool _claimingWatch = false;

  /// Filtro ativo do extrato: 0=Todo, 1=Entradas, 2=Saídas, 3=Presentes,
  /// 4=Recompensas. Aplica-se apenas à exibição (nunca altera o backend).
  int _txFilter = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Cargas paralelas: saldo + catálogo + histórico + conversão + missões.
      final results = await Future.wait([
        _admin.myWallet(),
        _admin.currencies(),
        _admin.myTransactions(limit: 40),
        _safe(_conversion.settings()),
        _safe(_admin.myProgress()),
      ]);
      if (!mounted) return;
      setState(() {
        _wallet = (results[0] as Map<String, dynamic>?) ?? const {};
        _currencies = (results[1] as List<Map<String, dynamic>>?) ?? const [];
        _tx = (results[2] as List<Map<String, dynamic>>?) ?? const [];
        _conversions = (results[3] as List<Map<String, dynamic>>?) ?? const [];
        _progress = (results[4] as Map<String, dynamic>?) ?? const {};
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

  Future<T> _safe<T>(Future<T> future) async {
    try {
      return await future;
    } catch (_) {
      return Future.value(<dynamic>[]).then((_) => ([] as dynamic));
    }
  }

  int get _credits => (_wallet['credits'] as num?)?.toInt() ?? 0;

  /// Estimativa em "Reais" usando a taxa de conversão/resgate de credits ativa
  /// no backend; `null` quando não houver cotação (sem inventar valor).
  double? get _brlEstimate {
    for (final s in _conversions) {
      final from = s['from_currency']?.toString();
      final to = s['to_currency']?.toString();
      final rate = (s['rate'] as num?)?.toDouble() ?? 0;
      if (from == 'credits' && to != 'credits' && rate > 0) {
        final min = (s['min_amount'] as num?)?.toInt() ?? 1;
        final fullUnits = min > 0 ? (_credits ~/ min) : 0;
        return fullUnits * rate;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> get _dailyMissions {
    final list = _progress['missions'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((m) => m['frequency']?.toString() == 'daily')
        .toList();
  }

  /// Extrato filtrado conforme a categoria ativa (base real de
  /// `credit_transactions`; filtro é só apresentação).
  List<Map<String, dynamic>> get _filteredTx {
    if (_txFilter == 0) return _tx;
    return _tx.where((t) {
      final kind = t['kind']?.toString() ?? '';
      final delta = (t['delta'] as num?)?.toInt() ?? 0;
      switch (_txFilter) {
        case 1:
          return delta >= 0;
        case 2:
          return delta < 0;
        case 3:
          return kind == 'gift';
        case 4:
          return kind == 'reward' || kind == 'chest' || kind == 'mission';
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      maxChildSize: 0.97,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
                  : _error != null
                      ? _buildError()
                      : RefreshIndicator(
                          color: const Color(0xFF8B5CF6),
                          onRefresh: _load,
                          child: ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                            children: [
                              _buildHeader(),
                              const SizedBox(height: 14),
                              _buildPremiumCard(),
                              const SizedBox(height: 22),
                              _buildTaskHeader(),
                              const SizedBox(height: 10),
                              _buildDailyTasks(),
                              const SizedBox(height: 24),
                              _sectionTitle(
                                  Icons.grid_view_rounded, 'Moedas'),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  for (final c in _currencies)
                                    _currencyCard(context, c, _wallet),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _sectionTitle(
                                  Icons.receipt_long_rounded, 'Extrato'),
                              _buildTxFilters(),
                              if (_filteredTx.isEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 20),
                                  child: Center(
                                    child: Text(
                                      _tx.isEmpty
                                          ? 'Sem movimentações ainda.'
                                          : 'Nada por aqui nesse filtro.',
                                      style:
                                          const TextStyle(color: Colors.white38),
                                    ),
                                  ),
                                )
                              else
                                ..._filteredTx
                                    .map((t) => _txTile(t, _currencies)),
                            ],
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Topo
  // ---------------------------------------------------------------------------
  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF170F26), Color(0xFF6D28D9)],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
            ),
          ),
          child: const Icon(
            Icons.account_balance_wallet_rounded,
            color: Color(0xFFFFD700),
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Carteira',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'Seu saldo real',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
        const Spacer(),
        _glassPill('🪙 ${_fmt(_credits)}', const Color(0xFFFFD700)),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => ConversionScreen.show(context),
          tooltip: 'Converter moedas',
          style: IconButton.styleFrom(
            backgroundColor: const Color(0x228B5CF6),
            side: BorderSide(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
            ),
          ),
          icon: const Icon(Icons.swap_horiz_rounded,
              color: Color(0xFF8B5CF6), size: 20),
        ),
      ],
    );
  }

  Widget _glassPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Card principal do saldo
  // ---------------------------------------------------------------------------
  /// Card do saldo — limpo e compacto (preto/grafite + roxo neon + dourado só
  /// p/ moedas), sem glass-blur nem adornos decorativos. Valores reais do
  /// backend e ações reais: Obter moedas → Loja, Converter → conversão.
  Widget _buildPremiumCard() {
    final brl = _brlEstimate;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF211447),
            Color(0xFF161130),
            Color(0xFF0E1124),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.workspace_premium_rounded,
                  color: Color(0xFFFFD700), size: 16),
              SizedBox(width: 6),
              Text(
                'CARTEIRA KLAY K',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFD700), Color(0xFFFF8A00)],
                  ),
                ),
                child: const Icon(Icons.monetization_on_rounded,
                    color: Color(0xFF1A1205), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _fmt(_credits),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const Text(
                      'Saldo em Moedas',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (brl != null) ...[
            const SizedBox(height: 10),
            Text(
              '≈ R\$ ${brl.toStringAsFixed(2)} (saldo estimado p/ resgate)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _GradientActionButton(
                  label: 'Obter moedas',
                  icon: Icons.add_rounded,
                  gradient: const [Color(0xFF8B5CF6), Color(0xFF38BDF8)],
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const StoreScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GradientActionButton(
                  label: 'Converter',
                  icon: Icons.swap_horiz_rounded,
                  gold: true,
                  onPressed: () => ConversionScreen.show(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tarefas diárias
  // ---------------------------------------------------------------------------
  Widget _buildTaskHeader() {
    return const Row(
      children: [
        Icon(Icons.bolt_rounded, color: Color(0xFFFFD700), size: 18),
        SizedBox(width: 6),
        Text(
          'Tarefas diárias',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildDailyTasks() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _DailyTaskCard(
                icon: Icons.card_giftcard_rounded,
                iconColor: const Color(0xFFFFD700),
                title: 'Bônus Diário',
                subtitle: 'Abra seu baú grátis',
                reward: '+recompensas',
                loading: _claimingChest,
                onPressed: _claimChest,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DailyTaskCard(
                icon: Icons.play_circle_fill_rounded,
                iconColor: const Color(0xFF38BDF8),
                title: 'Recompensa assistida',
                subtitle: 'A cada 20s de vídeo',
                reward: '+15 moedas',
                loading: _claimingWatch,
                onPressed: _claimWatch,
              ),
            ),
          ],
        ),
        if (_dailyMissions.isNotEmpty) ...[
          const SizedBox(height: 10),
          ..._dailyMissions.map((m) => _MissionTaskTile(m)),
        ],
      ],
    );
  }

  Future<void> _claimChest() async {
    if (_claimingChest) return;
    setState(() => _claimingChest = true);
    try {
      final res = await _admin.claimDailyChest();
      if (!mounted) return;
      final daily = res['daily'];
      final status = daily is Map ? daily['status']?.toString() : '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status == 'unlocked' || status == 'opened'
            ? 'Baú diário liberado! Abra na aba de presentes.'
            : 'Baú diário indisponível agora.'),
      ));
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível reclamar o baú.')));
    } finally {
      if (mounted) setState(() => _claimingChest = false);
    }
  }

  Future<void> _claimWatch() async {
    if (_claimingWatch) return;
    setState(() => _claimingWatch = true);
    try {
      final res = await RewardService.instance.claimWatchCycleReward();
      if (!mounted) return;
      if (res.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('+${res.reward} moedas no saldo real!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res.error ?? 'Recompensa ainda em cooldown.')));
      }
      _load();
    } finally {
      if (mounted) setState(() => _claimingWatch = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Seções / moedas / extrato
  // ---------------------------------------------------------------------------
  Widget _sectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF8B5CF6), size: 18),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  /// Chips de categoria do extrato (filtro só de apresentação).
  Widget _buildTxFilters() {
    const filters = [
      'Tudo',
      'Entradas',
      'Saídas',
      'Presentes',
      'Recompensas',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Row(
        children: List.generate(filters.length, (i) {
          final sel = _txFilter == i;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                filters[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : Colors.white60,
                ),
              ),
              selected: sel,
              onSelected: (_) => setState(() => _txFilter = i),
              backgroundColor: const Color(0xFF17141F),
              selectedColor: const Color(0xFF6D28D9),
              checkmarkColor: Colors.white,
              side: BorderSide(
                color: sel
                    ? const Color(0xFF8B5CF6)
                    : Colors.white.withValues(alpha: 0.12),
              ),
              labelPadding: const EdgeInsets.symmetric(horizontal: 10),
              visualDensity: VisualDensity.compact,
            ),
          );
        }),
      ),
    );
  }

  Widget _currencyCard(
      BuildContext context, Map<String, dynamic> currency, Map<String, dynamic> wallet) {
    final width = (MediaQuery.of(context).size.width - 42) / 2;
    final id = currency['id']?.toString() ?? '';
    final emoji = currency['emoji']?.toString() ?? '🪙';
    final color = _parseColor(currency['color']?.toString());
    final value = wallet[id] ?? 0;
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF1B1A26), color.withValues(alpha: 0.12)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const Spacer(),
              if (currency['is_premium'] == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'rare',
                    style: TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 9,
                        fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _fmt(value),
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            currency['name']?.toString() ?? id,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _txTile(Map<String, dynamic> t, List<Map<String, dynamic>> currencies) {
    final kind = t['kind']?.toString() ?? 'grant';
    final delta = (t['delta'] as num?)?.toInt() ?? 0;
    final gain = delta >= 0;
    final cur = t['currency']?.toString() ?? 'credits';
    final label = _kindLabel(kind);
    final curColor = _currencyColor(cur, currencies);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: (gain ? curColor : const Color(0xFFFF6B81))
              .withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          gain ? Icons.add_rounded : Icons.remove_rounded,
          color: gain ? curColor : const Color(0xFFFF6B81),
          size: 18,
        ),
      ),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      subtitle: Text(
        _trim(t['note']?.toString()),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: Text(
          '${gain ? '+' : ''}$delta $cur',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            color: gain ? curColor : const Color(0xFFFF6B81),
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: Colors.white38, size: 32),
            const SizedBox(height: 10),
            const Text(
              'Não foi possível carregar a carteira.',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _load,
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Color _currencyColor(String id, List<Map<String, dynamic>> currencies) {
    for (final c in currencies) {
      if (c['id']?.toString() == id) {
        return _parseColor(c['color']?.toString());
      }
    }
    return const Color(0xFFF59E0B);
  }

  String _trim(String? s) =>
      (s ?? '').replaceAll(RegExp(r'\s+'), ' ').trim().isEmpty
          ? '—'
          : s!.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _kindLabel(String kind) {
    const labels = {
      'grant': 'Crédito',
      'spend': 'Gasto',
      'refund': 'Reembolso',
      'admin': 'Administração',
      'reward': 'Recompensa',
      'chest': 'Baú',
      'mission': 'Missão',
      'gift': 'Presente',
    };
    return labels[kind] ?? kind;
  }

  String _fmt(Object? v) {
    final n = (v is num ? v : 0).toDouble();
    if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}k';
    return n == n.truncateToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
  }

  Color _parseColor(String? hex) {
    var h = (hex ?? '').replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16) ?? 0xFF8B5CF6;
    return Color(v);
  }
}

// ============================================================================
// Widgets reutilizáveis da carteira
// ============================================================================

/// Botão de ação com gradiente e estado de loading (razão normal e dourada).
class _GradientActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onPressed;
  final bool loading;
  final bool gold;

  const _GradientActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.gradient = const [Color(0xFF8B5CF6), Color(0xFF38BDF8)],
    this.loading = false,
    this.gold = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = gold
        ? const [Color(0xFFFFD700), Color(0xFFFF8A00)]
        : gradient;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.4),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: loading ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                else
                  Icon(icon, color: Colors.white, size: 18),
                if (loading) const SizedBox(width: 8) else const SizedBox(width: 8),
                if (!loading)
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Card pequeno de tarefa diária com ação.
class _DailyTaskCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String reward;
  final bool loading;
  final VoidCallback onPressed;

  const _DailyTaskCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.reward,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1B1A26),
            iconColor.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _GradientActionButton(
              label: reward,
              icon: Icons.bolt_rounded,
              gold: iconColor == const Color(0xFFFFD700),
              loading: loading,
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarefa de missão (progresso real do backend: `my_progress`).
class _MissionTaskTile extends StatelessWidget {
  final Map<String, dynamic> m;

  const _MissionTaskTile(this.m);

  @override
  Widget build(BuildContext context) {
    final title = m['title']?.toString() ?? 'Tarefa';
    final icon = m['icon']?.toString() ?? '📋';
    final target = (m['target'] as num?)?.toInt() ?? 1;
    final progress = (m['progress'] as num?)?.toInt() ?? 0;
    final completed = m['completed'] == true;
    final ratio = (progress / target).clamp(0.0, 1.0);

    final rewardsMap = m['rewards'];
    String rewardLabel = 'XP';
    if (rewardsMap is Map && rewardsMap.isNotEmpty) {
      final entries = rewardsMap.entries.map((e) => '${e.value} ${e.key}').join(' + ');
      if (entries.isNotEmpty) rewardLabel = entries;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF161420),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (completed ? const Color(0xFF34D399) : const Color(0xFF8B5CF6))
              .withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  completed ? '✓ $title' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: completed ? const Color(0xFF34D399) : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 5,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      completed
                          ? const Color(0xFF34D399)
                          : const Color(0xFF8B5CF6),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  completed ? 'Concluída' : 'Recompensa: $rewardLabel',
                  style: TextStyle(
                    color: completed ? Colors.white54 : Colors.white38,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
