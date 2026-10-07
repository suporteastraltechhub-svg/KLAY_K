import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/store_models.dart';
import '../services/store_service.dart';
import '../services/supabase_service.dart';

const Color _kAccent = Color(0xFF8B5CF6);

/// Pedidos da Loja: aba "Compras" (o que comprei) e "Vendas" (pedidos dos
/// meus produtos). O vendedor atualiza o status; o comprador cancela pedidos
/// pendentes. Tudo via RPC com validação no backend.
class StoreOrdersScreen extends StatefulWidget {
  const StoreOrdersScreen({super.key});

  @override
  State<StoreOrdersScreen> createState() => _StoreOrdersScreenState();
}

class _StoreOrdersScreenState extends State<StoreOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  List<StoreOrder> _orders = [];
  Map<String, List<StoreOrderItem>> _items = {};
  bool _loading = true;
  String? _meId;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = SupabaseService.instance.client.auth.currentUser?.id ?? '';
      final orders = await StoreService.instance.fetchOrders();
      final itemsMap = <String, List<StoreOrderItem>>{};
      for (final o in orders) {
        itemsMap[o.id] = await StoreService.instance.fetchOrderItems(o.id);
      }
      if (!mounted) return;
      setState(() {
        _meId = me;
        _orders = orders;
        _items = itemsMap;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<StoreOrder> get _bought =>
      _orders.where((o) => o.userId == _meId).toList();
  List<StoreOrder> get _sold =>
      _orders.where((o) => o.sellerId == _meId).toList();

  Future<void> _setStatus(StoreOrder o, String status) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await StoreService.instance.updateOrderStatus(o.id, status);
      _load();
    } catch (e) {
      _snack(l10n.storeErrorGeneric(e));
    }
  }

  Future<void> _cancel(StoreOrder o) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await StoreService.instance.cancelOrder(o.id);
      _load();
    } catch (e) {
      _snack(l10n.storeErrorGeneric(e));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0C16),
        title: Text(
          l10n.ordersTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: _kAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: [
            Tab(text: l10n.ordersTabBought),
            Tab(text: l10n.ordersTabSold),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : TabBarView(
              controller: _tab,
              children: [
                _list(l10n, _bought, isSold: false),
                _list(l10n, _sold, isSold: true),
              ],
            ),
    );
  }

  Widget _list(
    AppLocalizations l10n,
    List<StoreOrder> list, {
    required bool isSold,
  }) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSold ? Icons.storefront_outlined : Icons.receipt_long_outlined,
              color: Colors.white24,
              size: 52,
            ),
            const SizedBox(height: 12),
            Text(
              isSold ? l10n.ordersNoSales : l10n.ordersNoPurchases,
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _kAccent,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        itemBuilder: (context, i) => _orderCard(l10n, list[i], isSold: isSold),
      ),
    );
  }

  Widget _orderCard(
    AppLocalizations l10n,
    StoreOrder o, {
    required bool isSold,
  }) {
    final items = _items[o.id] ?? const <StoreOrderItem>[];
    final otherName = o.buyerDisplayName.isNotEmpty
        ? o.buyerDisplayName
        : o.buyerUsername.isNotEmpty
        ? '@${o.buyerUsername}'
        : '';
    final sellerName = o.sellerDisplayName.isNotEmpty
        ? o.sellerDisplayName
        : o.sellerUsername.isNotEmpty
        ? '@${o.sellerUsername}'
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusChip(l10n, o.status),
              const Spacer(),
              Text(
                _dateLabel(l10n, o.createdAt),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map(
            (it) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${it.quantity}× ${it.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  Text(
                    formatPrice(it.unitPrice * it.quantity),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Color(0xFF2A2740), height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  isSold
                      ? l10n.orderBuyerLabel(
                          otherName.isEmpty
                              ? o.userId.substring(0, 8)
                              : otherName,
                        )
                      : l10n.orderSellerLabel(
                          sellerName.isEmpty
                              ? o.sellerId.substring(0, 8)
                              : sellerName,
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const Spacer(),
              Text(
                l10n.ordersTotalPrefix(formatPrice(o.total)),
                style: const TextStyle(
                  color: _kAccent,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (isSold && _statusActions(o).isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: _statusActions(o)
                  .map(
                    (s) => OutlinedButton(
                      onPressed: () => _setStatus(o, s),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: _kAccent),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(_statusLabel(l10n, s)),
                    ),
                  )
                  .toList(),
            ),
          ] else if (o.cancellable) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _confirmCancel(l10n, o),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: Text(l10n.cancelOrderButton),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<String> _statusActions(StoreOrder o) {
    const flow = ['pendente', 'pago', 'enviado', 'concluido'];
    final idx = flow.indexOf(o.status);
    if (idx == -1) return [];
    final next = idx + 1 < flow.length ? flow[idx + 1] : null;
    final out = <String>[];
    if (o.status == 'concluido' || o.status == 'cancelado') return [];
    if (next != null) out.add(next);
    if (o.status == 'pendente') out.add('cancelado');
    return out;
  }

  Future<void> _confirmCancel(AppLocalizations l10n, StoreOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17151F),
        title: Text(
          l10n.cancelOrderTitle,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          l10n.cancelOrderBody,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.back,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
    if (ok == true) _cancel(o);
  }

  Widget _statusChip(AppLocalizations l10n, String status) {
    final color = switch (status) {
      'concluido' => const Color(0xFF4CAF50),
      'cancelado' => Colors.redAccent,
      'enviado' => Colors.orange,
      'pago' => Colors.lightBlueAccent,
      _ => Colors.amber,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabel(l10n, status),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  String _statusLabel(AppLocalizations l10n, String status) => switch (status) {
    'pendente' => l10n.orderStatusPending,
    'pago' => l10n.orderStatusPaid,
    'enviado' => l10n.orderStatusShipped,
    'concluido' => l10n.orderStatusCompleted,
    'cancelado' => l10n.orderStatusCancelled,
    _ => status,
  };

  String _dateLabel(AppLocalizations l10n, DateTime d) {
    final n = DateTime.now();
    if (d.year == n.year && d.month == n.month && d.day == n.day) {
      final h = d.hour.toString().padLeft(2, '0');
      final m = d.minute.toString().padLeft(2, '0');
      return '${l10n.todayLabel} $h:$m';
    }
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}
