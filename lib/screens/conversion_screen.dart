import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/conversion_service.dart';
import '../services/gift_service.dart';

/// Conversão/resgate de moedas do KLAY K.
///
/// Mostra as regras ativas (backend), permite criar um pedido (o backend
/// RESERVA o saldo de forma atômica) e listar/cancelar pedidos próprios.
/// Toda validação de saldo/permissão acontece no servidor.
class ConversionScreen extends StatefulWidget {
  const ConversionScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ConversionScreen()));
  }

  @override
  State<ConversionScreen> createState() => _ConversionScreenState();
}

class _ConversionScreenState extends State<ConversionScreen> {
  final ConversionService _svc = ConversionService.instance;
  List<Map<String, dynamic>> _settings = const [];
  List<Map<String, dynamic>> _history = const [];
  Map<String, dynamic> _wallet = const {};
  bool _loading = true;
  String? _error;

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
      final results = await Future.wait([
        _svc.settings(),
        _svc.history(),
        GiftService.instance.fetchWalletCurrencies(),
      ]);
      if (!mounted) return;
      setState(() {
        _settings = (results[0] as List<Map<String, dynamic>>?) ?? const [];
        _history = (results[1] as List<Map<String, dynamic>>?) ?? const [];
        _wallet = (results[2] as Map<String, dynamic>?) ?? const {};
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

  Future<void> _create(Map<String, dynamic> setting) async {
    final l10n = AppLocalizations.of(context)!;
    final from = setting['from_currency']?.toString() ?? 'credits';
    final balance = _balance(from);
    final min = (setting['min_amount'] as num?)?.toInt() ?? 1;
    final max = (setting['max_amount'] as num?)?.toInt() ?? balance;
    final controller = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1424),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          l10n.conversionDialogTitle(setting['name'].toString()),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l10n.conversionAmountHint(max, min),
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF2A2A35),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(controller.text.trim())),
            child: Text(l10n.conversionReserve),
          ),
        ],
      ),
    );
    if (amount == null || !mounted) return;
    if (amount < min || amount > max) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.conversionAmountOutOfRange(max, min))),
      );
      return;
    }
    try {
      final res = await _svc.request(settingId: setting['id'], amount: amount);
      if (!mounted) return;
      if (res['ok'] == true) {
        GiftService.instance.invalidateWalletCache();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.conversionCreated)));
        _load();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_msg(l10n, res['error']))));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_msg(l10n, e))));
    }
  }

  Future<void> _cancel(Map<String, dynamic> request) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final res = await _svc.cancel(request['id']);
      if (!mounted) return;
      if (res['ok'] == true) {
        GiftService.instance.invalidateWalletCache();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.conversionCancelled)));
        _load();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_msg(l10n, res['error']))));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_msg(l10n, e))));
    }
  }

  String _statusLabel(AppLocalizations l10n, String s) {
    switch (s) {
      case 'pending':
        return l10n.conversionStatusPending;
      case 'approved':
        return l10n.conversionStatusApproved;
      case 'rejected':
        return l10n.conversionStatusRejected;
      case 'cancelled':
        return l10n.conversionStatusCancelled;
      case 'executed':
        return l10n.conversionStatusExecuted;
      default:
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12101A),
        title: Text(
          l10n.conversionTitle,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
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
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    l10n.conversionRulesTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_settings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.lock_clock_rounded,
                            color: Colors.white24,
                            size: 30,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.conversionNoSettingsTitle,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.conversionNoSettingsBody,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white30,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._settings.map((s) => _settingCard(context, s)),
                  const SizedBox(height: 24),
                  Text(
                    l10n.conversionMyRequests,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_history.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        l10n.conversionNoRequests,
                        style: const TextStyle(color: Colors.white38),
                      ),
                    )
                  else
                    ..._history.map((h) => _requestCard(context, h)),
                ],
              ),
            ),
    );
  }

  Widget _settingCard(BuildContext context, Map<String, dynamic> s) {
    final l10n = AppLocalizations.of(context)!;
    final from = s['from_currency']?.toString() ?? '?';
    final to = s['to_currency']?.toString() ?? '?';
    final rate = (s['rate'] as num?)?.toDouble() ?? 1;
    final fee = (s['fee_percent'] as num?)?.toDouble() ?? 0;
    final min = (s['min_amount'] as num?)?.toInt() ?? 1;
    final max = (s['max_amount'] as num?)?.toInt() ?? 0;
    final hasBalance = _balance(from) >= min;
    return Card(
      color: const Color(0xFF1B1A26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.swap_horiz_rounded,
                  color: Color(0xFF8B5CF6),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${s['name']} • $from → $to',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.conversionRateLine(
                fee.toStringAsFixed(0),
                from,
                max,
                min,
                rate,
                to,
              ),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if ((s['description']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                s['description'].toString(),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: hasBalance ? () => _create(s) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                ),
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: Text(
                  hasBalance
                      ? l10n.conversionConvertBalance(_balance(from))
                      : l10n.conversionInsufficientIn(from),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestCard(BuildContext context, Map<String, dynamic> h) {
    final l10n = AppLocalizations.of(context)!;
    final status = h['status']?.toString() ?? 'pending';
    final from = h['from_currency']?.toString() ?? '?';
    final to = h['to_currency']?.toString() ?? '?';
    final amount = (h['amount'] as num?)?.toInt() ?? 0;
    final received = (h['received'] as num?)?.toInt() ?? 0;
    final isPending = status == 'pending';
    final color = isPending
        ? const Color(0xFFFFD700)
        : status == 'executed'
        ? const Color(0xFF34D399)
        : status == 'cancelled'
        ? Colors.white54
        : const Color(0xFFFF6B81);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1724),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$amount $from → $received $to',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _statusLabel(l10n, status),
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ],
            ),
          ),
          if (isPending)
            TextButton(
              onPressed: () => _cancel(h),
              child: Text(
                l10n.cancel,
                style: const TextStyle(color: Color(0xFFFF6B81), fontSize: 12),
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
              l10n.conversionLoadError,
              style: const TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.conversionRetry),
            ),
          ],
        ),
      ),
    );
  }

  String _msg(AppLocalizations l10n, Object? e) {
    final s = e?.toString() ?? '';
    if (s.contains('insufficient_funds')) {
      return l10n.conversionErrInsufficientFunds;
    }
    if (s.contains('amount_out_of_range')) {
      return l10n.conversionErrAmountOutOfRange;
    }
    if (s.contains('setting_not_active')) {
      return l10n.conversionErrSettingNotActive;
    }
    if (s.contains('received_zero')) {
      return l10n.conversionErrReceivedZero;
    }
    if (s.contains('not_found_or_not_pending')) {
      return l10n.conversionErrNotFound;
    }
    if (s.contains('not_authenticated')) {
      return l10n.conversionErrNotAuthenticated;
    }
    return s;
  }
}
