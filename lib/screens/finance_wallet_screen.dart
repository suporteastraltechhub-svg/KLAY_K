import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/admin_service.dart';
import '../services/finance_service.dart';

/// 📊 CARTEIRA FINANCEIRA CENTRAL do KLAY K (KLAY K FINANCE).
///
/// Compra de moedas virtuais por pacote, histórico financeiro com filtros
/// (Todos/Entradas/Saídas/Compras/Presentes/Reembolsos) e ganhos de criador.
/// TODOS os valores vêm do backend (RPCs `security definer`); este app nunca
/// decide preço/saldo. Se a fonte não existir, mostra "Sem dados disponíveis"
/// (nunca inventa número). Durante a confirmação de pagamento exibe o estado
/// honesto "Verificando transação..." — sem cobrança fictícia.
class FinanceWalletScreen extends StatefulWidget {
  const FinanceWalletScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FinanceWalletScreen()));
  }

  @override
  State<FinanceWalletScreen> createState() => _FinanceWalletScreenState();
}

class _FinanceWalletScreenState extends State<FinanceWalletScreen> {
  final FinanceService _finance = FinanceService.instance;
  final AdminService _admin = AdminService.instance;

  List<Map<String, dynamic>> _packages = const [];
  List<Map<String, dynamic>> _history = const [];
  Map<String, dynamic> _wallet = const {};
  Map<String, dynamic> _balance = const {};
  List<Map<String, dynamic>> _earnings = const [];

  bool _loading = true;
  bool _walletLoaded = false;
  String? _walletError;
  String? _error;
  String? _debugError;
  final List<String> _loadFailures = [];

  int _historyFilter =
      0; // 0=Todos 1=Entradas 2=Saídas 3=Compras 4=Presentes 5=Reembolsos

  String? _orderingPackageId;
  bool _requestingPayout = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _walletLoaded = false;
      _walletError = null;
      _error = null;
      _debugError = null;
      _loadFailures.clear();
    });
    try {
      final catalog = await _guard(
        'catalog',
        _finance.catalog,
        const <Map<String, dynamic>>[],
      );
      final history = await _guard(
        'history',
        () => _finance.history(limit: 60),
        const <Map<String, dynamic>>[],
      );
      final wallet = await _guard(
        'wallet',
        _admin.myWallet,
        const <String, dynamic>{},
      );
      final balance = await _guard(
        'creator_balance',
        _finance.creatorBalance,
        const <String, dynamic>{},
      );
      final earnings = await _guard(
        'creator_earnings',
        () => _finance.myCreatorEarnings(limit: 40),
        const <Map<String, dynamic>>[],
      );
      if (!mounted) return;
      final walletFailures = _loadFailures.where(
        (failure) => failure.startsWith('wallet:'),
      );
      final walletFailure = walletFailures.isEmpty
          ? null
          : walletFailures.first;
      setState(() {
        _packages = catalog;
        _history = history;
        _wallet = wallet;
        _balance = balance;
        _earnings = earnings;
        _walletLoaded = walletFailure == null;
        _walletError = walletFailure;
        _debugError = _loadFailures.isEmpty ? null : _loadFailures.join('\n');
        _error = catalog.isEmpty && wallet.isEmpty && _loadFailures.isNotEmpty
            ? FinanceService.friendlyError(_loadFailures.first)
            : null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      debugPrint('[KLayK][Finance] load falhou: $error');
      setState(() {
        _walletLoaded = false;
        _walletError = 'Falha ao ler o saldo real.';
        _error = FinanceService.friendlyError(error);
        _debugError = error.toString();
        _loading = false;
      });
    }
  }

  Future<T> _guard<T>(
    String label,
    Future<T> Function() request,
    T fallback,
  ) async {
    try {
      return await request();
    } catch (error) {
      if (kDebugMode) debugPrint('[KLayK][Finance] $label falhou: $error');
      _loadFailures.add('$label: ${error.runtimeType}');
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF12101A),
      appBar: AppBar(
        title: Text(
          l10n.financeWalletTitle,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0A0812),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: l10n.refreshLabel,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
            )
          : _error != null
          ? _buildError(l10n)
          : RefreshIndicator(
              color: const Color(0xFF8B5CF6),
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  _balanceCard(l10n),
                  const SizedBox(height: 20),
                  _sectionTitle(
                    Icons.shopping_bag_rounded,
                    l10n.financeBuyCoins,
                  ),
                  const SizedBox(height: 10),
                  if (_packages.isEmpty)
                    _emptyBox(l10n.financeNoData)
                  else
                    ..._packages.map((p) => _packageTile(p, l10n)),
                  const SizedBox(height: 22),
                  _sectionTitle(
                    Icons.emoji_events_rounded,
                    l10n.financeEarningsTitle,
                  ),
                  const SizedBox(height: 10),
                  _earningsCard(l10n),
                  const SizedBox(height: 22),
                  _sectionTitle(
                    Icons.receipt_long_rounded,
                    l10n.financeHistoryTitle,
                  ),
                  const SizedBox(height: 4),
                  _buildFilters(l10n),
                  if (_filteredHistory.isEmpty)
                    _emptyBox(l10n.financeNoData)
                  else
                    ..._filteredHistory.map((h) => _historyTile(h, l10n)),
                ],
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Saldo / pacotes
  // ---------------------------------------------------------------------------

  Widget _balanceCard(AppLocalizations l10n) {
    final credits = (_wallet['credits'] as num?)?.toInt() ?? 0;
    final walletReady = _walletLoaded;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF211447), Color(0xFF0E1124)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
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
            child: Icon(
              walletReady
                  ? Icons.monetization_on_rounded
                  : Icons.cloud_off_rounded,
              color: walletReady ? const Color(0xFF1A1205) : Colors.white54,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  walletReady ? _fmt(credits) : '—',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  walletReady
                      ? l10n.coinBalanceLabel
                      : (_walletError ?? 'Saldo real indisponível'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _packageTile(Map<String, dynamic> p, AppLocalizations l10n) {
    final id = p['id']?.toString() ?? '';
    final name = p['name']?.toString() ?? id;
    final emoji = p['emoji']?.toString() ?? '🪙';
    final credits = (p['credits_amount'] as num?)?.toInt() ?? 0;
    final priceCents = (p['price_cents'] as num?)?.toDouble() ?? 0;
    final busy = _orderingPackageId == id;
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
                  '+ $credits ${p['currency']?.toString() ?? 'credits'}',
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
              onPressed: busy ? null : () => _startPurchase(p, l10n),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(l10n.financeBuyNow),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Compra + verificação de transação
  // ---------------------------------------------------------------------------

  Future<void> _startPurchase(
    Map<String, dynamic> pkg,
    AppLocalizations l10n,
  ) async {
    final id = pkg['id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() => _orderingPackageId = id);
    try {
      final res = await _finance.createCoinOrder(
        id,
        idempotencyKey: FinanceService.newIdempotencyKey(),
      );
      if (!mounted) return;
      final orderId = res['order_id']?.toString();
      if (orderId == null || res['ok'] != true) {
        _toast(FinanceService.friendlyError(res));
        return;
      }
      await _verifyOrder(orderId, l10n);
    } catch (e) {
      if (!mounted) return;
      _toast(FinanceService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _orderingPackageId = null);
    }
  }

  Future<void> _verifyOrder(String orderId, AppLocalizations l10n) async {
    final navigator = Navigator.of(context);
    // Estado honesto: pagamento em verificação (nunca assume sucesso).
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ProcessingDialog(),
    );

    String? done;
    for (var i = 0; i < 12 && done == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      try {
        final s = await _finance.orderStatus(orderId);
        final orderStatus = s['order_status']?.toString();
        final payStatus = s['payment_status']?.toString();
        if (orderStatus == 'paid' || payStatus == 'captured') {
          done = 'paid';
        } else if (orderStatus == 'failed' || payStatus == 'failed') {
          done = 'failed';
        } else if (orderStatus == 'refunded' || payStatus == 'refunded') {
          done = 'refunded';
        }
      } catch (_) {
        // Perda de conexão durante verificação: não alarmar; segue tentando.
      }
    }

    navigator.pop(); // fecha o dialog
    await _load();

    if (done == 'paid') {
      _toast(l10n.financePaidMessage);
    } else if (done == 'failed') {
      _toast(l10n.financeFailedMessage);
    } else {
      _toast(l10n.financePendingMessage);
    }
  }

  // ---------------------------------------------------------------------------
  // Ganhos de criador
  // ---------------------------------------------------------------------------

  Widget _earningsCard(AppLocalizations l10n) {
    final available = (_balance['available_credits'] as num?)?.toInt() ?? 0;
    final pending = (_balance['pending_credits'] as num?)?.toInt() ?? 0;
    final withdrawn = (_balance['withdrawn_credits'] as num?)?.toInt() ?? 0;
    final hasEarnings =
        _balance.isNotEmpty ||
        _earnings.isNotEmpty ||
        available > 0 ||
        pending > 0 ||
        withdrawn > 0;

    if (!hasEarnings) return _emptyBox(l10n.financeNoData);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF34D399).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _statChip(
                  l10n.financeEarningsAvailable,
                  _fmt(available),
                  const Color(0xFF34D399),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statChip(
                  l10n.financeEarningsPending,
                  _fmt(pending),
                  const Color(0xFFFBBF24),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statChip(
                  l10n.financeEarningsWithdrawn,
                  _fmt(withdrawn),
                  const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
          if (available > 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: OutlinedButton.icon(
                onPressed: _requestingPayout
                    ? null
                    : () => _askPayout(l10n, available),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF34D399),
                  side: const BorderSide(color: Color(0xFF34D399)),
                ),
                icon: const Icon(Icons.output_rounded, size: 18),
                label: Text(l10n.financePayoutAction),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _askPayout(AppLocalizations l10n, int available) async {
    final controller = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          l10n.financePayoutTitle,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l10n.financePayoutHint,
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF8B5CF6)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(0),
            child: Text(
              l10n.financePayoutCancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim()) ?? 0;
              Navigator.of(ctx).pop(v);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF34D399),
            ),
            child: Text(l10n.financePayoutConfirm),
          ),
        ],
      ),
    );

    if (amount == null || amount <= 0) return;
    if (amount > available) {
      _toast(FinanceService.friendlyError('insufficient_balance'));
      return;
    }
    setState(() => _requestingPayout = true);
    try {
      final res = await _finance.requestPayout(amount);
      if (!mounted) return;
      if (res['ok'] == true) {
        _toast(l10n.financePayoutOk);
      } else {
        _toast(FinanceService.friendlyError(res));
      }
      _load();
    } catch (e) {
      if (!mounted) return;
      _toast(l10n.financePayoutFail);
    } finally {
      if (mounted) setState(() => _requestingPayout = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Histórico
  // ---------------------------------------------------------------------------

  Widget _buildFilters(AppLocalizations l10n) {
    final labels = [
      l10n.financeFilterAll,
      l10n.financeFilterIn,
      l10n.financeFilterOut,
      l10n.financeFilterBuy,
      l10n.financeFilterGifts,
      l10n.financeFilterRefunds,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Row(
        children: List.generate(labels.length, (i) {
          final sel = _historyFilter == i;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : Colors.white60,
                ),
              ),
              selected: sel,
              onSelected: (_) => setState(() => _historyFilter = i),
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

  List<Map<String, dynamic>> get _filteredHistory {
    if (_historyFilter == 0) return _history;
    return _history.where((h) {
      final kind = h['kind']?.toString() ?? '';
      final status = h['status']?.toString() ?? '';
      switch (_historyFilter) {
        case 1: // Entradas
          return kind == 'earning' || (kind == 'order' && status == 'paid');
        case 2: // Saídas
          return kind == 'refund' || kind == 'payout';
        case 3: // Compras
          return kind == 'order';
        case 4: // Presentes (ganhos)
          return kind == 'earning';
        case 5: // Reembolsos
          return kind == 'refund';
      }
      return true;
    }).toList();
  }

  Widget _historyTile(Map<String, dynamic> h, AppLocalizations l10n) {
    final kind = h['kind']?.toString() ?? 'order';
    final credits = (h['credits'] as num?)?.toInt() ?? 0;
    final status = h['status']?.toString() ?? '';
    final priceCents = (h['price_cents'] as num?)?.toDouble() ?? 0;
    final label = switch (kind) {
      'earning' => l10n.financeKindEarning,
      'refund' => l10n.financeKindRefund,
      'payout' => l10n.financeKindPayout,
      _ => l10n.financeKindOrder,
    };
    final isIn = kind == 'earning' || (kind == 'order' && status == 'paid');
    final color = isIn ? const Color(0xFF34D399) : const Color(0xFFFF6B81);

    final subtitleParts = <String>[];
    if (kind == 'order' && priceCents > 0) subtitleParts.add(_brl(priceCents));
    subtitleParts.add(status);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          isIn ? Icons.add_rounded : Icons.remove_rounded,
          color: color,
          size: 18,
        ),
      ),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: Text(
        '${isIn ? '+' : ''}$credits credits',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Auxiliares
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

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _emptyBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF15131E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.hourglass_empty_rounded,
            color: Colors.white24,
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Colors.white38,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              l10n.walletLoadFail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
            if (kDebugMode && _debugError != null) ...[
              const SizedBox(height: 8),
              Text(
                _debugError!,
                textAlign: TextAlign.center,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white30,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(Object? v) {
    final n = (v is num ? v : 0).toDouble();
    return NumberFormat.compact(locale: 'pt').format(n);
  }

  String _brl(double cents) {
    final reais = cents / 100;
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(reais);
  }
}

/// Dialog honesto enquanto o pagamento é verificado no backend.
class _ProcessingDialog extends StatelessWidget {
  const _ProcessingDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: const Color(0xFF1B1A26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: Color(0xFF8B5CF6),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.financeProcessingTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.financeProcessingBody,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
