import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/shop_models.dart';
import '../services/finance_service.dart';
import '../services/shop_service.dart';
import 'finance_wallet_screen.dart';
import '../widgets/klay_live_widgets.dart';

/// Loja virtual do KLAY K.
///
/// Tema preto + roxo neon (mesma identidade da Sala de Live). Todos os valores
/// exibidos vêm do backend: catálogo (`shop_items`), inventário (`user_items`),
/// equipados (`user_equipped`) e saldos por moeda (`my_wallet`). A compra é
/// sempre atômica e decidida no backend (`shop_buy_item`) com idempotência por
/// `request_id`; o "Comprar" da aba Moedas abre a carteira financeira real
/// (compra de créditos com pagamento).
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  static Future<T?> show<T>(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ShopScreen()));
  }

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen>
    with SingleTickerProviderStateMixin {
  final ShopService _shop = ShopService.instance;
  final FinanceService _finance = FinanceService.instance;

  late final TabController _tab;
  Map<String, dynamic> _wallet = const {};
  List<Map<String, dynamic>> _packages = const [];
  List<ShopItem> _catalog = const [];
  Set<String> _myItems = const {};
  Map<String, String> _equipped = const {};
  bool _loading = true;
  String? _error;
  String? _busyItemId;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _shop.fetchWallet(),
        _shop.fetchCatalog(),
        _shop.fetchMyItems(),
        _shop.fetchEquipped(),
        _finance.catalog(),
      ]);
      if (!mounted) return;
      final wallet = (results[0] is Map)
          ? Map<String, dynamic>.from(results[0] as Map)
          : const <String, dynamic>{};
      final catalog = (results[1] as List<ShopItem>? ?? const <ShopItem>[]);
      final mine = (results[2] as List<ShopItem>? ?? const <ShopItem>[])
          .map((e) => e.id)
          .toSet();
      final equipped = (results[3] is Map)
          ? (results[3] as Map).map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            )
          : const <String, String>{};
      final packs = (results[4] is List)
          ? (results[4] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : const <Map<String, dynamic>>[];
      setState(() {
        _wallet = wallet;
        _catalog = catalog;
        _myItems = mine;
        _equipped = equipped;
        _packages = packs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // -------------------------------------------------------------------------
  // Saldo por moeda
  // -------------------------------------------------------------------------
  int _balance(ShopCurrency c) => (_wallet[c.walletKey] as num?)?.toInt() ?? 0;

  List<ShopCurrency> _currenciesInUse() {
    final list = <ShopCurrency>[];
    for (final c in ShopCurrency.values) {
      if (_balance(c) > 0) list.add(c);
    }
    return list;
  }

  // -------------------------------------------------------------------------
  // Compra (idempotente, com retry em duplicate_in_progress)
  // -------------------------------------------------------------------------
  Future<void> _buy(ShopItem item, AppLocalizations l10n) async {
    if (_busyItemId != null) return;
    final balance = _balance(item.priceCurrency);
    if (balance < item.priceUnits) {
      _toast(l10n.shopInsufficient);
      return;
    }
    setState(() => _busyItemId = item.id);
    try {
      var ok = false;
      for (var attempt = 0; attempt < 2 && !ok; attempt++) {
        final requestId =
            'sh_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
        try {
          final res = await _shop.buyItem(item, requestId: requestId);
          if (!mounted) return;
          if (res.duplicate) {
            _toast(l10n.shopPurchaseDuplicate);
          } else {
            _toast(l10n.shopPurchaseSuccess);
          }
          // Saldo e inventário mudaram — reconsulta honesta do backend.
          await _reloadDynamic();
          ok = true;
        } on ShopDuplicateInProgressException {
          // Mesmo requestId sendo processado: troca de id e tenta de novo.
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      if (!ok && mounted) {
        _toast(l10n.shopPurchaseBusy);
        await _reloadDynamic();
      }
    } catch (e) {
      if (!mounted) return;
      _toast(_friendly(e, l10n.shopBuyError));
      await _reloadDynamic();
    } finally {
      if (mounted) setState(() => _busyItemId = null);
    }
  }

  Future<void> _equip(ShopItem item, AppLocalizations l10n) async {
    if (_busyItemId != null) return;
    final slot = item.slot;
    if (slot == null) return;
    setState(() => _busyItemId = item.id);
    try {
      await _shop.equip(item);
      if (!mounted) return;
      _toast(l10n.shopEquip);
      await _reloadDynamic();
    } catch (e) {
      if (!mounted) return;
      _toast(_friendly(e, l10n.shopEquipError));
    } finally {
      if (mounted) setState(() => _busyItemId = null);
    }
  }

  Future<void> _unequip(String slot, AppLocalizations l10n) async {
    if (_busyItemId != null) return;
    setState(() => _busyItemId = slot);
    try {
      await _shop.unequip(slot);
      if (!mounted) return;
      _toast(l10n.shopUnequip);
      await _reloadDynamic();
    } catch (e) {
      if (!mounted) return;
      _toast(_friendly(e, l10n.shopUnequipError));
    } finally {
      if (mounted) setState(() => _busyItemId = null);
    }
  }

  Future<void> _reloadDynamic() async {
    try {
      final results = await Future.wait([
        _shop.fetchWallet(),
        _shop.fetchMyItems(),
        _shop.fetchEquipped(),
      ]);
      if (!mounted) return;
      setState(() {
        if (results[0] is Map) {
          _wallet = Map<String, dynamic>.from(results[0] as Map);
        }
        _myItems = (results[1] as List<ShopItem>? ?? const [])
            .map((e) => e.id)
            .toSet();
        if (results[2] is Map) {
          _equipped = (results[2] as Map).map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
        }
      });
    } catch (_) {
      // Erros de refresh são não fatais; o próximo load da tela re-sincroniza.
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Erro amigável: reconhece falhas específicas do backend (saldo insuficiente,
  /// item inexistente…); sem falha reconhecida usa a tradução da tela.
  String _friendly(Object? e, String fallback) {
    final f = FinanceService.friendlyError(e);
    const genericPT = 'Não foi possível concluir. Tente novamente.';
    if (f.isEmpty || f == genericPT) return fallback;
    return f;
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: kkBg,
      appBar: AppBar(
        backgroundColor: kkBg,
        elevation: 0,
        title: Text(
          l10n.shopTitle,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _header(l10n),
          _tabs(l10n),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _coinsTab(l10n),
                _cosmeticsTab(l10n),
                _boostsTab(l10n),
                _communityTab(l10n),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(AppLocalizations l10n) {
    final chips = _currenciesInUse();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF211447), Color(0xFF161130), Color(0xFF0E1124)],
        ),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront_rounded, color: kkNeon, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.shopWalletLabel.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                if (chips.isEmpty)
                  const Text(
                    '—',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final c in chips)
                        _currencyChip(c, _balance(c), l10n),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _currencyChip(ShopCurrency c, int value, AppLocalizations l10n) {
    final label = switch (c) {
      ShopCurrency.credits => l10n.shopWalletCredits,
      ShopCurrency.diamonds => l10n.shopWalletDiamonds,
      ShopCurrency.crystals => l10n.shopWalletCrystals,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c == ShopCurrency.credits
            ? const Color(0xFFFFD700).withValues(alpha: 0.12)
            : kkAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              (c == ShopCurrency.credits ? const Color(0xFFFFD700) : kkAccent)
                  .withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        '${c.emoji} ${_fmt(value)} $label',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _tabs(AppLocalizations l10n) {
    return Container(
      color: const Color(0xFF12101A),
      child: TabBar(
        controller: _tab,
        labelColor: kkNeon,
        unselectedLabelColor: Colors.white54,
        indicatorColor: kkNeon,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.white10,
        tabs: [
          Tab(text: l10n.shopTabCoins),
          Tab(text: l10n.shopTabCosmetics),
          Tab(text: l10n.shopTabBoosts),
          Tab(text: l10n.shopTabCommunity),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Aba Moedas (créditos reais → carteira financeira)
  // -------------------------------------------------------------------------
  Widget _coinsTab(AppLocalizations l10n) {
    if (_loading) return _loader();
    final packs = _packages;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1A26),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kkNeon.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Text('💳', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.shopCoinsHint,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (packs.isEmpty)
          _empty(l10n.shopNoItems)
        else ...[
          const SizedBox(height: 6),
          for (final p in packs) _packageTile(p, l10n),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () => FinanceWalletScreen.show(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF8B5CF6),
              side: const BorderSide(color: Color(0xFF8B5CF6)),
            ),
            icon: const Icon(Icons.workspace_premium_rounded, size: 18),
            label: Text(l10n.shopOpenFinance),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _packageTile(Map<String, dynamic> p, AppLocalizations l10n) {
    final emoji = p['emoji']?.toString() ?? '🪙';
    final name = p['name']?.toString() ?? '';
    final credits = (p['credits_amount'] as num?)?.toInt() ?? 0;
    final priceCents = (p['price_cents'] as num?)?.toDouble() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '+ $credits credits',
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _brl(priceCents),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: FilledButton(
              onPressed: () => FinanceWalletScreen.show(context),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text(l10n.shopBuy),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Aba Cosméticos (frames / entrada / badges)
  // -------------------------------------------------------------------------
  Widget _cosmeticsTab(AppLocalizations l10n) {
    if (_loading) return _loader();
    final frames = _byKind(ShopItemKind.frame);
    final entries = _byKind(ShopItemKind.entryEffect);
    final badges = _byKind(ShopItemKind.badge);
    if (frames.isEmpty && entries.isEmpty && badges.isEmpty) {
      return _empty(l10n.shopNoItems);
    }
    return RefreshIndicator(
      color: kkNeon,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (frames.isNotEmpty) _section(l10n.shopSlotFrame, frames, l10n),
          if (entries.isNotEmpty) _section(l10n.shopSlotEntry, entries, l10n),
          if (badges.isNotEmpty) _section(l10n.shopSlotBadge, badges, l10n),
        ],
      ),
    );
  }

  Widget _section(String title, List<ShopItem> items, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisExtent: 210,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => _itemCard(items[i], l10n),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _itemCard(ShopItem item, AppLocalizations l10n) {
    final rarityColor = _rarityColor(item.rarity);
    final equipped = item.slot != null && _equipped[item.slot] == item.id;
    final owned = _myItems.contains(item.id);
    final affordable = _balance(item.priceCurrency) >= item.priceUnits;
    final busy = _busyItemId == item.id || _busyItemId == item.slot;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: equipped ? kkNeon : rarityColor.withValues(alpha: 0.45),
          width: equipped ? 1.6 : 1,
        ),
        boxShadow: equipped
            ? [BoxShadow(color: kkNeon.withValues(alpha: 0.25), blurRadius: 14)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kkAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(item.icon, style: const TextStyle(fontSize: 22)),
              ),
              const Spacer(),
              if (equipped)
                _pill(l10n.shopEquipped, kkNeon)
              else if (owned)
                _pill(l10n.shopOwned, rarityColor),
            ],
          ),
          const SizedBox(height: 10),
          _rarityTag(item.rarity, rarityColor),
          const SizedBox(height: 4),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              item.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${item.priceCurrency.emoji} ${_fmt(item.priceUnits)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _buildAction(
                item,
                l10n,
                busy: busy,
                equipped: equipped,
                owned: owned,
                affordable: affordable,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAction(
    ShopItem item,
    AppLocalizations l10n, {
    required bool busy,
    required bool equipped,
    required bool owned,
    required bool affordable,
  }) {
    if (busy) {
      return const SizedBox(
        width: 30,
        height: 30,
        child: CircularProgressIndicator(strokeWidth: 2, color: kkNeon),
      );
    }
    final equippable = item.equippable;
    if (equipped) {
      return IconButton(
        onPressed: () => _unequip(item.slot!, l10n),
        icon: const Icon(
          Icons.remove_circle_outline_rounded,
          color: Colors.white54,
          size: 20,
        ),
        tooltip: l10n.shopUnequip,
      );
    }
    if (owned && equippable) {
      return SizedBox(
        height: 32,
        child: FilledButton(
          onPressed: () => _equip(item, l10n),
          style: FilledButton.styleFrom(
            backgroundColor: kkNeon,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: Text(l10n.shopEquip),
        ),
      );
    }
    if (!owned && !affordable) {
      return const Icon(
        Icons.lock_rounded,
        color: Colors.white24,
        size: 18,
        semanticLabel: '',
      );
    }
    return SizedBox(
      height: 32,
      child: FilledButton(
        onPressed: () => _buy(item, l10n),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF8B5CF6),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
        child: Text(l10n.shopBuy),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Abas Boosts + Comunidade (itens de posse)
  // -------------------------------------------------------------------------
  Widget _boostsTab(AppLocalizations l10n) =>
      _possessionTab(ShopItemKind.boost, l10n);

  Widget _communityTab(AppLocalizations l10n) =>
      _possessionTab(ShopItemKind.community, l10n);

  Widget _possessionTab(ShopItemKind kind, AppLocalizations l10n) {
    if (_loading) return _loader();
    final items = _byKind(kind);
    if (items.isEmpty) return _empty(l10n.shopNoItems);
    return RefreshIndicator(
      color: kkNeon,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [for (final i in items) _rowCard(i, l10n)],
      ),
    );
  }

  Widget _rowCard(ShopItem item, AppLocalizations l10n) {
    final rarityColor = _rarityColor(item.rarity);
    final owned = _myItems.contains(item.id);
    final affordable = _balance(item.priceCurrency) >= item.priceUnits;
    final busy = _busyItemId == item.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: rarityColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kkAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(item.icon, style: const TextStyle(fontSize: 24)),
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
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _rarityTag(item.rarity, rarityColor),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.description.isEmpty ? item.id : item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${item.priceCurrency.emoji} ${_fmt(item.priceUnits)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (owned)
                      Text(
                        '✓ ${l10n.shopOwned}',
                        style: TextStyle(
                          color: rarityColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: kkNeon),
            )
          else if (owned)
            const Icon(Icons.check_circle_rounded, color: kkNeon, size: 24)
          else if (!affordable)
            const Icon(Icons.lock_rounded, color: Colors.white24, size: 20)
          else
            SizedBox(
              height: 34,
              child: FilledButton(
                onPressed: () => _buy(item, l10n),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(l10n.shopBuy),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Helpers de UI
  // -------------------------------------------------------------------------
  List<ShopItem> _byKind(ShopItemKind kind) {
    if (_error != null || _catalog.isEmpty) return const [];
    return _catalog.where((e) => e.kind == kind).toList();
  }

  Widget _loader() =>
      const Center(child: CircularProgressIndicator(color: kkNeon));

  Widget _empty(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🛍️', style: TextStyle(fontSize: 42)),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
          if (_error != null && _error!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
          const SizedBox(height: 14),
          IconButton(
            tooltip: 'retry',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, color: kkNeon),
          ),
        ],
      ),
    ),
  );

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
    ),
  );

  Widget _rarityTag(String rarity, Color color) => Text(
    rarity.toUpperCase(),
    style: TextStyle(
      color: color,
      fontSize: 9,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.8,
    ),
  );

  Color _rarityColor(String rarity) {
    switch (rarity) {
      case 'comum':
        return const Color(0xFFB0BEC5);
      case 'incomum':
        return const Color(0xFF66BB6A);
      case 'especial':
        return const Color(0xFFAB47BC);
      case 'raro':
        return const Color(0xFF42A5F5);
      case 'epico':
        return const Color(0xFF7E57C2);
      case 'mitico':
        return const Color(0xFFFF7043);
      case 'lendario':
        return const Color(0xFFFFB300);
      case 'exclusivo':
        return const Color(0xFF29B6F6);
      case 'ultra':
        return const Color(0xFFD4AF37);
      default:
        return Colors.white70;
    }
  }

  String _fmt(int n) {
    if (n >= 1000) {
      final k = n / 1000;
      return '${k.toStringAsFixed(k >= 100 ? 0 : 1)}k';
    }
    return NumberFormat.decimalPattern().format(n);
  }

  String _brl(double cents) {
    final reais = cents / 100;
    if (reais == reais.roundToDouble()) {
      return 'R\$${reais.toStringAsFixed(0)},00';
    }
    return 'R\$${reais.toStringAsFixed(2).replaceAll('.', ',')}';
  }
}
