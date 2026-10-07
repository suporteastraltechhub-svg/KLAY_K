import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/admin_service.dart';
import '../services/supabase_service.dart';

/// 🎁 Baús do KLAY K: coletar o baú diário, abrir baús desbloqueados e ver o
/// histórico. As rolagens e o credito são 100% no backend (security definer):
/// aqui o app só chama `claim_daily_chest()`/`open_chest()` e exibe o resultado.
class ChestsScreen extends StatefulWidget {
  const ChestsScreen({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12101A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const ChestsScreen(),
    );
  }

  @override
  State<ChestsScreen> createState() => _ChestsScreenState();
}

class _ChestsScreenState extends State<ChestsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _mine = [];
  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _opens = [];
  Map<String, dynamic> _daily = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!SupabaseService.instance.isConfigured) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = AppLocalizations.of(context)!.chestsDemoMode;
        });
      }
      return;
    }
    final a = AdminService.instance;
    try {
      final mine = await a.myChests();
      final catalog = await a.chestCatalog();
      final opens = await a.myChestOpens(limit: 15);
      Map<String, dynamic> daily = const {};
      // Baú diário: a última linha por user/chest/source 'daily' diz se coletei hoje.
      for (final c in mine) {
        if (c['chest_id'] == 'diario' && c['source'] == 'daily') {
          daily = c;
        }
      }
      if (mounted) {
        setState(() {
          _mine = mine;
          _catalog = catalog;
          _opens = opens;
          _daily = daily;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  bool get _collectedToday {
    final obtained = _daily['obtained_at']?.toString();
    if (obtained == null) return false;
    final d = DateTime.tryParse(obtained)?.toUtc();
    if (d == null) return false;
    final now = DateTime.now().toUtc();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  Future<void> _claimDaily() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final res = await AdminService.instance.claimDailyChest();
      _toast(
        res['daily'] != null
            ? l10n.dailyChestCollectedToast
            : l10n.dailyChestAlreadyCollected,
      );
      await _load();
    } catch (e) {
      _toast(AdminService.instance.friendlyError(e), error: true);
    }
  }

  Future<void> _openChest(Map<String, dynamic> chest) async {
    final l10n = AppLocalizations.of(context)!;
    final id = chest['id']?.toString();
    if (id == null) return;
    try {
      final res = await AdminService.instance.openChest(id);
      final drops = res['drops'];
      if (drops is List && drops.isNotEmpty) {
        final parts = drops
            .map<String>(
              (d) =>
                  '${d is Map ? d['item_type'] ?? '?' : '?'} +${d is Map ? d['amount'] ?? 0 : 0}',
            )
            .toList();
        _toast(l10n.chestOpenedRewards(parts.join(', ')));
      } else {
        _toast(l10n.chestOpenedToast);
      }
      await _load();
    } catch (e) {
      _toast(AdminService.instance.friendlyError(e), error: true);
      await _load();
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error
            ? const Color(0xFFE4183C)
            : const Color(0xFF0F8A4D),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        final l10n = AppLocalizations.of(context)!;
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(
                '🎁 ${l10n.chests}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  : _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF8B5CF6),
                      ),
                    )
                  : RefreshIndicator(
                      color: const Color(0xFF8B5CF6),
                      onRefresh: _load,
                      child: ListView(
                        controller: scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
                        children: [
                          _dailyCard(),
                          const SizedBox(height: 14),
                          _sectionTitle(l10n.myChestsTitle),
                          const SizedBox(height: 8),
                          if (_mine.isEmpty)
                            _emptyText(l10n.noChestsYet)
                          else
                            ..._mine.map(_chestTile),
                          const SizedBox(height: 14),
                          _sectionTitle(l10n.catalogLabel),
                          const SizedBox(height: 8),
                          if (_catalog.isEmpty)
                            _emptyText(l10n.noChestsAvailable)
                          else
                            ..._catalog.map(_catalogTile),
                          const SizedBox(height: 14),
                          _sectionTitle(l10n.chestOpensHistory),
                          const SizedBox(height: 8),
                          if (_opens.isEmpty)
                            _emptyText(l10n.noChestOpens)
                          else
                            ..._opens.map(_openTile),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w800,
    ),
  );

  Widget _emptyText(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Center(
      child: Text(text, style: const TextStyle(color: Colors.white38)),
    ),
  );

  Widget _dailyCard() {
    final l10n = AppLocalizations.of(context)!;
    final collected = _collectedToday;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1B54), Color(0xFF151126)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          const Text('📦', style: TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.dailyChestTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  collected
                      ? l10n.dailyChestCollectedHint
                      : l10n.dailyChestHint,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: collected ? null : _claimDaily,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            child: Text(collected ? l10n.collectedLabel : l10n.collectLabel),
          ),
        ],
      ),
    );
  }

  Widget _chestTile(Map<String, dynamic> c) {
    final l10n = AppLocalizations.of(context)!;
    final status = c['status']?.toString() ?? 'unlocked';
    final unlocked = status == 'unlocked';
    String label;
    switch (status) {
      case 'opened':
        label = l10n.chestStatusOpened;
        break;
      case 'locked':
        label = l10n.blockedSuffix;
        break;
      default:
        label = l10n.chestStatusReady;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const Text('📦', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c['chest_id'] ?? '—'} (${c['source'] ?? ''})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: unlocked
                        ? const Color(0xFF34D399)
                        : const Color(0xFFB794FF),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (unlocked)
            FilledButton(
              onPressed: () => _openChest(c),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text(l10n.openAction),
            ),
        ],
      ),
    );
  }

  Widget _catalogTile(Map<String, dynamic> c) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Text(
        c['emoji']?.toString() ?? '📦',
        style: const TextStyle(fontSize: 18),
      ),
      title: Text(
        c['name']?.toString() ?? c['id']?.toString() ?? '—',
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      subtitle: Text(
        c['description']?.toString() ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
    );
  }

  Widget _openTile(Map<String, dynamic> o) {
    final l10n = AppLocalizations.of(context)!;
    final drops = (o['drops'] as List?) ?? const [];
    String summary;
    if (drops.isEmpty) {
      summary = l10n.emptyReward;
    } else {
      summary = drops
          .map<String>(
            (d) =>
                '${d is Map ? d['item_type'] ?? '?' : '?'} +${d is Map ? d['amount'] ?? 0 : 0}',
          )
          .join(', ');
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_open_rounded,
            color: Color(0xFF34D399),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${o['chest_id'] ?? '—'} · $summary',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Text(
            _daysAgo(o['opened_at']?.toString(), l10n),
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }

  String _daysAgo(String? iso, AppLocalizations l10n) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return l10n.justNow;
    if (diff.inHours < 1) return l10n.msTimeMin(diff.inMinutes);
    if (diff.inDays < 1) return l10n.msTimeH(diff.inHours);
    return l10n.msTimeD(diff.inDays);
  }
}
